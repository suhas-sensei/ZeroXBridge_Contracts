use snforge_std::{
    declare, spy_events, ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, CheatSpan,
    cheat_caller_address, EventSpyTrait,
};

use l2::ZeroXBridgeL2::{IZeroXBridgeL2Dispatcher, IZeroXBridgeL2DispatcherTrait};
use l2::ZeroXBridgeL2::ZeroXBridgeL2::{Event, BurnEvent, BurnData};
use l2::xZBERC20::{IMintableDispatcher, IMintableDispatcherTrait};
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use starknet::{ContractAddress, contract_address_const};
use core::integer::u256;
use core::pedersen::PedersenTrait;
use core::hash::{HashStateTrait, HashStateExTrait};
use openzeppelin_utils::serde::SerializedAppend;

fn alice() -> ContractAddress {
    contract_address_const::<'alice'>()
}

fn owner() -> ContractAddress {
    contract_address_const::<'owner'>()
}

fn deploy_xzb() -> ContractAddress {
    let contract_class = declare("xZBERC20").unwrap().contract_class();
    let mut calldata = array![];
    calldata.append_serde(owner());
    let (contract_address, _) = contract_class.deploy(@calldata).unwrap();
    contract_address
}

fn deploy_bridge(xzb_addr: ContractAddress) -> ContractAddress {
    let contract_class = declare("ZeroXBridgeL2").unwrap().contract_class();
    let mut calldata = array![];
    calldata.append_serde(xzb_addr);
    let (contract_address, _) = contract_class.deploy(@calldata).unwrap();
    contract_address
}

#[test]
fn test_burn_xzb_for_unlock_happy_path() {
    let token_addr = deploy_xzb();
    let bridge_addr = deploy_bridge(token_addr);
    let alice_addr = alice();
    let owner_addr = owner();

    // Mint tokens to Alice.
    cheat_caller_address(token_addr, owner_addr, CheatSpan::TargetCalls(1));
    IMintableDispatcher { contract_address: token_addr }.mint(alice_addr, 1000);

    // Burn tokens through bridge with alice as caller.
    let mut spy = spy_events();
    cheat_caller_address(bridge_addr, alice_addr, CheatSpan::TargetCalls(1));
    cheat_caller_address(token_addr, alice_addr, CheatSpan::TargetCalls(1));
    let amount: u256 = u256 { low: 500, high: 0 };
    IZeroXBridgeL2Dispatcher { contract_address: bridge_addr }.burn_xzb_for_unlock(amount);

    // Compute expected commitment hash.
    let data_to_hash = BurnData {
        caller: alice_addr.try_into().unwrap(), amount_low: 500, amount_high: 0,
    };
    let expected_hash = PedersenTrait::new(0).update_with(data_to_hash).finalize();

    // Build expected event value.
    let expected_event = (
        bridge_addr,
        Event::BurnEvent(
            BurnEvent {
                user: alice_addr.try_into().unwrap(),
                amount_low: 500,
                amount_high: 0,
                commitment_hash: expected_hash,
            },
        ),
    );

    // Assert that the expected event was emitted.
    spy.assert_emitted(@array![expected_event]);
}

#[test]
fn test_burn_xzb_updates_balance() {
    // Verify that burning xZB tokens updates the user's balance correctly.
    let token_addr = deploy_xzb();
    let bridge_addr = deploy_bridge(token_addr);
    let alice_addr = alice();
    let owner_addr = owner();

    // Mint tokens to Alice.
    cheat_caller_address(token_addr, owner_addr, CheatSpan::TargetCalls(1));
    IMintableDispatcher { contract_address: token_addr }.mint(alice_addr, 1000);

    // Check initial balance.
    let erc20 = IERC20Dispatcher { contract_address: token_addr };
    let initial_balance = erc20.balance_of(alice_addr);

    // Burn tokens through bridge.
    cheat_caller_address(bridge_addr, alice_addr, CheatSpan::TargetCalls(1));
    cheat_caller_address(token_addr, alice_addr, CheatSpan::TargetCalls(1));
    let amount: u256 = u256 { low: 500, high: 0 };
    IZeroXBridgeL2Dispatcher { contract_address: bridge_addr }.burn_xzb_for_unlock(amount);

    // Check balance after burn.
    let final_balance = erc20.balance_of(alice_addr);
    assert(initial_balance - final_balance == 500, 'Token balance not reduced');
}

#[test]
fn test_commitment_hash_consistency() {
    // Verify that for a fixed caller and burn amount, the commitment hash is consistent.
    let token_addr = deploy_xzb();
    let bridge_addr = deploy_bridge(token_addr);
    let alice_addr = alice();
    let owner_addr = owner();

    // Mint tokens to Alice.
    cheat_caller_address(token_addr, owner_addr, CheatSpan::TargetCalls(1));
    IMintableDispatcher { contract_address: token_addr }.mint(alice_addr, 1000);

    // Burn tokens via bridge.
    let mut spy = spy_events();
    // Burn tokens through bridge.
    cheat_caller_address(bridge_addr, alice_addr, CheatSpan::TargetCalls(1));
    cheat_caller_address(token_addr, alice_addr, CheatSpan::TargetCalls(1));
    let amount: u256 = u256 { low: 500, high: 0 };
    IZeroXBridgeL2Dispatcher { contract_address: bridge_addr }.burn_xzb_for_unlock(amount);

    // Compute expected hash using BurnData.
    let data_to_hash = BurnData {
        caller: alice_addr.try_into().unwrap(), amount_low: 500, amount_high: 0,
    };
    let expected = PedersenTrait::new(0).update_with(data_to_hash).finalize();
    println!("Expected commitment hash: {:?}", expected);
    // Retrieve the emitted event and compare commitment hash.
    let events = spy.get_events();
    let (_emitter, evt) = events.events.at(1);
    assert(evt.data.at(3) == @expected, 'hash does not match');
}

#[test]
#[should_panic(expected: 'ERC20: insufficient balance')]
fn test_burn_xzb_insufficient_balance() {
    // Test that burning more tokens than available triggers an error.
    let token_addr = deploy_xzb();
    let bridge_addr = deploy_bridge(token_addr);
    let alice_addr = alice();
    let owner_addr = owner();

    // Mint fewer tokens than we attempt to burn.
    cheat_caller_address(token_addr, owner_addr, CheatSpan::TargetCalls(1));
    IMintableDispatcher { contract_address: token_addr }.mint(alice_addr, 300);

    // Attempt to burn 500 tokens when balance is only 300.
    cheat_caller_address(bridge_addr, alice_addr, CheatSpan::TargetCalls(1));
    cheat_caller_address(token_addr, alice_addr, CheatSpan::TargetCalls(1));
    let amount: u256 = u256 { low: 500, high: 0 };
    IZeroXBridgeL2Dispatcher { contract_address: bridge_addr }.burn_xzb_for_unlock(amount);
}
