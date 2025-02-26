use starknet::ContractAddress;

#[derive(Drop, Serde)]
pub enum ProposalStatus {
    Pending,
    PollPassed,
    Approved,
    Executed,
    Rejected,
}

#[derive(Drop, Serde)]
pub struct Proposal {
    pub proposal_id: u256,
    pub title: felt252,
    pub description: felt252,
    pub creator_address: ContractAddress,
    pub poll_duration: u256,
    pub binding_duration: u256,
    pub for_votes: u256,
    pub against_votes: u256,
    pub abstain_votes: u256,
    pub status: ProposalStatus,
}

#[derive(starknet::Store, Drop, Serde, Copy)]
pub struct Vote {
    pub voter_address: ContractAddress,
    pub vote_choice: u8 // 0: For, 1: Against, 2: Abstain
}

#[starknet::interface]
pub trait IDAO<TContractState> {
    fn create_proposal(
        ref self: TContractState,
        proposal_id: u256,
        title: felt252,
        description: felt252,
        poll_duration: u256,
        binding_duration: u256,
    );
    fn cast_vote(ref self: TContractState, proposal_id: u256, vote_choice: u8);
    fn delegate_vote(ref self: TContractState, delegatee: ContractAddress);
}

#[starknet::contract]
mod DAO {
    use super::{Proposal, ProposalStatus, Vote, IDAO};
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::storage::{
        Map, StoragePathEntry, StoragePointerReadAccess, StoragePointerWriteAccess,
    };

    #[storage]
    struct Storage {
        proposals: Map<u256, Proposal>,
        has_voted: Map<(u256, ContractAddress), bool>,
        votes: Map<(u256, ContractAddress), Vote>,
        delegated_votes: Map<ContractAddress, ContractAddress>,
    }

    #[abi(embed_v0)]
    impl DAOImpl of IDAO<ContractState> {
        fn create_proposal(
            ref self: ContractState,
            proposal_id: u256,
            title: felt252,
            description: felt252,
            poll_duration: u256,
            binding_duration: u256,
        ) {
            let caller = get_caller_address();
            let proposal = Proposal {
                proposal_id,
                title,
                description,
                creator_address: caller,
                poll_duration,
                binding_duration,
                for_votes: 0,
                against_votes: 0,
                abstain_votes: 0,
                status: ProposalStatus::Pending,
            };

            // Write the proposal to the proposals map
            self.proposals.entry(proposal_id).write(proposal);
        }

        fn cast_vote(ref self: ContractState, proposal_id: u256, vote_choice: u8) {
            let caller = get_caller_address();

            // Check if the caller has already voted
            let has_voted = self.has_voted.entry((proposal_id, caller)).read();
            assert(!has_voted, 'Already voted');

            // Create a new vote
            let vote = Vote { voter_address: caller, vote_choice };

            // Write the vote to the votes map
            self.votes.entry((proposal_id, caller)).write(vote);

            // Mark the caller as having voted
            self.has_voted.entry((proposal_id, caller)).write(true);

            // Update the proposal's vote counts
            let mut proposal = self.proposals.entry(proposal_id).read();
            match vote_choice {
                0 => proposal.for_votes += 1,
                1 => proposal.against_votes += 1,
                2 => proposal.abstain_votes += 1,
                _ => panic!("Invalid vote choice"),
            };

            // Write the updated proposal back to storage
            self.proposals.entry(proposal_id).write(proposal);
        }

        fn delegate_vote(ref self: ContractState, delegatee: ContractAddress) {
            let caller = get_caller_address();

            // Write the delegation to the delegated_votes map
            self.delegated_votes.entry(caller).write(delegatee);
        }
    }
}
