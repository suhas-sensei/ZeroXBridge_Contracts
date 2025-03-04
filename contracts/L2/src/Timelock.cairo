use starknet::ContractAddress;
use starknet::get_block_timestamp;
use starknet::get_caller_address;
use starknet::storage::{
    StoragePointerReadAccess, StoragePointerWriteAccess, StoragePathEntry, Vec, Map,
};
use core::array::{ArrayTrait};
use core::poseidon::PoseidonTrait;
use core::poseidon::poseidon_hash_span;
use core::hash::{HashStateTrait};
use core::integer::u256;

#[starknet::interface]
trait IExecutor<TContractState> {
    fn execute(ref self: TContractState, calldata: Array<u256>);
}

#[starknet::interface]
trait ITimelock<TContractState> {
    fn queue_action(
        ref self: TContractState, executor: ContractAddress, delay: u64, calldata: Array<u256>,
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
    use starknet::storage::{MutableVecTrait};

    #[storage]
    struct Storage {
        #[starknet::storage_node]
        actions: Map<felt252, ActionNode>,
        action_count: u64,
        minimum_delay: u64,
        governance: ContractAddress,
    }

    #[starknet::storage_node]
    struct ActionNode {
        executor: ContractAddress,
        executable_timestamp: u64,
        status: ActionStatus,
        // calldata is stored as a storage Vec<u256>.
        calldata: Vec<u256>,
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

    #[derive(Drop, Serde, Copy, PartialEq, starknet::Store)]
    #[allow(starknet::store_no_default_variant)]
    enum ActionStatus {
        Pending: (),
        Executed: (),
        Canceled: (),
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, initial_minimum_delay: u64, governance: ContractAddress,
    ) {
        self.action_count.write(0);
        self.minimum_delay.write(initial_minimum_delay);
        self.governance.write(governance);
    }

    #[abi(embed_v0)]
    impl ITimelockImpl of ITimelock<ContractState> {
        fn queue_action(
            ref self: ContractState, executor: ContractAddress, delay: u64, calldata: Array<u256>,
        ) -> felt252 {
            let caller = get_caller_address();
            assert!(caller == self.governance.read(), "Unauthorized");

            let min_delay = self.minimum_delay.read();
            assert!(delay >= min_delay, "Delay must be >= minimum delay");

            // Use calldata.span() for generating the action ID.
            let action_id = self.generate_action_id(executor, calldata.span(), delay);
            let current_time = get_block_timestamp();
            let executable_timestamp = current_time + delay;

            // Store action components.
            let mut action_entry = self.actions.entry(action_id);
            action_entry.executor.write(executor);
            action_entry.executable_timestamp.write(executable_timestamp);
            action_entry.status.write(ActionStatus::Pending);

            // Iterate over the calldata memory array and append each element to the storage Vec.
            let calldata_length = calldata.len();
            let mut i = 0;
            while i < calldata_length {
                // If indexing returns a pointer (@u256), use .read() to obtain the value.
                let element: u256 = *calldata.at(i);
                action_entry.calldata.append().write(element);
                i = i + 1;
            };

            self.action_count.write(self.action_count.read() + 1);

            self
                .emit(
                    Event::ActionQueued(
                        ActionQueued { action_id, executor, executable_timestamp, calldata },
                    ),
                );

            action_id
        }

        fn execute_action(ref self: ContractState, action_id: felt252) {
            let caller = get_caller_address();
            assert!(caller == self.governance.read(), "Unauthorized");

            let action_entry = self.actions.entry(action_id);
            let status = action_entry.status.read();
            assert!(status == ActionStatus::Pending, "Action not pending");

            let timestamp = action_entry.executable_timestamp.read();
            let current_time = get_block_timestamp();
            assert!(current_time >= timestamp, "Delay not elapsed");

            // Update status.
            action_entry.status.write(ActionStatus::Executed);

            // Retrieve and execute calldata.
            let executor = action_entry.executor.read();

            // Build a memory array from the stored calldata.
            let calldata_length = action_entry.calldata.len();
            let mut calldata_array = array![];

            let mut j = 0;
            while j < calldata_length {
                let element = action_entry.calldata.at(j).read();
                calldata_array.append(element);
                j = j + 1;
            };

            let executor_contract = IExecutorDispatcher { contract_address: executor };
            executor_contract.execute(calldata_array);

            self
                .emit(
                    Event::ActionExecuted(
                        ActionExecuted { action_id, executor, executed_timestamp: current_time },
                    ),
                );
        }

        fn cancel_action(ref self: ContractState, action_id: felt252) {
            let caller = get_caller_address();
            assert!(caller == self.governance.read(), "Unauthorized");

            let action_entry = self.actions.entry(action_id);
            let status = action_entry.status.read();
            assert!(status == ActionStatus::Pending, "Not cancellable");

            action_entry.status.write(ActionStatus::Canceled);

            self.emit(Event::ActionCanceled(ActionCanceled { action_id, canceled_by: caller }));
        }

        fn set_minimum_delay(ref self: ContractState, new_delay: u64) {
            let caller = get_caller_address();
            assert!(caller == self.governance.read(), "Unauthorized");

            let old_delay = self.minimum_delay.read();
            self.minimum_delay.write(new_delay);

            self.emit(Event::MinimumDelayChanged(MinimumDelayChanged { old_delay, new_delay }));
        }

        fn get_pending_actions(self: @ContractState) -> Array<felt252> {
            let mut pending = ArrayTrait::new();
            let count = self.action_count.read();

            for i in 0..count {
                let action_id: felt252 = i.into();
                let action_entry = self.actions.entry(action_id);
                if action_entry.status.read() == ActionStatus::Pending {
                    pending.append(action_id);
                }
            };
            pending
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn generate_action_id(
            self: @ContractState, executor: ContractAddress, calldata: Span<u256>, delay: u64,
        ) -> felt252 {
            // Convert calldata elements into a memory array of felt252.
            let mut calldata_felt = array![]; // Memory array of felt252.
            let calldata_length = calldata.len();
            let mut i = 0;

            while i < calldata_length {
                // Use .read() to access the value at index `i`.
                let element: u256 = *calldata.at(i);
                let element_felt: felt252 = self
                    .u256_to_felt252(element); // Convert u256 to felt252.
                calldata_felt.append(element_felt);
                i = i + 1;
            };

            // Generate the action ID using Poseidon hash.
            PoseidonTrait::new()
                .update(executor.into()) // Convert ContractAddress to felt252.
                .update(delay.into()) // Convert u64 to felt252.
                .update(poseidon_hash_span(calldata_felt.span())) // Hash the calldata array.
                .finalize()
        }
        fn u256_to_felt252(self: @ContractState, value: u256) -> felt252 {
            // Access the low and high parts of u256 directly (as fields, not methods).
            let low = value.low; // Lower 128 bits (u128).
            let high = value.high; // Upper 128 bits (u128).

            // Truncate the high part to 124 bits (since felt252 can hold 252 bits: 128 + 124).
            let truncated_high = high
                & 0x0FFFFFFFFFFFFFFFF; // Mask to retain only the lower 124 bits.

            // Use Poseidon hashing to combine the truncated high part and low part into a single
            // felt252.
            PoseidonTrait::new()
                .update(truncated_high.into()) // Convert truncated_high to felt252.
                .update(low.into()) // Convert low to felt252.
                .finalize() // Finalize the hash to produce a single felt252.
        }
    }
}
