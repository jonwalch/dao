// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Dao.sol";
import "./NftMarketplace.sol";

contract DaoTest is Test, Dao {
    address public constant deployer = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;
    string public constant ERROR_MESSAGE = "DAO Collector: execute call reverted without message";

    uint256 public constant alicePk = 1;
    address public alice;
    address public constant bob = address(300_000_000);
    address public constant ronnie = address(400_000_000);
    address public constant donnie = address(500_000_000);
    address public constant jonny = address(600_000_000);
    address public constant one = address(1);
    address public constant two = address(2);
    address public constant three = address(3);
    address public constant four = address(4);
    address public constant five = address(5);
    address public constant six = address(6);
    address public constant seven = address(7);
    address public constant eight = address(8);
    address public constant nine = address(9);

    uint8 public constant numNFTs = 3;

    address[] targets;
    uint256[] values;
    bytes[] calldatas;
    string description = "dis a good one bruh";
    bytes32 descriptionHash = keccak256(bytes(description));

    uint256 propID;

    address[] public users;

    Dao public dao;
    NftMarketplaceImpl public nft;

    function setUp() public {
        alice = vm.addr(alicePk);
        dao = new Dao();
        nft = new NftMarketplaceImpl(numNFTs);

        address[] memory _targets = new address[](1);
        _targets[0] = address(nft);
        targets = _targets;

        uint256[] memory _values = new uint256[](1);
        _values[0] = 0.9 ether;
        values = _values;

        bytes[] memory _calldatas = new bytes[](1);
        _calldatas[0] = abi.encodeWithSignature("buy(address,uint256)", address(nft), 0);
        calldatas = _calldatas;

        address[] memory _users = new address[](14);
        _users[0] = alice;
        _users[1] = bob;
        _users[2] = ronnie;
        _users[3] = donnie;
        _users[4] = jonny;
        _users[5] = one;
        _users[6] = two;
        _users[7] = three;
        _users[8] = four;
        _users[9] = five;
        _users[10] = six;
        _users[11] = seven;
        _users[12] = eight;
        _users[13] = nine;

        users = _users;

        propID = dao.hashProposal(targets, values, calldatas, descriptionHash);
    }

    function seedMembers() public {
        for (uint i = 0; i < users.length; i++) {
            hoax(users[i]);
            dao.joinDao{value: 1 ether}();
        }
    }

    function generateDigestTest(uint256 proposalId, uint8 support) public view returns (bytes32) {
        bytes32 domainSeparator = keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(NAME)), keccak256(bytes(VERSION)), getChainIdInternal(), address(dao)));
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        return digest;
    }

    function testMarketplaceHasNFTs() public {
        assertEq(nft.balanceOf(address(nft)), numNFTs);
    }

    function testCantJoinWrongAmount() public {
        vm.expectRevert(WrongJoinAmount.selector);
        dao.joinDao();

        vm.expectRevert(WrongJoinAmount.selector);
        dao.joinDao{value: 1.00001 ether}();

        vm.expectRevert(WrongJoinAmount.selector);
        dao.joinDao{value: 0.99999 ether}();
    }

    function testJoinDao() public {
        vm.expectEmit(true,true,true,true);
        emit JoinedDao(deployer);
        dao.joinDao{value: 1 ether}();

        assertEq(address(dao).balance, 1 ether);
    }

    function testCantDoubleJoinDao() public {
        dao.joinDao{value: 1 ether}();
        assertEq(address(dao).balance, 1 ether);

        vm.expectRevert(AlreadyMember.selector);
        dao.joinDao{value: 1 ether}();

        assertEq(address(dao).balance, 1 ether);
    }

    function testCantProposeNotMember() public {
        vm.expectRevert(NotMember.selector);
        dao.propose(targets, values, calldatas, description);
    }

    function testPropose() public {
        dao.joinDao{value: 1 ether}();

        vm.expectEmit(true,true,true,true);
        emit ProposalCreated(
            dao.hashProposal(targets, values, calldatas, keccak256(bytes(description))),
            deployer,
            targets,
            values,
            calldatas,
            block.timestamp + 7 days,
            description
        );
        dao.propose(targets, values, calldatas, description);
    }

    function testBadProposeArgs() public {
        dao.joinDao{value: 1 ether}();

        // targets length 0
        vm.expectRevert(ProposeMalformedArgs.selector);
        dao.propose(new address[](0), values, calldatas, description);

        //targets != values length
        vm.expectRevert(ProposeMalformedArgs.selector);
        dao.propose(targets, new uint256[](0), calldatas, description);

        //targets != calldatas length
        vm.expectRevert(ProposeMalformedArgs.selector);
        dao.propose(targets, values, new bytes[](0), description);
    }

    function testCantProposeTwoActive() public {
        dao.joinDao{value: 1 ether}();

        dao.propose(targets, values, calldatas, description);
        vm.expectRevert(NoTwoActiveProposals.selector);
        dao.propose(targets, values, calldatas, "different description");
    }

    function testProposalAlreadyExists() public {
        dao.joinDao{value: 1 ether}();
        dao.propose(targets, values, calldatas, description);

        hoax(alice);
        dao.joinDao{value: 1 ether}();

        hoax(alice);
        vm.expectRevert(ProposalExistsAlready.selector);
        dao.propose(targets, values, calldatas, description);
    }

    function testCanProposeDifferentString() public {
        dao.joinDao{value: 1 ether}();
        dao.propose(targets, values, calldatas, description);

        hoax(alice);
        dao.joinDao{value: 1 ether}();

        hoax(alice);
        dao.propose(targets, values, calldatas, "different description");
    }

    function testCanProposeAfterSuccess() public {
        testVotingReachQuorum();
        hoax(alice);
        dao.propose(targets, values, calldatas, "different description");
    }

    function testCanProposeAfterDefeat() public {
        testVotingFailReachQuorum();
        hoax(alice);
        dao.propose(targets, values, calldatas, "different description");
    }

    function testCanProposeAfterDefeatNoQuorum() public {
        testVotingFailsNoQuorum();
        hoax(alice);
        dao.propose(targets, values, calldatas, "different description");
    }

    function testCanProposeAfterExecuted() public {
        testVotingFailReachQuorum();
        hoax(alice);
        dao.propose(targets, values, calldatas, "different description");
    }

    function testCantVoteNotMember() public {
        dao.joinDao{value: 1 ether}();
        dao.propose(targets, values, calldatas, description);

        vm.expectRevert(NotMember.selector);
        hoax(alice);
        dao.castVote(propID, uint8(VoteType.For));
    }

    function testCantVoteTwice() public {
        dao.joinDao{value: 1 ether}();
        dao.propose(targets, values, calldatas, description);
        dao.castVote(propID, uint8(VoteType.For));

        vm.expectRevert(AlreadyVoted.selector);
        dao.castVote(propID, uint8(VoteType.For));
    }

    function testInvalidVoteValue() public {
        dao.joinDao{value: 1 ether}();
        dao.propose(targets, values, calldatas, description);

        vm.expectRevert(InvalidValueForVote.selector);
        dao.castVote(propID, 2);
    }

    function testCantFindProposal() public {
        vm.expectRevert(CantFindProposal.selector);
        dao.proposalState(0);
    }

    function testVotingReachQuorum() public {
        seedMembers();

        hoax(alice);
        dao.propose(targets, values, calldatas, description);

        for (uint i = 0; i < users.length / 2 + 1; i++) {
            hoax(users[i]);
            vm.expectEmit(true,true,true,true);
            emit VoteCast(users[i], propID, uint8(VoteType.For));
            dao.castVote(propID, uint8(VoteType.For));
        }

        for (uint i = users.length / 2 + 1; i < users.length; i++) {
            hoax(users[i]);
            vm.expectEmit(true,true,true,true);
            emit VoteCast(users[i], propID, uint8(VoteType.Against));
            dao.castVote(propID, uint8(VoteType.Against));
        }

        assertEq(uint256(ProposalState.Active), uint256(dao.proposalState(propID)));

        vm.warp(block.timestamp + 7 days);

        assertEq(uint256(ProposalState.Succeeded), uint256(dao.proposalState(propID)));

    }

    function testVotingFailReachQuorum() public {
        seedMembers();

        hoax(alice);
        dao.propose(targets, values, calldatas, description);

        for (uint i = 0; i < users.length / 2; i++) {
            hoax(users[i]);
            dao.castVote(propID, uint8(VoteType.For));
        }

        for (uint i = users.length / 2; i < users.length; i++) {
            hoax(users[i]);
            dao.castVote(propID, uint8(VoteType.Against));
        }

        assertEq(uint256(ProposalState.Active), uint256(dao.proposalState(propID)));

        vm.warp(block.timestamp + 7 days);

        assertEq(uint256(ProposalState.Defeated), uint256(dao.proposalState(propID)));

    }

    function testVotingFailsNoQuorum() public {
        seedMembers();

        hoax(alice);
        dao.propose(targets, values, calldatas, description);

        for (uint i = 0; i < 2; i++) {
            hoax(users[i]);
            dao.castVote(propID, uint8(VoteType.For));
        }

        assertEq(uint256(ProposalState.Active), uint256(dao.proposalState(propID)));

        vm.warp(block.timestamp + 7 days);

        assertEq(uint256(ProposalState.Defeated), uint256(dao.proposalState(propID)));

        hoax(users[2]);
        vm.expectRevert(VoteNotActive.selector);
        dao.castVote(propID, uint8(VoteType.For));
    }

    function testExecution() public {
        testVotingReachQuorum();

        vm.expectEmit(true,true,true,true);
        emit ProposalExecuted(propID);
        dao.execute(targets, values, calldatas, descriptionHash);

        assertEq(1, nft.balanceOf(address(dao)));
        assertEq(address(dao), nft.ownerOf(0));

        assertEq(uint256(ProposalState.Executed), uint256(dao.proposalState(propID)));
    }

    function testExecutionCantFindProposal() public {
        vm.expectRevert(CantFindProposal.selector);
        dao.execute(targets, values, calldatas, descriptionHash);
    }

    function testExecutionProposalActive() public {
        testPropose();
        vm.expectRevert(ProposalNotSucceeded.selector);
        dao.execute(targets, values, calldatas, descriptionHash);
    }

    function testExecutionProposalDefeated() public {
        testVotingFailReachQuorum();
        vm.expectRevert(ProposalNotSucceeded.selector);
        dao.execute(targets, values, calldatas, descriptionHash);
    }

    function testExecutionProposalExecuted() public {
        testExecution();
        vm.expectRevert(ProposalNotSucceeded.selector);
        dao.execute(targets, values, calldatas, descriptionHash);
    }

    function testExecuteNotEnoughValue() public {
        testVotingReachQuorum();

        deal(address(dao), 0);
        vm.expectRevert(bytes(ERROR_MESSAGE));
        dao.execute(targets, values, calldatas, descriptionHash);
    }

    function testMultipleTargets() public {
        // test calls safeTransferFrom after calling buy
        seedMembers();

        address[] memory _targets = new address[](2);
        _targets[0] = address(nft);
        _targets[1] = address(nft);
        uint256[] memory _values = new uint256[](2);
        _values[0] = 0.9 ether;
        _values[1] = 0;
        bytes[] memory _calldatas = new bytes[](2);
        _calldatas[0] = abi.encodeWithSignature("buy(address,uint256)", address(nft), 0);
        _calldatas[1] = abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", address(dao), address(nft), 0);

        uint256 _propID = dao.hashProposal(_targets, _values, _calldatas, descriptionHash);

        hoax(alice);
        dao.propose(_targets, _values, _calldatas, description);

        for (uint i = 0; i < users.length / 2 + 1; i++) {
            hoax(users[i]);
            vm.expectEmit(true,true,true,true);
            emit VoteCast(users[i], _propID, uint8(VoteType.For));
            dao.castVote(_propID, uint8(VoteType.For));
        }

        for (uint i = users.length / 2 + 1; i < users.length; i++) {
            hoax(users[i]);
            vm.expectEmit(true,true,true,true);
            emit VoteCast(users[i], _propID, uint8(VoteType.Against));
            dao.castVote(_propID, uint8(VoteType.Against));
        }

        assertEq(uint256(ProposalState.Active), uint256(dao.proposalState(_propID)));

        vm.warp(block.timestamp + 7 days);

        assertEq(uint256(ProposalState.Succeeded), uint256(dao.proposalState(_propID)));

        dao.execute(_targets, _values, _calldatas, descriptionHash);
        assertEq(0, nft.balanceOf(address(dao)));
        assertEq(address(nft), nft.ownerOf(0));

        assertEq(uint256(ProposalState.Executed), uint256(dao.proposalState(_propID)));
    }

    function testVoteSig() public {
        seedMembers();

        hoax(alice);
        dao.propose(targets, values, calldatas, description);

        bytes32 aliceMessage = generateDigestTest(propID, uint8(VoteType.For));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, aliceMessage);

        //call as someone else
        hoax(bob);
        vm.expectEmit(true,true,true,true);
        emit VoteCast(alice, propID, uint8(VoteType.For));
        dao.castVoteBySig(propID, uint8(VoteType.For), v, r, s);
    }

    function testCantVoteSigAfterVote() public {
        uint256 randoPk = 2;
        address rando = vm.addr(randoPk);
        bytes32 randoMessage = generateDigestTest(propID, uint8(VoteType.For));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(randoPk, randoMessage);

        hoax(rando);
        dao.joinDao{value: 1 ether}();
        hoax(rando);
        dao.propose(targets, values, calldatas, description);
        hoax(rando);
        dao.castVote(propID, uint8(VoteType.For));

        hoax(bob);
        vm.expectRevert(AlreadyVoted.selector);
        dao.castVoteBySig(propID, uint8(VoteType.For), v, r, s);
    }

    function testCantVoteAfterSigVote() public {
        testVoteSig();

        hoax(alice);
        vm.expectRevert(AlreadyVoted.selector);
        dao.castVote(propID, uint8(VoteType.For));
    }

    function testCantReplaySig() public {
        testVoteSig();

        bytes32 aliceMessage = generateDigestTest(propID, uint8(VoteType.For));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, aliceMessage);

        //call as someone else
        hoax(bob);
        vm.expectRevert(AlreadyVoted.selector);
        dao.castVoteBySig(propID, uint8(VoteType.For), v, r, s);
    }

    function testVoteSigWrongSigner() public {
        seedMembers();

        hoax(alice);
        dao.propose(targets, values, calldatas, description);

        uint256 randoPk = 2;
        address rando = vm.addr(randoPk);

        bytes32 randoMessage = generateDigestTest(propID, uint8(VoteType.For));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(randoPk, randoMessage);

        //call as someone else
        hoax(bob);
        vm.expectRevert(NotMember.selector);
        dao.castVoteBySig(propID, uint8(VoteType.For), v, r, s);
    }

    function testVoteSigInvalidSignature() public {
        seedMembers();

        hoax(alice);
        dao.propose(targets, values, calldatas, description);

        uint256 randoPk = 2;
        address rando = vm.addr(randoPk);

        bytes32 randoMessage = generateDigestTest(propID, uint8(VoteType.For));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(randoPk, randoMessage);

        //call as someone else
        hoax(bob);
        vm.expectRevert(InvalidSignature.selector);
        //wrong v
        dao.castVoteBySig(propID, uint8(VoteType.For), 17, r, s);
    }

    function testVoteSigNotMember() public {
        seedMembers();

        hoax(alice);
        dao.propose(targets, values, calldatas, description);

        uint256 randoPk = 2;
        address rando = vm.addr(randoPk);

        bytes32 randoMessage = generateDigestTest(propID, uint8(VoteType.For));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(randoPk, randoMessage);

        hoax(bob);
        vm.expectRevert(NotMember.selector);
        dao.castVoteBySig(propID, uint8(VoteType.For), v, r, s);
    }

    function testVoteSigExpiredProposal() public {
        seedMembers();

        hoax(alice);
        dao.propose(targets, values, calldatas, description);

        bytes32 aliceMessage = generateDigestTest(propID, uint8(VoteType.For));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, aliceMessage);

        vm.warp(block.timestamp + 7 days);

        //call as someone else
        hoax(bob);
        vm.expectRevert(VoteNotActive.selector);
        dao.castVoteBySig(propID, uint8(VoteType.For), v, r, s);
    }

    function testBulkVoteSig() public {
        uint256 randoPk = 2;
        address rando = vm.addr(randoPk);

        hoax(rando);
        dao.joinDao{value: 1 ether}();
        seedMembers();

        hoax(alice);
        dao.propose(targets, values, calldatas, description);

        bytes32 aliceMessage = generateDigestTest(propID, uint8(VoteType.For));
        (uint8 vAlice, bytes32 rAlice, bytes32 sAlice) = vm.sign(alicePk, aliceMessage);

        bytes32 randoMessage = generateDigestTest(propID, uint8(VoteType.For));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(randoPk, randoMessage);

        SigVote memory al = SigVote(propID, rAlice, sAlice, uint8(VoteType.For), vAlice);
        SigVote memory ra = SigVote(propID, r, s, uint8(VoteType.For), v);

        SigVote[] memory sv = new SigVote[](2);
        sv[0] = al;
        sv[1] = ra;

        dao.bulkCastVoteBySig(sv);
    }

    function testBuyFromMarketplace() public {
        seedMembers();

        address[] memory _targets = new address[](1);
        _targets[0] = address(dao);
        uint256[] memory _values = new uint256[](1);
        _values[0] = 0;
        bytes[] memory _calldatas = new bytes[](1);
        _calldatas[0] = abi.encodeWithSignature(
            "buyFromMarketplace(address,address,uint256,uint256)",
            nft,
            address(nft),
            0,
            0.9 ether);

        uint256 _propID = dao.hashProposal(_targets, _values, _calldatas, descriptionHash);

        hoax(alice);
        dao.propose(_targets, _values, _calldatas, description);

        for (uint i = 0; i < users.length / 2 + 1; i++) {
            hoax(users[i]);
            vm.expectEmit(true,true,true,true);
            emit VoteCast(users[i], _propID, uint8(VoteType.For));
            dao.castVote(_propID, uint8(VoteType.For));
        }

        for (uint i = users.length / 2 + 1; i < users.length; i++) {
            hoax(users[i]);
            vm.expectEmit(true,true,true,true);
            emit VoteCast(users[i], _propID, uint8(VoteType.Against));
            dao.castVote(_propID, uint8(VoteType.Against));
        }

        assertEq(uint256(ProposalState.Active), uint256(dao.proposalState(_propID)));

        vm.warp(block.timestamp + 7 days);

        assertEq(uint256(ProposalState.Succeeded), uint256(dao.proposalState(_propID)));

        dao.execute(_targets, _values, _calldatas, descriptionHash);

        assertEq(1, nft.balanceOf(address(dao)));
        assertEq(address(dao), nft.ownerOf(0));

        assertEq(uint256(ProposalState.Executed), uint256(dao.proposalState(_propID)));

    }

    function testBadPriceFromMarketplace() public {
        seedMembers();

        address[] memory _targets = new address[](1);
        _targets[0] = address(dao);
        uint256[] memory _values = new uint256[](1);
        _values[0] = 0;
        bytes[] memory _calldatas = new bytes[](1);
        _calldatas[0] = abi.encodeWithSignature(
            "buyFromMarketplace(address,address,uint256,uint256)",
            nft,
            address(nft),
            0,
            0.8 ether);

        uint256 _propID = dao.hashProposal(_targets, _values, _calldatas, descriptionHash);

        hoax(alice);
        dao.propose(_targets, _values, _calldatas, description);

        for (uint i = 0; i < users.length / 2 + 1; i++) {
            hoax(users[i]);
            vm.expectEmit(true,true,true,true);
            emit VoteCast(users[i], _propID, uint8(VoteType.For));
            dao.castVote(_propID, uint8(VoteType.For));
        }

        for (uint i = users.length / 2 + 1; i < users.length; i++) {
            hoax(users[i]);
            vm.expectEmit(true,true,true,true);
            emit VoteCast(users[i], _propID, uint8(VoteType.Against));
            dao.castVote(_propID, uint8(VoteType.Against));
        }

        assertEq(uint256(ProposalState.Active), uint256(dao.proposalState(_propID)));

        vm.warp(block.timestamp + 7 days);

        assertEq(uint256(ProposalState.Succeeded), uint256(dao.proposalState(_propID)));

        vm.expectRevert(abi.encodeWithSelector(PriceTooHigh.selector, 0.9 ether, 0.8 ether));
        dao.execute(_targets, _values, _calldatas, descriptionHash);

        assertEq(0, nft.balanceOf(address(dao)));
        assertEq(address(nft), nft.ownerOf(0));

        assertEq(uint256(ProposalState.Succeeded), uint256(dao.proposalState(_propID)));

    }

    function testWrongBuyCaller() public {
        vm.expectRevert(InvalidCall.selector);
        dao.buyFromMarketplace(nft, address(nft), 0, 1 ether);
    }

    function testNotExecuteCaller() public {
        vm.expectRevert(MustBeCalledByExecute.selector);
        hoax(address(dao));
        dao.buyFromMarketplace(nft, address(nft), 0, 1 ether);
    }
}
