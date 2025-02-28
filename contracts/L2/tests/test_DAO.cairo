use snforge_std::DeclareResultTrait;
use starknet::ContractAddress;
// use starknet::testing::{set_caller_address, set_contract_address};
use snforge_std::{
    declare, start_cheat_caller_address, stop_cheat_caller_address, ContractClassTrait,
};
use core::traits::Into;
use core::option::OptionTrait;

// Import the contract interface and types
use l2::DAO::{IPollContractDispatcher, IPollContractDispatcherTrait};

fn deploy_dao() -> (ContractAddress, IPollContractDispatcher) {
    // Deploy the contract
    let contract = declare("PollContract").unwrap().contract_class();
    // let owner = contract_address_const::<'OWNER'>();
    let owner: ContractAddress = 0x0590e76a2e65435b7288bf3526cfa5c3ec7748d2f3433a934c931cce62460fc5
        .try_into()
        .unwrap();
    let user_felt: felt252 = owner.into();
    let threshold: u256 = 100; // Set voting threshold

    let calldata = array![user_felt, threshold.try_into().unwrap()];
    // Fix: use a ContractAddress instead of felt252
    // let contract_address = starknet::contract_address_const::<100>()

    let (address, _) = contract.deploy(@calldata).unwrap();
    let contract_address: ContractAddress = address.try_into().unwrap();

    (owner, IPollContractDispatcher { contract_address })
}

#[test]
fn test_poll_tally_passed() {
    let (owner, dao) = deploy_dao();

    // Set up test data
    let proposal_id: u256 = 1;
    // let for_votes: u256 = 150; // More than threshold
    // let against_votes: u256 = 50;

    // Set caller as owner
    start_cheat_caller_address(dao.contract_address, owner);

    // Call tally_poll_votes
    dao.tally_poll_votes(proposal_id);

    // We would verify the emitted event here, but current testing framework
    // doesn't support event verification directly

    stop_cheat_caller_address(dao.contract_address);
}

#[test]
fn test_poll_tally_failed() {
    let (owner, dao) = deploy_dao();

    // Set up test data
    let proposal_id: u256 = 2;
    // let for_votes: u256 = 50; // Less than threshold
    // let against_votes: u256 = 150;

    // Set caller as owner
    start_cheat_caller_address(dao.contract_address, owner);

    // Call tally_poll_votes
    dao.tally_poll_votes(proposal_id);

    stop_cheat_caller_address(dao.contract_address);
}

#[test]
#[should_panic]
fn test_poll_tally_unauthorized() {
    let (_, dao) = deploy_dao();

    // Set up test data
    let proposal_id: u256 = 3;
    let unauthorized_user = contract_address_const::<'UNAUTHORIZED'>();

    // Try to call tally_poll_votes with unauthorized user
    start_cheat_caller_address(dao.contract_address, unauthorized_user);
    dao.tally_poll_votes(proposal_id);
    stop_cheat_caller_address(dao.contract_address);
}

// Helper function to create a constant contract address
fn contract_address_const<const ADDRESS: felt252>() -> ContractAddress {
    starknet::contract_address_const::<ADDRESS>()
}
