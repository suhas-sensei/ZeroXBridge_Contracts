#[starknet::interface]
pub trait IZeroXBridgeL2<TContractState> {
    fn burn_xzb_for_unlock(ref self: TContractState, amount: core::integer::u256);
}

#[starknet::contract]
pub mod ZeroXBridgeL2 {
    use starknet::{ContractAddress, get_caller_address};
    use l2::xZBERC20::{IBurnableDispatcher, IBurnableDispatcherTrait};
    use core::pedersen::PedersenTrait;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use core::hash::{HashStateTrait, HashStateExTrait};

    #[storage]
    struct Storage {
        xzb_token: ContractAddress,
    }

    #[derive(Drop, Hash)]
    pub struct BurnData {
        pub caller: felt252,
        pub amount_low: felt252,
        pub amount_high: felt252,
    }

    #[event]
    #[derive(Drop, Debug, starknet::Event)]
    pub enum Event {
        BurnEvent: BurnEvent,
    }

    #[derive(Drop, Debug, starknet::Event)]
    pub struct BurnEvent {
        pub user: ContractAddress,
        pub amount_low: felt252,
        pub amount_high: felt252,
        pub commitment_hash: felt252,
    }

    #[constructor]
    fn constructor(ref self: ContractState, token: ContractAddress) {
        self.xzb_token.write(token);
    }

    #[abi(embed_v0)]
    impl BurnXzbImpl of super::IZeroXBridgeL2<ContractState> {
        fn burn_xzb_for_unlock(ref self: ContractState, amount: core::integer::u256) {
            let caller = get_caller_address();
            let token_addr = self.xzb_token.read();

            IBurnableDispatcher { contract_address: token_addr }.burn(amount);

            let data_to_hash = BurnData {
                caller: caller.try_into().unwrap(),
                amount_low: amount.low.try_into().unwrap(),
                amount_high: amount.high.try_into().unwrap(),
            };
            let commitment_hash = PedersenTrait::new(0).update_with(data_to_hash).finalize();

            self
                .emit(
                    BurnEvent {
                        user: caller,
                        amount_low: amount.low.into(),
                        amount_high: amount.high.into(),
                        commitment_hash: commitment_hash,
                    },
                );
        }
    }
}
