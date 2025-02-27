use openzeppelin_utils::serde::SerializedAppend;
use l2::Dynamicrate::{IDynamicRateDispatcher, IDynamicRateDispatcherTrait};
use snforge_std::{CheatSpan, ContractClassTrait, DeclareResultTrait, cheat_caller_address, declare};
use starknet::{ContractAddress, contract_address_const};

// Constants for test configuration
const MIN_RATE: u256 = 100000; // 0.1 (with PRECISION = 1000000)
const MAX_RATE: u256 = 5000000; // 5.0 (with PRECISION = 1000000)
const PRECISION: u256 = 1000000; // 6 decimals for rate precision

// Helper functions to get test addresses
fn owner() -> ContractAddress {
    contract_address_const::<'owner'>()
}

fn non_owner() -> ContractAddress {
    contract_address_const::<'non_owner'>()
}

fn oracle_address() -> ContractAddress {
    contract_address_const::<'oracle'>()
}

fn new_oracle_address() -> ContractAddress {
    contract_address_const::<'new_oracle'>()
}

// Helper functions
fn deploy_dynamic_rate() -> ContractAddress {
    let owner = owner();
    let oracle = oracle_address();
    let contract_class = declare("DynamicRate").unwrap().contract_class();
    let mut calldata = array![];
    calldata.append_serde(owner);
    calldata.append_serde(oracle);
    calldata.append_serde(MIN_RATE);
    calldata.append_serde(MAX_RATE);
    let (contract_address, _) = contract_class.deploy(@calldata).unwrap();
    contract_address
}

#[test]
#[should_panic(expected: 'Only owner')]
fn test_only_owner_can_set_min_rate() {
    let contract_address = deploy_dynamic_rate();
    let dynamic_rate = IDynamicRateDispatcher { contract_address };

    // Non-owner tries to update the min rate
    cheat_caller_address(contract_address, non_owner(), CheatSpan::TargetCalls(1));
    dynamic_rate.set_min_rate(200000);
}

#[test]
fn test_set_max_rate() {
    let contract_address = deploy_dynamic_rate();
    let dynamic_rate = IDynamicRateDispatcher { contract_address };

    // Owner can update the max rate
    let new_max_rate: u256 = 6000000; // 6.0
    cheat_caller_address(contract_address, owner(), CheatSpan::TargetCalls(1));
    dynamic_rate.set_max_rate(new_max_rate);
    // Test with a scenario where max rate would be applied
}

#[test]
#[should_panic(expected: 'Only owner')]
fn test_only_owner_can_set_max_rate() {
    let contract_address = deploy_dynamic_rate();
    let dynamic_rate = IDynamicRateDispatcher { contract_address };

    // Non-owner tries to update the max rate
    cheat_caller_address(contract_address, non_owner(), CheatSpan::TargetCalls(1));
    dynamic_rate.set_max_rate(6000000);
}

#[test]
#[should_panic(expected: 'Min rate must be < max rate')]
fn test_min_rate_less_than_max_rate() {
    let contract_address = deploy_dynamic_rate();
    let dynamic_rate = IDynamicRateDispatcher { contract_address };

    // Try to set min rate equal to max rate
    cheat_caller_address(contract_address, owner(), CheatSpan::TargetCalls(1));
    dynamic_rate.set_min_rate(MAX_RATE);
}

#[test]
#[should_panic(expected: 'Max rate must be > min rate')]
fn test_max_rate_greater_than_min_rate() {
    let contract_address = deploy_dynamic_rate();
    let dynamic_rate = IDynamicRateDispatcher { contract_address };

    // Try to set max rate equal to min rate
    cheat_caller_address(contract_address, owner(), CheatSpan::TargetCalls(1));
    dynamic_rate.set_max_rate(MIN_RATE);
}
