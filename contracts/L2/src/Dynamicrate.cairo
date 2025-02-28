use starknet::ContractAddress;

#[starknet::interface]
pub trait IDynamicRate<TContractState> {
    fn get_dynamic_rate(self: @TContractState, tvl: u256) -> u256;
    fn get_current_xzb_supply(self: @TContractState) -> u256;
    fn set_min_rate(ref self: TContractState, rate: u256);
    fn set_max_rate(ref self: TContractState, rate: u256);
    fn set_oracle(ref self: TContractState, oracle: ContractAddress);
    fn set_xzb_token(ref self: TContractState, xzb_token: ContractAddress);
}

#[starknet::interface]
trait IL1Oracle<TContractState> {
    fn get_total_tvl(self: @TContractState) -> u256;
}

#[starknet::interface]
trait IERC20<TContractState> {
    fn total_supply(self: @TContractState) -> u256;
}

#[starknet::contract]
pub mod DynamicRate {
    use super::IDynamicRate;
    use super::{ContractAddress, IL1OracleDispatcher, IL1OracleDispatcherTrait};
    use super::{IERC20Dispatcher, IERC20DispatcherTrait};
    use core::starknet::storage::{StoragePointerWriteAccess, StoragePointerReadAccess};
    use starknet::get_caller_address;

    const BASIS_POINTS: u256 = 10000;
    const PRECISION: u256 = 1000000; // 6 decimals for rate precision

    #[storage]
    struct Storage {
        owner: ContractAddress,
        oracle: ContractAddress,
        min_rate: u256,
        max_rate: u256,
        // current_xzb_supply: u256,
        xzb_token: ContractAddress,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    pub enum Event {
        RateUpdated: RateUpdated,
        OracleUpdated: OracleUpdated,
        XZBTokenUpdated: XZBTokenUpdated,
        RateLimitsUpdated: RateLimitsUpdated,
    }

    #[derive(Drop, starknet::Event)]
    struct RateUpdated {
        #[key]
        new_rate: u256,
        tvl: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct OracleUpdated {
        #[key]
        oracle: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct XZBTokenUpdated {
        #[key]
        xzb_token: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct RateLimitsUpdated {
        min_rate: u256,
        max_rate: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        oracle: ContractAddress,
        min_rate: u256,
        max_rate: u256,
    ) {
        self.owner.write(owner);
        self.oracle.write(oracle);
        self.min_rate.write(min_rate);
        self.max_rate.write(max_rate);
    }

    #[abi(embed_v0)]
    impl DynamicRateImpl of super::IDynamicRate<ContractState> {
        fn get_dynamic_rate(self: @ContractState, tvl: u256) -> u256 {
            // Get current total TVL from oracle
            let oracle_dispatcher = IL1OracleDispatcher { contract_address: self.oracle.read() };
            let total_tvl = oracle_dispatcher.get_total_tvl();

            // Calculate new TVL including the incoming deposit
            let new_tvl = total_tvl + tvl;
            assert(new_tvl > 0, 'TVL cannot be zero');

            // Get current xZB supply
            let xzb_supply = self.get_current_xzb_supply();

            // Calculate new protocol rate
            // new_rate = (current_xZB_supply / new_TLV) * PRECISION
            let raw_rate = (xzb_supply * PRECISION) / new_tvl;

            // Apply rate limits
            let min_rate = self.min_rate.read();
            let max_rate = self.max_rate.read();

            let final_rate = if raw_rate < min_rate {
                min_rate
            } else if raw_rate > max_rate {
                max_rate
            } else {
                raw_rate
            };

            // self.emit(Event::RateUpdated(RateUpdated { new_rate: final_rate, tvl: new_tvl }));
            final_rate
        }

        fn get_current_xzb_supply(self: @ContractState) -> u256 {
            let xzb_token = self.xzb_token.read();

            // Create dispatcher to call the ERC20 contract
            let xzb_dispatcher = IERC20Dispatcher { contract_address: xzb_token };

            // Get total supply from the token contract
            xzb_dispatcher.total_supply()
        }

        fn set_min_rate(ref self: ContractState, rate: u256) {
            self.only_owner();
            assert(rate < self.max_rate.read(), 'Min rate must be < max rate');
            self.min_rate.write(rate);
            self
                .emit(
                    Event::RateLimitsUpdated(
                        RateLimitsUpdated { min_rate: rate, max_rate: self.max_rate.read() },
                    ),
                );
        }

        fn set_max_rate(ref self: ContractState, rate: u256) {
            self.only_owner();
            assert(rate > self.min_rate.read(), 'Max rate must be > min rate');
            self.max_rate.write(rate);
            self
                .emit(
                    Event::RateLimitsUpdated(
                        RateLimitsUpdated { min_rate: self.min_rate.read(), max_rate: rate },
                    ),
                );
        }

        fn set_oracle(ref self: ContractState, oracle: ContractAddress) {
            self.only_owner();
            self.oracle.write(oracle);
            self.emit(Event::OracleUpdated(OracleUpdated { oracle }));
        }

        fn set_xzb_token(ref self: ContractState, xzb_token: ContractAddress) {
            self.only_owner();
            self.xzb_token.write(xzb_token);
            self.emit(Event::XZBTokenUpdated(XZBTokenUpdated { xzb_token }));
        }
    }

    #[generate_trait]
    impl InternalFunctions of InternalFunctionsTrait {
        fn only_owner(self: @ContractState) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), 'Only owner');
        }
    }
}
