#[starknet::contract]
pub mod ExitModule {
    use core::num::traits::Zero;
    use starknet::{ContractAddress};
    use starknet::storage::{StoragePointerWriteAccess, StoragePointerReadAccess};
    use ekubo::interfaces::core::{
        ICoreDispatcher, ICoreDispatcherTrait, IExtension, SwapParameters, UpdatePositionParameters,
    };
    use ekubo::types::call_points::CallPoints;
    use ekubo::types::bounds::Bounds;
    use ekubo::types::delta::Delta;
    use ekubo::types::i129::i129;
    use ekubo::types::keys::{PoolKey};

    use clt_ekubo::components::constants::Constants;
    use clt_ekubo::components::util::{deserialize, serialize, keccak_hash};
    use clt_ekubo::interfaces::clt_base::{
        ICLTBaseDispatcher, ICLTBaseDispatcherTrait, ShiftLiquidityParams, SwapOrderParams,
    };
    use clt_ekubo::interfaces::clt_modules::StrategyPayload;
    use clt_ekubo::interfaces::clt_twap_quoter::{
        ICLTTwapQuoterDispatcher, ICLTTwapQuoterDispatcherTrait,
    };
    use clt_ekubo::interfaces::extension_input_validation::IExtensionInputValidation;
    use clt_ekubo::types::pool_id::PoolIdTrait;

    #[storage]
    struct Storage {
        base: ICLTBaseDispatcher,
        core: ICoreDispatcher,
        twap_quoter: ICLTTwapQuoterDispatcher,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        base: ICLTBaseDispatcher,
        core: ICoreDispatcher,
        twap_quoter: ICLTTwapQuoterDispatcher,
    ) {
        self.base.write(base);
        self.core.write(core);
        self.twap_quoter.write(twap_quoter);
        self._set_call_points();
    }
    #[generate_trait]
    impl Internal of InternalTrait {
        fn _set_call_points(ref self: ContractState) {
            self
                .core
                .read()
                .set_call_points(
                    CallPoints {
                        before_initialize_pool: false,
                        after_initialize_pool: false,
                        before_swap: false,
                        after_swap: true,
                        before_update_position: false,
                        after_update_position: false,
                        before_collect_fees: false,
                        after_collect_fees: false,
                    },
                );
        }

        fn _exit_and_hold(self: @ContractState, pool_key: PoolKey, action_data: Span<felt252>) {
            let (twap_duration, lower_exit_preference, upper_exit_preference) = deserialize::<
                (u32, i129, i129),
            >(action_data);
            let twap = self.twap_quoter.read().get_twap(pool_key, twap_duration);
            if twap < lower_exit_preference || twap > upper_exit_preference {
                self._shift_position(pool_key);
            }
        }


        fn _exit_and_swap(self: @ContractState, pool_key: PoolKey, action_data: Span<felt252>) {}

        fn _exit_and_reinvest(
            self: @ContractState, pool_key: PoolKey, action_data: Span<felt252>,
        ) {}

        fn _shift_position(self: @ContractState, pool_key: PoolKey) {
            let (strategy, _) = self.base.read().strategies(pool_key.to_id());

            // Update strategy state to reflect removed liquidity
            self
                .base
                .read()
                .shift_liquidity(
                    ShiftLiquidityParams {
                        is_manager_locked: false,
                        exchange_address: Zero::zero(),
                        order: SwapOrderParams {
                            key: strategy.key,
                            pool_key,
                            should_mint: false,
                            zero_for_one: false,
                            swap_amount: 0,
                            min_amount: 0,
                            deadline: 0,
                            action_name: Constants::IS_EXIT,
                            module_status: serialize::<bool>(@true).span(),
                        },
                        swap_data: array![].span(),
                        swap_selector: keccak_hash("swap"),
                    },
                );
        }
    }

    #[abi(embed_v0)]
    impl MockextensionImpl of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129,
        ) {
            assert(false, 'Call point not used');
        }

        fn after_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129,
        ) {
            assert(false, 'Call point not used');
        }

        fn before_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters,
        ) {
            assert(false, 'Call point not used');
        }

        //TODO: need to redesign shift liquidity for exit module
        //WHY? we are trying to remove funds after swap so when user perform swap through ekubo
        //router ekubo handle accounting in delta and the resolving of delta is done by router at
        //the end.
        //So, when we try to remove liquidity the ekubo doesn't have enough tokens.
        //To handle this ekubo core have two functions call save and load.
        //When we have to remove complete liquidity just after swap and we single handedly owns the
        //position we have to save the delta after removing liquidity instead of resolving
        //and next transaction can be bundled we have to load the delta and resolve it.
        fn after_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters,
            delta: Delta,
        ) {
            let (_, action_type) = self.base.read().strategies(pool_key.to_id());
            let (_, strategy_action) = deserialize::<(u256, Span<StrategyPayload>)>(action_type);

            for index in 0..strategy_action.len() {
                let action = *(strategy_action.get(index).unwrap().unbox());
                if action.intent == Constants::EXIT_STRATEGY {
                    if action.action_name == Constants::EXIT_AND_HOLD {
                        self._exit_and_hold(pool_key, action.data);
                    } else if action.action_name == Constants::EXIT_AND_SWAP {
                        self._exit_and_swap(pool_key, action.data);
                    } else if action.action_name == Constants::EXIT_AND_REINVEST {
                        self._exit_and_reinvest(pool_key, action.data);
                    }
                }
            };
        }


        fn before_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters,
        ) {
            assert(false, 'Call point not used');
        }

        fn after_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters,
            delta: Delta,
        ) {
            assert(false, 'Call point not used');
        }

        fn before_collect_fees(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            salt: felt252,
            bounds: Bounds,
        ) {
            assert(false, 'Call point not used');
        }

        fn after_collect_fees(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            salt: felt252,
            bounds: Bounds,
            delta: Delta,
        ) {
            assert(false, 'Call point not used');
        }
    }

    #[abi(embed_v0)]
    impl InputValidationImpl of IExtensionInputValidation<ContractState> {
        fn check_input_data(self: @ContractState, data: StrategyPayload) -> bool {
            true
        }
    }
}
