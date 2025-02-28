use core::starknet::ContractAddress;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Proposal {
    pub id: u256,
    pub description: felt252,
    pub creator: ContractAddress,
    pub creation_time: u64,
    pub poll_end_time: u64,
    pub voting_end_time: u64,
    pub vote_for: u256,
    pub vote_against: u256,
    pub state: u8 // 0: Active, 1: Poll Phase, 2: Voting Phase, 3: Executed, 4: Defeated
}
// Interface definition for the DAO contract
#[starknet::interface]
pub trait IDAO<TContractState> {
    fn vote_in_poll(ref self: TContractState, proposal_id: u256, support: bool);
    fn get_proposal(self: @TContractState, proposal_id: u256) -> Proposal;
    fn has_voted(self: @TContractState, proposal_id: u256, voter: ContractAddress) -> bool;
    fn create_proposal(
        ref self: TContractState,
        proposal_id: u256,
        description: felt252,
        poll_duration: u64,
        voting_duration: u64,
    );
    fn tally_poll_votes(ref self: TContractState, proposal_id: u256);
}

#[starknet::contract]
pub mod DAO {
    use starknet::storage::StorageMapWriteAccess;
    use starknet::storage::StorageMapReadAccess;
    use starknet::ContractAddress;
    use starknet::get_caller_address;
    use starknet::get_block_timestamp;
    use core::traits::Into;
    use core::array::ArrayTrait;
    use core::starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, Map};
    use super::Proposal;
    use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};

    pub const PollActive: u8 = 0;
    pub const PollPassed: u8 = 2;
    pub const PollDefeated: u8 = 4;
    use core::panic_with_felt252;

    #[storage]
    struct Storage {
        // xZB token address
        xzb_token: ContractAddress,
        // Proposals data
        proposals: Map<u256, Proposal>,
        // Mapping to track if an address has voted on a proposal
        has_voted: Map<(u256, ContractAddress), bool>,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        PollVoted: PollVoted,
        PollResultUpdated: PollResultUpdated,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PollVoted {
        #[key]
        pub proposal_id: u256,
        #[key]
        pub voter: ContractAddress,
        pub support: bool,
        pub vote_weight: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PollResultUpdated {
        #[key]
        pub proposal_id: u256,
        pub total_for: u256,
        pub total_against: u256,
        pub new_status: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, xzb_token_address: ContractAddress) {
        self.xzb_token.write(xzb_token_address);
    }

    // External functions
    #[abi(embed_v0)]
    impl DAOImpl of super::IDAO<ContractState> {
        fn vote_in_poll(ref self: ContractState, proposal_id: u256, support: bool) {
            // Get the caller's address
            let caller = get_caller_address();

            // Get the proposal
            let mut proposal = self._validate_proposal_exists(proposal_id);

            // Check if the proposal is in the poll phase
            assert(self._is_in_poll_phase(proposal_id), 'Not in poll phase');

            // Check if the caller has already voted
            assert(!self.has_voted.read((proposal_id, caller)), 'Already voted');

            // Check if the proposal exists and is in the poll phase
            assert(proposal.id == proposal_id, 'Proposal does not exist');
            assert(proposal.state == 1, 'Not in poll phase');

            // Check if the current time is within the poll phase
            let current_time = get_block_timestamp();
            assert(current_time <= proposal.poll_end_time, 'Poll phase ended');

            // Check if the caller has already voted
            assert(!self.has_voted.read((proposal_id, caller)), 'Already voted');

            // Get the voter's xZB token balance (vote weight)
            let vote_weight = self._get_voter_weight(caller);

            // Ensure the voter has some voting power
            assert(vote_weight > 0, 'No voting power');

            // Update vote counts based on the support parameter
            self._update_vote_counts(proposal_id, support, vote_weight);

            // Update vote counts based on the support parameter
            if support {
                proposal.vote_for += vote_weight;
            } else {
                proposal.vote_against += vote_weight;
            }

            // Update the proposal
            self.proposals.write(proposal_id, proposal);

            // Mark the caller as having voted
            self.has_voted.write((proposal_id, caller), true);

            // Emit the PollVoted event
            self
                .emit(
                    Event::PollVoted(
                        PollVoted {
                            proposal_id: proposal_id,
                            voter: caller,
                            support: support,
                            vote_weight: vote_weight,
                        },
                    ),
                );
        }

        fn get_proposal(self: @ContractState, proposal_id: u256) -> Proposal {
            let proposal = self.proposals.read(proposal_id);
            assert(proposal.id == proposal_id, 'Proposal does not exist');
            proposal
        }

        fn has_voted(self: @ContractState, proposal_id: u256, voter: ContractAddress) -> bool {
            self.has_voted.read((proposal_id, voter))
        }

        fn create_proposal(
            ref self: ContractState,
            proposal_id: u256,
            description: felt252,
            poll_duration: u64,
            voting_duration: u64,
        ) {
            // Get the caller's address
            let caller = get_caller_address();

            // Get the current timestamp
            let current_time = get_block_timestamp();

            // Create a new proposal
            let proposal = Proposal {
                id: proposal_id,
                description: description,
                creator: caller,
                creation_time: current_time,
                poll_end_time: current_time + poll_duration,
                voting_end_time: current_time + poll_duration + voting_duration,
                vote_for: 0.into(),
                vote_against: 0.into(),
                state: 0 // Active
            };

            // Store the proposal in the storage
            self.proposals.write(proposal_id, proposal);
        }

        fn tally_poll_votes(ref self: ContractState, proposal_id: u256) {
            let mut proposal = self._validate_proposal_exists(proposal_id);

            if proposal.state != PollActive {
                panic_with_felt252('Not in poll phase');
            }

            let total_for = proposal.vote_for;
            let total_against = proposal.vote_against;

            let threshold: u256 = 100.into();

            if total_for >= threshold {
                proposal.state = PollPassed;
                self.proposals.write(proposal_id, proposal);

                // Emit the PollResultUpdated event
                self
                    .emit(
                        Event::PollResultUpdated(
                            PollResultUpdated {
                                proposal_id: proposal_id,
                                total_for: total_for,
                                total_against: total_against,
                                new_status: 'PollPassed'.into(),
                            },
                        ),
                    );
            }
            if total_against >= threshold {
                proposal.state = PollDefeated;
                self.proposals.write(proposal_id, proposal);

                // Emit the PollResultUpdated event
                self
                    .emit(
                        Event::PollResultUpdated(
                            PollResultUpdated {
                                proposal_id: proposal_id,
                                total_for: total_for,
                                total_against: total_against,
                                new_status: 'PollDefeated'.into(),
                            },
                        ),
                    );
            }
        }
    }

    // Internal functions
    #[generate_trait]
    impl InternalFunctions of InternalTrait {
        fn _get_voter_weight(self: @ContractState, voter: ContractAddress) -> u256 {
            // Get the xZB token contract address
            let xzb_token = self.xzb_token.read();

            // Create a dispatcher to interact with the ERC20 token contract
            let token_dispatcher = IERC20Dispatcher { contract_address: xzb_token };

            // Call the balance_of function to get the voter's token balance
            let balance = token_dispatcher.balance_of(voter);

            // Return the voter's token balance as their voting weight
            balance
        }
        // Helper function to check if a proposal is in the poll phase
        fn _is_in_poll_phase(self: @ContractState, proposal_id: u256) -> bool {
            let proposal = self.proposals.read(proposal_id);
            let current_time = get_block_timestamp();

            // Check if proposal is in poll phase state and within time limits
            proposal.state == 1 && current_time <= proposal.poll_end_time
        }

        // Helper function to validate a proposal exists
        fn _validate_proposal_exists(self: @ContractState, proposal_id: u256) -> Proposal {
            let proposal = self.proposals.read(proposal_id);
            assert(proposal.id == proposal_id, 'Proposal does not exist');
            proposal
        }

        // Helper function to update vote counts
        fn _update_vote_counts(
            ref self: ContractState, proposal_id: u256, support: bool, vote_weight: u256,
        ) {
            let mut proposal = self.proposals.read(proposal_id);

            if support {
                proposal.vote_for += vote_weight;
            } else {
                proposal.vote_against += vote_weight;
            }

            self.proposals.write(proposal_id, proposal);
        }
    }
}
