// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

error WrongJoinAmount();
error NotMember();
error AlreadyMember();
error ProposeMalformedArgs();
error ProposalExistsAlready();
error NoTwoActiveProposals();
error CantFindProposal();
error VoteNotActive();
error AlreadyVoted();
error InvalidValueForVote();
error InvalidSignature();
error SignatureExpired();
error ProposalNotSucceeded();
error ExecutionFailed();
error InvalidCall();
error MustBeCalledByExecute();
error PriceTooHigh(uint256 price, uint256 maxPrice);

interface NftMarketplace {
    function getPrice(address nftContract, uint nftId) external returns (uint price);
    function buy(address nftContract, uint nftId) external payable returns (bool success);
}

contract Dao {

    enum ProposalState {Active, Succeeded, Executed, Defeated}
    enum VoteType {For, Against}

    struct Proposal {
        uint256 voteEnd;
        uint256 votesFor;
        uint256 votesAgainst;
        bool executed;
        mapping(address => bool) hasVoted;
    }

    struct SigVote {
        uint256 proposalId;
        bytes32 r;
        bytes32 s;
        uint8 support;
        uint8 v;
    }

    uint256 memberCount;
    uint256 private constant VOTE_DURATION = 7 days;
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support)");
    uint8 private constant QUORUM = 4; // 25% when used to multiply
    string public constant NAME = "DAO Governor";
    string public constant VERSION = "0.1";
    string private constant ERROR_MESSAGE = "DAO Collector: execute call reverted without message";
    bool private executing;

    mapping(address => bool) private members;
    mapping(uint256 => Proposal) private _proposals;
    mapping(address => uint256) private memberCurrentProposal;

    event JoinedDao(address member);
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        bytes[] calldatas,
        uint256 voteEnd,
        string description
    );
    event VoteCast(address indexed, uint256 proposalId, uint8 support);
    event ProposalExecuted(uint256 proposalId);

    modifier onlyMember(address a) {
        if (!members[a]) revert NotMember();
        _;
    }

    constructor() {}

    function joinDao() external payable {
        if (msg.value != 1 ether) revert WrongJoinAmount();
        if (members[msg.sender]) revert AlreadyMember();

        members[msg.sender] = true;
        memberCount += 1;
        emit JoinedDao(msg.sender);
    }

    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public pure returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
    }

    function _quorumReached(uint256 proposalId) internal view returns (bool) {
        Proposal storage proposal = _proposals[proposalId];
        return (proposal.votesFor + proposal.votesAgainst) * QUORUM >= memberCount;
    }

    function _voteSucceeded(uint256 proposalId) internal view returns (bool) {
        Proposal storage proposal = _proposals[proposalId];
        return proposal.votesFor > proposal.votesAgainst;
    }

    function proposalState(uint256 proposalId) public view returns (ProposalState) {
        Proposal storage proposal = _proposals[proposalId];

        if (proposal.executed) {
            return ProposalState.Executed;
        }

        if (proposal.voteEnd == 0) revert CantFindProposal();

        if (proposal.voteEnd > block.timestamp) {
            return ProposalState.Active;
        }

        if (_quorumReached(proposalId) && _voteSucceeded(proposalId)) {
            return ProposalState.Succeeded;
        }

        return ProposalState.Defeated;
    }

    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external onlyMember(msg.sender) {
        if (targets.length == 0 || targets.length != values.length || targets.length != calldatas.length) revert ProposeMalformedArgs();

        uint256 memberProposalId = memberCurrentProposal[msg.sender];
        Proposal storage memberProposal = _proposals[memberProposalId]; //TODO: don't do two reads from storage
        // account for first proposal they ever make
        if (memberProposal.voteEnd != 0 && proposalState(memberProposalId) == ProposalState.Active) revert NoTwoActiveProposals();

        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        Proposal storage proposal = _proposals[proposalId];

        if (proposal.voteEnd != 0) revert ProposalExistsAlready();

        uint256 end = block.timestamp + VOTE_DURATION;
        proposal.voteEnd = end;

        memberCurrentProposal[msg.sender] = proposalId;

        emit ProposalCreated(proposalId, msg.sender, targets, values, calldatas, end, description);
    }

    function castVote(uint256 proposalId, uint8 support) external {
        _castVote(proposalId, msg.sender, support);
    }

    function castVoteBySig(uint256 proposalId, uint8 support, uint8 v, bytes32 r, bytes32 s) public {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(NAME)), keccak256(bytes(VERSION)), getChainIdInternal(), address(this)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        address signer = ecrecover(digest, v, r, s);

        if (signer == address(0)) revert InvalidSignature();

        _castVote(proposalId, signer, support);
    }

    function bulkCastVoteBySig(SigVote[] calldata sigVotes) external {
        for (uint256 i = 0; i < sigVotes.length; i++){
            castVoteBySig(
                sigVotes[i].proposalId,
                sigVotes[i].support,
                sigVotes[i].v,
                sigVotes[i].r,
                sigVotes[i].s);
        }
    }

    function _castVote(
        uint256 proposalId,
        address account,
        uint8 support
    ) internal onlyMember(account) {
        Proposal storage proposal = _proposals[proposalId];

        if (proposalState(proposalId) != ProposalState.Active) revert VoteNotActive();
        if (proposal.hasVoted[account]) revert AlreadyVoted();

        proposal.hasVoted[account] = true;

        if (support == uint8(VoteType.Against)) {
            proposal.votesAgainst += 1;
        } else if (support == uint8(VoteType.For)) {
            proposal.votesFor += 1;
        } else {
            revert InvalidValueForVote();
        }

        emit VoteCast(account, proposalId, support);
    }

    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external payable { // payable so executor can top up funds if necessary

        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        ProposalState status = proposalState(proposalId);

        if (status != ProposalState.Succeeded) revert ProposalNotSucceeded();

        executing = true;
        _proposals[proposalId].executed = true;
        emit ProposalExecuted(proposalId);

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory returndata) = targets[i].call{value: values[i]}(calldatas[i]);
            if (!success) {
                if (returndata.length > 0) {
                    assembly {
                        let returndata_size := mload(returndata)
                        revert(add(32, returndata), returndata_size)
                    }
                } else {
                    revert(ERROR_MESSAGE);
                }

            }
        }
        executing = false;
    }

    function buyFromMarketplace(
        NftMarketplace marketplace,
        address nftContract,
        uint256 nftId,
        uint256 maxPrice
    ) external {
        if (msg.sender != address(this)) revert InvalidCall();
        if (!executing) revert MustBeCalledByExecute();

        uint256 price = marketplace.getPrice(nftContract, nftId);
        if (maxPrice < price) revert PriceTooHigh(price, maxPrice);

        marketplace.buy{value: price}(nftContract, nftId);
    }

    function getChainIdInternal() internal view returns (uint256) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data)
    public returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
