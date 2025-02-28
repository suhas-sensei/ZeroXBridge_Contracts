use starknet::ContractAddress;
use starknet::get_block_timestamp;
use starknet::get_caller_address;
use starknet::storage::{
    StoragePointerReadAccess, StoragePointerWriteAccess,  Map,
};
use core::option::OptionTrait;
use core::array::ArrayTrait;

#[starknet::interface]
trait IExecutor<TContractState> {
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

#[starknet::contract]
mod Timelock {
    use super::*;
    use core::traits::Into;

    #[storage]
    struct Storage {
        actions:Map<felt252, Action>,
        action_count: u64,
        minimum_delay:u64,
        governance: ContractAddress,
    }
   #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ActionQueued: ActionQueued,
        ActionExecuted: ActionExecuted,
        ActionCanceled: ActionCanceled,
        MinimumDelayChanged: MinimumDelayChanged,
    }

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
    struct MinimumDelayChanged {
        old_delay: u64,
        new_delay: u64,
    }

    #[derive(Drop, Serde)]
    struct Action {
        executor: ContractAddress,
        executable_timestamp: u64,
        calldata: Array<u256>,
        status: ActionStatus,
    }

    #[derive(Drop, Serde, PartialEq)]
    enum ActionStatus {
        Pending: (),
        Executed: (),
        Canceled: (),
    }

    #[constructor]
    fn constructor(ref self: ContractState, initial_minimum_delay: u64, governance: ContractAddress) {
        self.action_count.write(0);
        self.minimum_delay.write(initial_minimum_delay);
        self.governance.write(governance);
    }

    #[abi(embed_v0)]
impl ITimelockImpl of ITimelock<ContractState> {
    fn queue_action(
        ref self: ContractState,
        executor: ContractAddress,
        delay: u64,
        calldata: Array<u256>
    ) -> felt252 {
        // Remove dereference operator *
        let min_delay = self.minimum_delay.read();
        assert!(delay >= min_delay, "Delay must be >= minimum delay");
        
        let current_time = get_block_timestamp();
        let executable_timestamp = current_time + delay;
        
        // Direct read without dereference
        let action_id = self.action_count.read();
        self.action_count.write(action_id + 1);
        
        let action = Action {
            executor,
            executable_timestamp,
            calldata,
            status: ActionStatus::Pending,
        };
        
        self.actions.write(action_id.into(), action);
        
        self.emit(Event::ActionQueued(ActionQueued {
            action_id: action_id.into(),
            executor,
            executable_timestamp,
            calldata,
        }));
        
        action_id.into()
    }

    fn execute_action(ref self: ContractState, action_id: felt252) {
        let action = self.actions.read(action_id).expect("Action does not exist");
        
        assert!(
            action.status == ActionStatus::Pending,
            "Action is not pending"
        );
        
        let current_time = get_block_timestamp();
        assert!(
            current_time >= action.executable_timestamp,
            "Delay not elapsed"
        );
        
        // Create new mutable action
        let updated_action = Action {
            status: ActionStatus::Executed,
            executor: action.executor,
            executable_timestamp: action.executable_timestamp,
            calldata: action.calldata,
        };
        
        // Write the updated action back to storage
        self.actions.write(action_id, updated_action);

        let executor_contract = IExecutorDispatcher { 
            contract_address: action.executor 
        };
        executor_contract.execute(action.calldata);
        
        self.emit(Event::ActionExecuted(ActionExecuted {
            action_id,
            executor: action.executor,
            executed_timestamp: current_time,
        }));
    }

    fn cancel_action(ref self: ContractState, action_id: felt252) {
        let caller = get_caller_address();
        // Remove dereference operator *
        assert!(caller == self.governance.read(), "Unauthorized");
        
        // Make action mutable
        let mut action = self.actions.read(action_id).expect("Action not found");
        assert!(action.status == ActionStatus::Pending, "Not cancellable");
        
        let updated_action = Action {
        status: ActionStatus::Canceled,
        executor: action.executor,
        executable_timestamp: action.executable_timestamp,
        calldata: action.calldata,
    };
    
    // Write the updated action back to storage
    self.actions.write(action_id, updated_action);
        
        self.emit(Event::ActionCanceled(ActionCanceled {
            action_id,
            canceled_by: caller,
        }));
    }

    fn set_minimum_delay(ref self: ContractState, new_delay: u64) {
        let caller = get_caller_address();
        // Remove dereference operator *
        assert!(caller == self.governance.read(), "Unauthorized");
        
        // Direct read without dereference
        let old_delay = self.minimum_delay.read();
        self.minimum_delay.write(new_delay);
        
        self.emit(Event::MinimumDelayChanged(MinimumDelayChanged {
            old_delay,
            new_delay,
        }));
    }

    fn get_pending_actions(self: @ContractState) -> Array<felt252> {
        let mut pending = ArrayTrait::new();
        // Direct read without dereference
        let count = self.action_count.read();
        let mut i: u64 = 0;
        
        while i < count {
            let action_id: felt252 = i.into();
            match self.actions.read(action_id) {
                Option::Some(action) => {
                    if action.status == ActionStatus::Pending {
                        pending.append(action_id);
                    }
                },
                Option::None => ()
            }
            i += 1;
        };
        pending
    }
}
}