#[starknet::contract]
pub mod CLTTwapQuoter {
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StoragePointerWriteAccess, StoragePointerReadAccess, StoragePathEntry,
    };
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};
    use ekubo::types::i129::i129;
    use ekubo::types::keys::PoolKey;
    use openzeppelin::access::ownable::OwnableComponent;

    use clt_ekubo::extensions::oracle::interfaces::oracle::{
        IOracleDispatcher, IOracleDispatcherTrait,
    };
    use clt_ekubo::interfaces::clt_twap_quoter::{ICLTTwapQuoter, Errors};
    use clt_ekubo::types::pool_id::{PoolId, PoolIdTrait};

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl Ownable = OwnableComponent::OwnableImpl<ContractState>;

    impl OwnableInternal = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        oracle: IOracleDispatcher,
        pool_strategy: Map<PoolId, i129>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    pub enum Event {
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        core: ICoreDispatcher,
        oracle: IOracleDispatcher,
        owner: ContractAddress,
    ) {
        self.core.write(core);
        self.oracle.write(oracle);
        self.ownable.initializer(owner);
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn _calculate_twap(self: @ContractState, pool_key: PoolKey, twap_duration: u32) -> i129 {
            let core = self.core.read();
            let in_range_liquidity = core.get_pool_liquidity(pool_key);
            if in_range_liquidity == 0 {
                return core.get_pool_price(pool_key).tick;
            }
            self.get_twap(pool_key, twap_duration)
        }
    }

    #[abi(embed_v0)]
    impl CLTBaseImpl of ICLTTwapQuoter<ContractState> {
        fn pool_strategy(self: @ContractState, key: PoolId) -> i129 {
            self.pool_strategy.entry(key).read()
        }

        fn check_deviation(self: @ContractState, key: PoolKey, twap_duration: u32) {
            let twap = self._calculate_twap(key, twap_duration);
            let tick = self.core.read().get_pool_price(key).tick;
            let deviation: i129 = if tick > twap {
                tick
            } else {
                twap
            };
            assert(
                deviation <= self.pool_strategy.entry(key.to_id()).read(),
                Errors::MAX_TWAP_DEVIATION_EXCEEDED,
            );
        }

        fn get_twap(self: @ContractState, key: PoolKey, twap_duration: u32) -> i129 {
            self
                .oracle
                .read()
                .get_average_tick_over_last(key.token0, key.token1, twap_duration.into(), key)
        }
    }
}
