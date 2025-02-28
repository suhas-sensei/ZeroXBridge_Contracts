// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts for Cairo ^0.20.0

// Define the IPoll trait
#[starknet::interface]
pub trait IPollContract<TContractState> {
    fn tally_poll_votes(ref self: TContractState, proposal_id: u256);

    // New function for testing purposes
    fn set_proposal_votes(
        ref self: TContractState, proposal_id: u256, for_votes: u256, against_votes: u256,
    );
}

#[starknet::contract]
pub mod PollContract {
    use OwnableComponent::InternalTrait;
    use starknet::{ContractAddress};
    use openzeppelin_access::ownable::OwnableComponent;
    use openzeppelin_token::erc20::{ERC20Component, ERC20HooksEmptyImpl};
    use openzeppelin_upgrades::UpgradeableComponent;
    use starknet::storage::{
        StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess, Map,
    };

    // Import the IPoll trait
    use super::IPollContract;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);

    #[storage]
    pub struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
        proposal_votes: Map<u256, (u256, u256)>,
        proposal_status: Map<u256, ProposalStatus>,
        vote_threshold: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event,
        PollResultUpdated: PollResultUpdatedEvent,
    }

    #[derive(Drop, Serde, starknet::Store, Copy, Clone, PartialEq)]
    #[allow(starknet::store_no_default_variant)]
    pub enum ProposalStatus {
        PollActive,
        PollPassed,
        PollFailed,
    }

    #[derive(Drop, Serde, starknet::Event)]
    pub struct PollResultUpdatedEvent {
        proposal_id: u256,
        total_for: u256,
        total_against: u256,
        new_status: ProposalStatus,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress, threshold: felt252) {
        self.ownable.initializer(owner);
        self.vote_threshold.write(threshold.into());
    }

    // Implement the IPoll trait
    #[abi(embed_v0)]
    impl PollImpl of IPollContract<ContractState> {
        fn tally_poll_votes(ref self: ContractState, proposal_id: u256) {
            // Ensure the caller is the owner
            self.ownable.assert_only_owner();

            // Read votes from the map
            let (for_votes, against_votes) = self.proposal_votes.read(proposal_id);

            // Determine the new status based on the threshold
            let new_status = if for_votes >= self.vote_threshold.read() {
                ProposalStatus::PollPassed
            } else {
                ProposalStatus::PollFailed
            };

            // Update the proposal status in the map
            self.proposal_status.write(proposal_id, new_status);

            // Emit the event
            self
                .emit(
                    PollResultUpdatedEvent {
                        proposal_id, total_for: for_votes, total_against: against_votes, new_status,
                    },
                );
        }

        // New function for testing purposes to set proposal votes
        fn set_proposal_votes(
            ref self: ContractState, proposal_id: u256, for_votes: u256, against_votes: u256,
        ) {
            // Ensure only the owner can set votes (for testing purposes)
            self.ownable.assert_only_owner();

            // Set the votes for the proposal
            self.proposal_votes.write(proposal_id, (for_votes, against_votes));

            // Initialize proposal as active
            self.proposal_status.write(proposal_id, ProposalStatus::PollActive);
        }
    }
}
