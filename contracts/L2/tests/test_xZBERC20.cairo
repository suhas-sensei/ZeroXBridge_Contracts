use l2::xZBERC20::{
    IBurnableDispatcher, IBurnableDispatcherTrait, IMintableDispatcher, IMintableDispatcherTrait,
    MINTER_ROLE,
};

use openzeppelin_access::accesscontrol::interface::{
    IAccessControlDispatcher, IAccessControlDispatcherTrait,
};
use openzeppelin_token::erc20::erc20::ERC20Component;
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use openzeppelin_utils::serde::SerializedAppend;
use snforge_std::{
    CheatSpan, ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait,
    cheat_caller_address, declare, spy_events,
};
use starknet::{ContractAddress, contract_address_const};


fn owner() -> ContractAddress {
    contract_address_const::<'owner'>()
}

fn alice() -> ContractAddress {
    contract_address_const::<'alice'>()
}

fn bob() -> ContractAddress {
    contract_address_const::<'bob'>()
}

fn carl() -> ContractAddress {
    contract_address_const::<'carl'>()
}

fn minter() -> ContractAddress {
    contract_address_const::<'minter'>()
}

fn mint(contract_address: ContractAddress, recipient: ContractAddress, amount: u256) {
    cheat_caller_address(contract_address, owner(), CheatSpan::TargetCalls(1));
    IMintableDispatcher { contract_address }.mint(recipient, amount);
}

fn grant_mint_role(contract_address: ContractAddress, user: ContractAddress) {
    cheat_caller_address(contract_address, owner(), CheatSpan::TargetCalls(1));
    IAccessControlDispatcher { contract_address }.grant_role(MINTER_ROLE, user);
}

fn deploy_erc20() -> ContractAddress {
    let owner = owner();
    let contract_class = declare("xZBERC20").unwrap().contract_class();
    let mut calldata = array![];
    calldata.append_serde(owner);
    let (contract_address, _) = contract_class.deploy(@calldata).unwrap();

    grant_mint_role(contract_address, minter());
    contract_address
}

#[test]
#[should_panic(expected: 'Caller is missing role')]
fn test_an_user_cant_grant_another_user() {
    let alice = alice();
    let bob = bob();
    let contract_address = deploy_erc20();
    cheat_caller_address(contract_address, alice, CheatSpan::TargetCalls(1));
    IAccessControlDispatcher { contract_address }.grant_role(MINTER_ROLE, bob);
}

#[test]
#[should_panic(expected: 'Caller is missing role')]
fn test_a_granted_user_cant_grant_another_user() {
    let minter = minter();
    let alice = alice();
    let contract_address = deploy_erc20();
    cheat_caller_address(contract_address, minter, CheatSpan::TargetCalls(1));
    IAccessControlDispatcher { contract_address }.grant_role(MINTER_ROLE, alice);
}

#[test]
#[should_panic(expected: 'Caller is missing role')]
fn test_a_granted_user_cant_revoke_another_granted_user() {
    let owner = owner();
    let minter = minter();
    let alice = alice();
    let contract_address = deploy_erc20();

    cheat_caller_address(contract_address, owner, CheatSpan::TargetCalls(1));
    IAccessControlDispatcher { contract_address }.grant_role(MINTER_ROLE, alice);

    cheat_caller_address(contract_address, minter, CheatSpan::TargetCalls(1));
    IAccessControlDispatcher { contract_address }.revoke_role(MINTER_ROLE, alice);
}

#[test]
fn test_a_granted_user_can_renounce_role() {
    let minter = minter();
    let contract_address = deploy_erc20();
    cheat_caller_address(contract_address, minter, CheatSpan::TargetCalls(1));
    IAccessControlDispatcher { contract_address }.renounce_role(MINTER_ROLE, minter);
    let can_mint = IAccessControlDispatcher { contract_address }.has_role(MINTER_ROLE, minter);
    assert(!can_mint, 'User should not have the role');
}

#[test]
fn test_owner_can_mint() {
    let owner = owner();
    let minter = minter();
    let alice = alice();
    let amount = 1000;
    let contract_address = deploy_erc20();
    let erc20 = IERC20Dispatcher { contract_address };
    let previous_balance = erc20.balance_of(owner);
    cheat_caller_address(contract_address, minter, CheatSpan::TargetCalls(1));
    IMintableDispatcher { contract_address }.mint(owner, amount);
    let balance = erc20.balance_of(owner);
    assert(balance - previous_balance == amount, 'Wrong amount after mint');

    let previous_balance = erc20.balance_of(alice);
    cheat_caller_address(contract_address, minter, CheatSpan::TargetCalls(1));
    IMintableDispatcher { contract_address }.mint(alice, amount);
    let balance = erc20.balance_of(alice);
    assert(balance - previous_balance == amount, 'Wrong amount after mint');
}

#[test]
#[should_panic(expected: 'Caller is missing role')]
fn test_only_granted_user_can_mint() {
    let alice = alice();
    let contract_address = deploy_erc20();

    cheat_caller_address(contract_address, alice, CheatSpan::TargetCalls(1));
    IMintableDispatcher { contract_address }.mint(alice, 1000);
}

#[test]
fn test_supply_is_updated_after_mint() {
    let alice = alice();
    let amount = 1000;
    let contract_address = deploy_erc20();
    let erc20 = IERC20Dispatcher { contract_address };
    let previous_supply = erc20.total_supply();
    mint(contract_address, alice, amount);
    let supply = erc20.total_supply();
    assert(supply - previous_supply == amount, 'Wrong supply after mint');
}

#[test]
fn test_a_granted_user_can_mint() {
    let owner = owner();
    let alice = alice();
    let bob = bob();
    let amount = 1000;
    let contract_address = deploy_erc20();
    let erc20 = IERC20Dispatcher { contract_address };

    cheat_caller_address(contract_address, owner, CheatSpan::TargetCalls(1));
    IAccessControlDispatcher { contract_address }.grant_role(MINTER_ROLE, bob);

    let previous_balance = erc20.balance_of(alice);
    cheat_caller_address(contract_address, bob, CheatSpan::TargetCalls(1));
    IMintableDispatcher { contract_address }.mint(alice, amount);
    let balance = erc20.balance_of(alice);
    assert(balance - previous_balance == amount, 'Wrong amount after mint');
}

#[test]
#[should_panic(expected: 'Caller is missing role')]
fn test_a_revoked_user_can_not_mint() {
    let owner = owner();
    let minter = minter();
    let alice = alice();
    let amount = 1000;
    let contract_address = deploy_erc20();

    cheat_caller_address(contract_address, owner, CheatSpan::TargetCalls(1));
    IAccessControlDispatcher { contract_address }.revoke_role(MINTER_ROLE, minter);

    cheat_caller_address(contract_address, minter, CheatSpan::TargetCalls(1));
    IMintableDispatcher { contract_address }.mint(alice, amount);
}

#[test]
fn test_user_can_burn() {
    let alice = alice();
    let amount = 1000;
    let contract_address = deploy_erc20();
    let erc20 = IERC20Dispatcher { contract_address };
    mint(contract_address, alice, amount);
    let previous_balance = erc20.balance_of(alice);
    cheat_caller_address(contract_address, alice, CheatSpan::TargetCalls(1));
    IBurnableDispatcher { contract_address }.burn(amount);
    let balance = erc20.balance_of(alice);
    assert(previous_balance - balance == amount, 'Wrong amount after burn');
}


#[test]
fn test_supply_is_updated_after_burn() {
    let alice = alice();
    let amount = 1000;
    let contract_address = deploy_erc20();
    let erc20 = IERC20Dispatcher { contract_address };
    mint(contract_address, alice, amount);

    let previous_supply = erc20.total_supply();
    cheat_caller_address(contract_address, alice, CheatSpan::TargetCalls(1));
    IBurnableDispatcher { contract_address }.burn(amount);
    let supply = erc20.total_supply();
    assert(previous_supply - supply == amount, 'Wrong supply after burn');
}

#[test]
#[should_panic(expected: 'ERC20: insufficient balance')]
fn test_user_cant_burn_more_than_balance() {
    let alice = alice();
    let contract_address = deploy_erc20();
    mint(contract_address, alice, 1000);
    let erc20 = IERC20Dispatcher { contract_address };
    let balance = erc20.balance_of(alice);
    cheat_caller_address(contract_address, alice, CheatSpan::TargetCalls(1));
    IBurnableDispatcher { contract_address }.burn(balance + 1);
}

#[test]
fn test_transfer() {
    let alice = alice();
    let bob = bob();
    let amount = 1000;
    let contract_address = deploy_erc20();
    mint(contract_address, alice, amount);
    let erc20 = IERC20Dispatcher { contract_address };
    let previous_balance_alice = erc20.balance_of(alice);
    let previous_balance_bob = erc20.balance_of(bob);
    cheat_caller_address(contract_address, alice, CheatSpan::TargetCalls(1));
    erc20.transfer(bob, amount);
    let balance_alice = erc20.balance_of(alice);
    let balance_bob = erc20.balance_of(bob);
    assert(previous_balance_alice - balance_alice == amount, 'Wrong amount after transfer');
    assert(balance_bob - previous_balance_bob == amount, 'Wrong amount after transfer');
}


#[test]
fn test_transfer_emit_event() {
    let alice = alice();
    let bob = bob();
    let amount = 1000;
    let contract_address = deploy_erc20();
    mint(contract_address, bob, amount);

    let erc20 = IERC20Dispatcher { contract_address };
    let mut spy = spy_events();
    cheat_caller_address(contract_address, bob, CheatSpan::TargetCalls(1));
    erc20.transfer(alice, amount);
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    ERC20Component::Event::Transfer(
                        ERC20Component::Transfer { from: bob, to: alice, value: amount },
                    ),
                ),
            ],
        );
}

#[test]
#[should_panic(expected: 'ERC20: insufficient balance')]
fn test_transfer_not_enough_balance() {
    let alice = alice();
    let bob = bob();
    let amount = 1000;
    let contract_address = deploy_erc20();
    mint(contract_address, bob, amount);

    let erc20 = IERC20Dispatcher { contract_address };
    let balance = erc20.balance_of(bob);
    cheat_caller_address(contract_address, bob, CheatSpan::TargetCalls(1));
    erc20.transfer(alice, balance + 1);
}

#[test]
fn test_transfer_from() {
    let alice = alice();
    let bob = bob();
    let carl = carl();
    let amount = 1000;
    let contract_address = deploy_erc20();
    mint(contract_address, alice, 2 * amount);

    let erc20 = IERC20Dispatcher { contract_address };
    let previous_balance_alice = erc20.balance_of(alice);
    let previous_balance_bob = erc20.balance_of(bob);

    cheat_caller_address(contract_address, alice, CheatSpan::TargetCalls(1));
    erc20.approve(carl, amount);

    cheat_caller_address(contract_address, carl, CheatSpan::TargetCalls(1));
    erc20.transfer_from(alice, bob, amount);

    let balance_alice = erc20.balance_of(alice);
    let balance_bob = erc20.balance_of(bob);
    assert(previous_balance_alice - balance_alice == amount, 'Wrong amount after transfer');
    assert(balance_bob - previous_balance_bob == amount, 'Wrong amount after transfer');
}

#[test]
fn test_transfer_from_emit_event() {
    let alice = alice();
    let bob = bob();
    let carl = carl();
    let amount = 1000;
    let contract_address = deploy_erc20();
    mint(contract_address, alice, 2 * amount);

    let erc20 = IERC20Dispatcher { contract_address };
    cheat_caller_address(contract_address, alice, CheatSpan::TargetCalls(1));
    erc20.approve(carl, amount);

    let mut spy = spy_events();
    cheat_caller_address(contract_address, carl, CheatSpan::TargetCalls(1));
    erc20.transfer_from(alice, bob, amount);
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    ERC20Component::Event::Transfer(
                        ERC20Component::Transfer { from: alice, to: bob, value: amount },
                    ),
                ),
            ],
        );
}

#[test]
#[should_panic(expected: 'ERC20: insufficient allowance')]
fn test_transfer_from_not_enough_allowance() {
    let alice = alice();
    let bob = bob();
    let carl = carl();
    let amount = 1000;
    let allowed_amount = amount - 1;
    let contract_address = deploy_erc20();
    mint(contract_address, alice, amount);

    let erc20 = IERC20Dispatcher { contract_address };
    cheat_caller_address(contract_address, alice, CheatSpan::TargetCalls(1));
    erc20.approve(carl, allowed_amount);

    cheat_caller_address(contract_address, carl, CheatSpan::TargetCalls(1));
    erc20.transfer_from(alice, bob, amount);
}

#[test]
#[should_panic(expected: 'ERC20: insufficient balance')]
fn test_transfer_from_not_enough_balance() {
    let alice = alice();
    let bob = bob();
    let carl = carl();
    let amount = 1000;
    let transfer_amount = amount + 1;
    let contract_address = deploy_erc20();
    mint(contract_address, alice, amount);

    let erc20 = IERC20Dispatcher { contract_address };
    cheat_caller_address(contract_address, alice, CheatSpan::TargetCalls(1));
    erc20.approve(carl, transfer_amount);

    cheat_caller_address(contract_address, carl, CheatSpan::TargetCalls(1));
    erc20.transfer_from(alice, bob, transfer_amount);
}
#[test]
fn test_allowance() {
    let alice = alice();
    let carl = carl();
    let amount = 1000;
    let contract_address = deploy_erc20();
    let erc20 = IERC20Dispatcher { contract_address };
    let allowance = erc20.allowance(alice, carl);
    assert(allowance == 0, 'Wrong allowance');
    cheat_caller_address(contract_address, alice, CheatSpan::TargetCalls(1));
    erc20.approve(carl, amount);
    let allowance = erc20.allowance(alice, carl);
    assert(allowance == amount, 'Wrong allowance');
}

#[test]
fn test_allowance_is_updated_after_transfer_from() {
    let alice = alice();
    let bob = bob();
    let carl = carl();
    let amount = 1000;
    let contract_address = deploy_erc20();
    mint(contract_address, alice, 2 * amount);

    let erc20 = IERC20Dispatcher { contract_address };

    cheat_caller_address(contract_address, alice, CheatSpan::TargetCalls(1));
    erc20.approve(carl, amount);
    let previous_allowance = erc20.allowance(alice, carl);

    cheat_caller_address(contract_address, carl, CheatSpan::TargetCalls(1));
    erc20.transfer_from(alice, bob, amount);

    let allowance = erc20.allowance(alice, carl);

    assert(previous_allowance - allowance == amount, 'Wrong allowance after transfer');
}

#[test]
fn test_approve_emit_event() {
    let alice = alice();
    let carl = carl();
    let amount = 1000;
    let contract_address = deploy_erc20();
    let erc20 = IERC20Dispatcher { contract_address };
    let mut spy = spy_events();
    cheat_caller_address(contract_address, alice, CheatSpan::TargetCalls(1));
    erc20.approve(carl, amount);
    spy
        .assert_emitted(
            @array![
                (
                    contract_address,
                    ERC20Component::Event::Approval(
                        ERC20Component::Approval { owner: alice, spender: carl, value: amount },
                    ),
                ),
            ],
        );
}
