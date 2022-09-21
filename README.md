# DAO Project

I wrote this project as part of the Macro Smart Contract Security Engineering Fellowship. https://0xmacro.com/engineering-fellowship

## Technical Spec
<!-- Here you should list your DAO specification. You have some flexibility on how you want your DAO's voting system to work and Proposals should be stored, and you need to document that here so that your staff micro-auditor knows what spec to compare your implementation to.  -->
The majority of this is covered in my Proposal System Spec and my Voting System spec.

The constructor takes no arguments because it doesn't need to initialize any state.

We rely on propose.VoteEnd == 0 to denote a proposal that has not been created, since 0 is the default value.

We maintain a mapping between address => uint256 to enforce only one active proposal per member. 
This exists to add some friction in spamming proposals.

`bulkCastVoteBySig` exists as a convenience function to do many `castVoteBySig` call without having to pay as much gas.

We implement `onERC721Received` so our contract can actually hold NFTs. 
We can execute arbitrary function calls if a proposal succeeds, so we can transfer ether, NFTs, etc.

Signed votes cannot be replayed, because we check if that user has already voted.

### Proposal System Spec

Only members can propose.

Members can only have one active proposal at a time. They must wait for their previous proposal to succeed or be defeated before they can propose another.

I’ll save gas by only storing the hash of the proposal data and rely on some off-chain database to retain proposal data.

The proposal hash is a uint256 that uses targets,values,calldatas, and the hash of the description.

Identical proposals will be rejected. changing the description will allow a new proposal to be created, even if targets, values, calldatas are all identical.

Anyone can execute succeeded proposals. Proposals can only be executed in the Succeeded state.
The execute function is payable, in case there isn’t enough ether in the contract to execute the proposal.
Quorum is at 25% of total members and counts all parties who voted, regardless of for or against. The 25% is rounded down
to the nearest integer.

Proposals cannot be cancelled.

Proposals will have the following states:

Executed - succeeded proposal’s functions have been executed

Active - Always from creation to creation + 7 days.

Succeeded - After 7 days. Quorum reached + voteFor > votesAgainst

Defeated - Afters 7 days. Quorum reached + votesFor ≤ votesAgainst OR quorum not reached

### Voting System Spec

Each address can only contribute 1 ether, this makes them a member.

Only members can vote, once per Proposal.

Each vote has a weight of 1.

Members cannot change votes once submitted.

Members can sign a message off-chain and have someone else submit their vote.

Signed votes conform to EIP-712, specifically Ethereum Signed Typed Data, created from a `domainSeparator` and a `structHash`.

Voting is always open for 7 days following proposal creation.

There are two voting options, For and Against.

Votes do not accept arbitrary reason strings.

## Design / The risks and tradeoffs of system:

I made the system quite simple. There are a few issues that could arise that will fall on members to avoid.
Members are responsible for all of their targets,values, and calldatas to be valid. Contract balance may need to be
topped up by sending ether to execute function as outlined above.

Signature votes were kept simple. They cannot be replayed. They don't need deadlines because proposal already enfore
deadlines. Including the signer in the message also felt like overkill. The odds that someone games illegitimate
signatures votes that spit out the valid members are very small and very expensive to attempt.

System is not sybil resistant, a whale could easily have a ton of public keys and own a ton of memberships.
A whale could coordinate an attack where they make up a large percentage of memberships, and send themselves all the
ether and NFTs held in the contract.

This attack could be mitigated by introducing a Queued period after a vote succeeds, and allowing members to gracefully
exit from the DAO at any time. We'd also have to remove any votes they had on Active proposals.

Not including Abstain votes makes it harder to reach quorum. Members without strong opinions or members that are uninterested
could make up a large percentage of total members.

Members currently have no way to leave. This could disincentivize people from joining in the first place, or make it hard
to reach quorum if they lose interest. They could pass a proposal to get their ether back but it would not remove them as a
member.

There are no conditional preferences between proposals i.e. (Vote For Propsal B if Proposal A is Defeated)

Users not being able to change their votes make it easier to bribe them behind the scenes.
