use starknet::ContractAddress;
use starknet::get_block_timestamp;
use starknet::get_caller_address;
use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Map};
use core::option::OptionTrait;
use core::array::ArrayTrait;

// ==============================
// INTERFACES
// ==============================

#[starknet::interface]
trait IExecutor<TContractState> {
    // The target contract must implement an execute function to run the provided calldata.
    fn execute(self: @TContractState, calldata: Array<u256>);
}

#[starknet::interface]
trait ITimelock<TContractState> {
    fn queue_action(
         ref self: TContractState,
         executor: ContractAddress,
         delay: u64,
         calldata: Array<u256>
    ) -> felt252;

    fn execute_action(ref self: TContractState, action_id: felt252);

    fn cancel_action(ref self: TContractState, action_id: felt252);

    fn set_minimum_delay(ref self: TContractState, new_delay: u64);

    fn get_pending_actions(self: @TContractState) -> Array<felt252>;
}

// ==============================
// TIMELOCK CONTRACT
// ==============================

#[starknet::contract]
mod Timelock {
    use super::*;

    // STORAGE
    #[storage]
    struct Storage {
        actions: Map<felt252, Action>,
        action_count: felt252,
        minimum_delay: u64,
        governance: ContractAddress,
    }

    // EVENTS
    #[derive(Drop, Serde, starknet::Event)]
    struct ActionQueued {
        action_id: felt252,
        executor: ContractAddress,
        executable_timestamp: u64,
        calldata: Array<u256>,
    }

    #[derive(Drop, Serde, starknet::Event)]
    struct ActionExecuted {
        action_id: felt252,
        executor: ContractAddress,
        executed_timestamp: u64,
    }

    #[derive(Drop, Serde, starknet::Event)]
    struct ActionCanceled {
        action_id: felt252,
        canceled_by: ContractAddress,
    }

    #[derive(Drop, Serde, starknet::Event)]
    pub struct MinimumDelayChanged {
        old_delay: u64,
        new_delay: u64,
    }

    // DATA STRUCTURES
    #[derive(Drop, Serde)]
    pub struct Action {
        executor: ContractAddress,
        executable_timestamp: u64,
        calldata: Array<u256>,
        status: ActionStatus,
    }

    #[derive(Drop, Serde, PartialEq)]
    pub enum ActionStatus {
        Pending: (),
        Executed: (),
        Canceled: (),
    }

    // CONSTRUCTOR
    #[constructor]
    pub fn constructor(ref self: ContractState, initial_minimum_delay: u64, governance: ContractAddress) {
        self.action_count.write(0);
        self.minimum_delay.write(initial_minimum_delay);
        self.governance.write(governance);
    }

    // ==============================
    // IMPLEMENTATION OF ITimelock INTERFACE
    // ==============================
    #[external(v0)]
    #[abi(embed_v0)]
    impl TimelockImp of super::ITimelock<ContractState> {
        fn queue_action(
             ref self: ContractState, 
             executor: ContractAddress, 
             delay: u64, 
             calldata: Array<u256>
        ) -> felt252 {
             let min_delay = self.minimum_delay.read();
             assert!(delay >= min_delay, "Delay must be >= minimum delay");
             let current_time = get_block_timestamp();
             let executable_timestamp = current_time + delay;

             // Generate a unique action_id using the counter.
             let action_id = self.action_count.read();
             self.action_count.write(action_id + 1);
     
             // Store the action details.
             let action = Action {
                 executor: executor,
                 executable_timestamp: executable_timestamp,
                 calldata: calldata,
                 status: ActionStatus::Pending,
             };
             self.actions.entry(action_id).write(action);
     
             // Emit the ActionQueued event.
             self.emit(ActionQueued {
                 action_id: action_id,
                 executor: executor,
                 executable_timestamp: executable_timestamp,
                 calldata: calldata,
             });
     
             action_id
        }
     
        fn execute_action(ref self: ContractState, action_id: felt252) {
             let action = self.actions.entry(action_id).read();
             assert!(action.status == ActionStatus::Pending, "Action is not pending");
             let current_time = get_block_timestamp();
             assert!(current_time >= action.executable_timestamp, "Action delay has not elapsed");
     
             // Mark the action as executed.
             let mut updated_action = action;
             updated_action.status = ActionStatus::Executed;
             self.actions.entry(action_id).write(updated_action);
     
             // Call the executor contract's execute() function.
             let executor_contract = IExecutor { contract_address: action.executor };
             executor_contract.execute(action.calldata);
     
             // Emit the ActionExecuted event.
             self.emit(ActionExecuted {
                 action_id: action_id,
                 executor: action.executor,
                 executed_timestamp: current_time,
             });
        }
     
        fn cancel_action(ref self: ContractState, action_id: felt252) {
             let action = self.actions.entry(action_id).read();
             assert!(action.status == ActionStatus::Pending, "Action is not pending");

             let mut updated_action = action;
             updated_action.status = ActionStatus::Canceled;
             self.actions.entry(action_id).write(updated_action);

             let caller = get_caller_address();
             self.emit(ActionCanceled {
                 action_id: action_id,
                 canceled_by: caller,
             });
        }
     
        fn set_minimum_delay(ref self: ContractState, new_delay: u64) {
             let caller = get_caller_address();
             assert!(caller == self.governance.read(), "Only governance can update minimum delay");

             let old_delay = self.minimum_delay.read();
             self.minimum_delay.write(new_delay);
             self.emit(MinimumDelayChanged {
                 old_delay: old_delay,
                 new_delay: new_delay,
             });
        }
     
        fn get_pending_actions(self: @ContractState) -> Array<felt252> {
             let mut pending_actions = ArrayTrait::new();
             for (action_id, action) in self.actions.iter() {
                 if action.status == ActionStatus::Pending {
                     pending_actions.append(action_id);
                 }
             };
             pending_actions
        }
    }
}