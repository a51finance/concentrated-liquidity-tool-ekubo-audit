#[starknet::contract]
pub mod RebaseModule {
    use core::num::traits::Zero;
    use starknet::{ContractAddress, get_block_timestamp};
    use starknet::storage::{StoragePointerWriteAccess, StoragePointerReadAccess};
    use ekubo::interfaces::core::{
        ICoreDispatcher, ICoreDispatcherTrait, IExtension, SwapParameters, UpdatePositionParameters,
    };
    use ekubo::types::call_points::CallPoints;
    use ekubo::types::bounds::Bounds;
    use ekubo::types::delta::Delta;
    use ekubo::types::i129::{i129, i129Trait};
    use ekubo::types::keys::PoolKey;

    use clt_ekubo::components::active_ticks_calculation::ActiveTicksCalculation;
    use clt_ekubo::components::constants::Constants;
    use clt_ekubo::components::liquidity_amounts::LiquidityAmounts;
    use clt_ekubo::components::math::Math;
    use clt_ekubo::components::util::{deserialize, serialize};
    use clt_ekubo::extensions::rebasing::interfaces::rebase_module::{
        ThresholdParams, ExecutableStrategiesData, AdjustedThresholdData, StrategyProcessingDetails,
        Errors,
    };
    use clt_ekubo::interfaces::clt_base::{
        ICLTBaseDispatcher, ICLTBaseDispatcherTrait, StrategyKey, ShiftLiquidityParams,
        SwapOrderParams,
    };
    use clt_ekubo::interfaces::clt_modules::StrategyPayload;
    use clt_ekubo::interfaces::clt_twap_quoter::{
        ICLTTwapQuoterDispatcher, ICLTTwapQuoterDispatcherTrait,
    };
    use clt_ekubo::interfaces::extension_input_validation::IExtensionInputValidation;
    use clt_ekubo::types::pool_id::{PoolId, PoolIdTrait};

    pub(crate) const SWAP_PERCENTAGE: u8 = 50;

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

    fn get_zero_for_one(
        amount0_desired: u256, amount1_desired: u256, amount0: u256, amount1: u256,
    ) -> bool {
        if (amount0_desired - amount0)
            * amount1_desired > (amount1_desired - amount1)
            * amount0_desired {
            return true;
        }
        false
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

        fn _execute_strategies(self: @ContractState, strategy_id: PoolId) {
            let data = self._get_strategy_data(strategy_id);
            if data.strategy_id != 0 && data.mode != 0 {
                self._process_strategy(data);
            }
        }

        fn _process_strategy(self: @ContractState, data: ExecutableStrategiesData) {
            let (strategy, _) = self.base.read().strategies(data.strategy_id);
            let details = StrategyProcessingDetails {
                rebase_count: 0,
                manual_swaps_count: 0,
                last_update_timeStamp: 0,
                last_rebalanced_ticks: Zero::zero(),
            };
            let mut params = ShiftLiquidityParams {
                is_manager_locked: false,
                exchange_address: Zero::zero(),
                order: SwapOrderParams {
                    key: StrategyKey { tick_lower: Zero::zero(), tick_upper: Zero::zero() },
                    pool_key: PoolKey {
                        token0: Zero::zero(),
                        token1: Zero::zero(),
                        fee: 0,
                        tick_spacing: 0,
                        extension: Zero::zero(),
                    },
                    should_mint: true,
                    zero_for_one: false,
                    swap_amount: 0,
                    min_amount: 0,
                    deadline: 0,
                    action_name: '',
                    module_status: array![].span(),
                },
                swap_data: array![].span(),
                swap_selector: '',
            };
            self
                ._execute_strategy_actions(
                    data, strategy.pool_key.into(), strategy.key, params, details,
                );
        }

        fn _execute_strategy_actions(
            self: @ContractState,
            data: ExecutableStrategiesData,
            pool_key: PoolKey,
            mut key: StrategyKey,
            mut params: ShiftLiquidityParams,
            details: StrategyProcessingDetails,
        ) {
            let original_key = key;
            let (tick_lower, tick_upper) = self
                ._get_ticks_for_mode_with_actions(key, pool_key, data.action_name);
            key.tick_lower = tick_lower;
            key.tick_upper = tick_upper;

            let mut threshold_data = AdjustedThresholdData {
                adjusted_lower_difference: Zero::zero(), adjusted_upper_difference: Zero::zero(),
            };

            self
                ._process_active_rebalance(
                    pool_key,
                    key,
                    original_key,
                    data.actions,
                    data.action_status,
                    ref params,
                    ref threshold_data,
                );
            self.finalize_module_status(details, key, ref params, threshold_data);

            self._shift_position(pool_key, ref params);
            self._place_swap_order(pool_key, ref params);
        }


        fn _place_swap_order(
            self: @ContractState, pool_key: PoolKey, ref params: ShiftLiquidityParams,
        ) {
            let (strategy, _) = self.base.read().strategies(pool_key.to_id());
            self
                .base
                .read()
                .place_swap_order(
                    SwapOrderParams {
                        key: strategy.key,
                        pool_key,
                        should_mint: true,
                        zero_for_one: params.order.zero_for_one,
                        swap_amount: params.order.swap_amount,
                        min_amount: params.order.min_amount,
                        deadline: get_block_timestamp().into() + 3600,
                        action_name: Constants::REBASE_STRATEGY,
                        module_status: params.order.module_status,
                    },
                );
        }

        fn _shift_position(
            self: @ContractState, pool_key: PoolKey, ref params: ShiftLiquidityParams,
        ) {
            let (strategy, _) = self.base.read().strategies(pool_key.to_id());

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
                            zero_for_one: params.order.zero_for_one,
                            swap_amount: 0,
                            min_amount: 0,
                            deadline: 0,
                            action_name: Constants::IS_EXIT,
                            module_status: serialize::<bool>(@true).span(),
                        },
                        swap_data: array![].span(),
                        swap_selector: '',
                    },
                );
        }

        fn _process_active_rebalance(
            self: @ContractState,
            pool_key: PoolKey,
            key: StrategyKey,
            original_key: StrategyKey,
            actions: Span<felt252>,
            action_status: Span<felt252>,
            ref params: ShiftLiquidityParams,
            ref threshold_data: AdjustedThresholdData,
        ) {
            let (amount_to_swap, zero_for_one) = self._get_swap_amount(pool_key, original_key, key);
            let (
                _,
                lower_threshold_diff,
                upper_threshold_diff,
                initial_current_tick,
                initial_tick_lower,
                initial_tick_upper,
            ) =
                deserialize::<
                (u32, i129, i129, i129, i129, i129),
            >(actions);

            let (_, _, adjusted_lower_difference, adjusted_upper_difference) = self
                ._get_adjusted_difference(
                    key,
                    pool_key,
                    action_status,
                    ThresholdParams {
                        lower_threshold_diff,
                        upper_threshold_diff,
                        initial_current_tick,
                        initial_tick_lower,
                        initial_tick_upper,
                    },
                );

            threshold_data.adjusted_lower_difference = adjusted_lower_difference;
            threshold_data.adjusted_upper_difference = adjusted_upper_difference;

            params.order.swap_amount = amount_to_swap;
            params.order.zero_for_one = zero_for_one;
        }

        fn finalize_module_status(
            self: @ContractState,
            details: StrategyProcessingDetails,
            key: StrategyKey, // new key
            ref params: ShiftLiquidityParams,
            threshold_data: AdjustedThresholdData,
        ) {
            let current_tick = self.core.read().get_pool_price(params.order.pool_key).tick;
            params.order.key = key; // new key
            params
                .order
                .module_status =
                    serialize::<
                        (u256, u256, u256, i129, i129, i129),
                    >(
                        @(
                            details.rebase_count,
                            details.last_update_timeStamp,
                            details.manual_swaps_count,
                            current_tick,
                            threshold_data.adjusted_lower_difference,
                            threshold_data.adjusted_upper_difference,
                        ),
                    )
                .span();
        }

        fn _get_swap_amount(
            self: @ContractState,
            strategy_id: PoolKey,
            original_key: StrategyKey,
            new_key: StrategyKey,
        ) -> (u256, bool) {
            let base = self.base.read();

            let (strategy, _) = base.strategies(strategy_id.to_id());
            let sqrt_ratio = self.core.read().get_pool_price(strategy_id).sqrt_ratio;

            let (mut amount0_desired, mut amount1_desired) =
                LiquidityAmounts::get_amounts_for_liquidity(
                sqrt_ratio, original_key.into(), strategy.account.ekubo_liquidity,
            );

            let (reserve0, reserve1) = (amount0_desired, amount1_desired);

            let (_, strategy_fee0, strategy_fee1) = base
                .get_strategy_reserves(strategy_id.to_id(), false);

            if strategy.is_compound {
                amount0_desired += strategy_fee0;
                amount1_desired += strategy_fee1;
            }

            amount0_desired += strategy.account.balance0;
            amount1_desired += strategy.account.balance1;

            let mut zero_for_one: bool = false;
            let mut amount_specified: u256 = 0;

            if reserve0 == 0 || reserve1 == 0 {
                zero_for_one = if amount0_desired > 0 {
                    true
                } else {
                    false
                };

                amount_specified =
                    if zero_for_one {
                        Math::mul_div(amount0_desired, SWAP_PERCENTAGE.into(), 100)
                    } else {
                        Math::mul_div(amount1_desired, SWAP_PERCENTAGE.into(), 100)
                    };
                return (amount_specified, zero_for_one);
            } else {
                let new_liquidity = LiquidityAmounts::get_liquidity_for_amounts(
                    sqrt_ratio, new_key.into(), amount0_desired, amount1_desired,
                );
                let (new_amount0, new_amount1) = LiquidityAmounts::get_amounts_for_liquidity(
                    sqrt_ratio, new_key.into(), new_liquidity,
                );
                zero_for_one =
                    get_zero_for_one(amount0_desired, amount1_desired, new_amount0, new_amount1);

                if zero_for_one {
                    amount_specified =
                        Math::mul_div(amount0_desired - new_amount0, SWAP_PERCENTAGE.into(), 100);
                } else {
                    amount_specified =
                        Math::mul_div(amount1_desired - new_amount1, SWAP_PERCENTAGE.into(), 100);
                }
                (amount_specified, zero_for_one)
            }
        }

        fn _get_ticks_for_mode_with_actions(
            self: @ContractState, key: StrategyKey, pool_key: PoolKey, action_name: felt252,
        ) -> (i129, i129) {
            if action_name == Constants::ACTIVE_REBALANCE {
                return self._get_ticks_for_mode_active(key, pool_key);
            }
            (Zero::zero(), Zero::zero())
        }

        fn _get_ticks_for_mode_active(
            self: @ContractState, key: StrategyKey, pool_key: PoolKey,
        ) -> (i129, i129) {
            ActiveTicksCalculation::shift_active(self.core.read(), key, pool_key)
        }

        fn _get_strategy_data(
            self: @ContractState, strategy_id: PoolId,
        ) -> ExecutableStrategiesData {
            let (strategy, action_type) = self.base.read().strategies(strategy_id);

            let (mode, strategy_actions) = deserialize::<
                (u256, Span<StrategyPayload>),
            >(action_type);

            let mut executable_strategy_data = ExecutableStrategiesData {
                strategy_id: 0,
                mode: 0,
                actions: array![].span(),
                action_status: array![].span(),
                action_name: 0,
            };

            for index in 0..strategy_actions.len() {
                let strategy_action = *(strategy_actions.get(index).unwrap().unbox());

                if strategy_action.intent == Constants::REBASE_STRATEGY
                    && strategy_action.action_name == Constants::ACTIVE_REBALANCE {
                    let action_status = self
                        .base
                        .read()
                        .action_status(strategy_id, strategy_action.action_name);

                    if self
                        ._check_active_rebalancing_strategies(
                            strategy.key,
                            strategy.pool_key.into(),
                            action_status,
                            strategy_action.data,
                            mode,
                        ) {
                        executable_strategy_data =
                            ExecutableStrategiesData {
                                strategy_id,
                                mode,
                                actions: strategy_action.data,
                                action_status,
                                action_name: strategy_action.action_name,
                            };
                        break;
                    }
                }
            };

            executable_strategy_data
        }

        fn _check_active_rebalancing_strategies(
            self: @ContractState,
            key: StrategyKey,
            pool_key: PoolKey,
            action_status: Span<felt252>,
            actions_data: Span<felt252>,
            mode: u256,
        ) -> bool {
            let (
                twap_duration,
                lower_preference_diff,
                upper_preference_diff,
                initial_current_tick,
                initial_tick_lower,
                initial_tick_upper,
            ) =
                deserialize::<
                (u32, i129, i129, i129, i129, i129),
            >(actions_data);

            let (lower_threshold_tick, upper_threshold_tick, _, _) = self
                ._get_preference_ticks(
                    key,
                    pool_key,
                    action_status,
                    Constants::ACTIVE_REBALANCE,
                    ThresholdParams {
                        lower_threshold_diff: lower_preference_diff,
                        upper_threshold_diff: upper_preference_diff,
                        initial_current_tick,
                        initial_tick_lower,
                        initial_tick_upper,
                    },
                );

            let tick = self.twap_quoter.read().get_twap(pool_key, twap_duration);
            println!("Twap Tick {}", tick.mag);
            if (mode == 2 && tick > upper_threshold_tick)
                || (mode == 1 && tick < lower_threshold_tick)
                || mode == 3 {
                if tick > upper_threshold_tick || tick < lower_threshold_tick {
                    return true;
                }
            }

            false
        }

        fn _get_preference_ticks(
            self: @ContractState,
            key: StrategyKey,
            pool_key: PoolKey,
            action_status: Span<felt252>,
            action_name: felt252,
            params: ThresholdParams,
        ) -> (i129, i129, i129, i129) {
            if action_name == Constants::ACTIVE_REBALANCE {
                return self._get_adjusted_difference(key, pool_key, action_status, params);
            }
            (Zero::zero(), Zero::zero(), Zero::zero(), Zero::zero())
        }

        fn _get_adjusted_difference(
            self: @ContractState,
            key: StrategyKey,
            pool_key: PoolKey,
            action_status: Span<felt252>,
            params: ThresholdParams,
        ) -> (i129, i129, i129, i129) {
            let mut last_rebalanced_tick: i129 = Zero::zero();
            let mut last_lower_difference: i129 = Zero::zero();
            let mut last_upper_difference: i129 = Zero::zero();

            if action_status.len() > 0 {
                let (
                    _,
                    _,
                    _,
                    _,
                    _last_rebalanced_tick,
                    _last_lower_difference,
                    _last_upper_difference,
                ) =
                    deserialize::<
                    (u256, bool, u256, u256, i129, i129, i129),
                >(action_status);
                last_rebalanced_tick = _last_rebalanced_tick;
                last_lower_difference = _last_lower_difference;
                last_upper_difference = _last_upper_difference;
            } else {
                last_rebalanced_tick = self.core.read().get_pool_price(pool_key).tick;
            }

            // If there's a previous rebalance, adjust the threshold ticks
            if last_lower_difference.is_non_zero() && last_upper_difference.is_non_zero() {
                return (
                    if last_lower_difference.sign == false {
                        key.tick_lower + last_lower_difference
                    } else {
                        key.tick_lower - last_lower_difference
                    },
                    if last_upper_difference.sign == false {
                        key.tick_upper - last_upper_difference
                    } else {
                        key.tick_upper + last_upper_difference
                    },
                    last_lower_difference,
                    last_upper_difference,
                );
            }

            // Default adjustment when initial ticks match key ticks
            if params.initial_tick_lower == key.tick_lower
                && params.initial_tick_upper == key.tick_upper {
                return (
                    key.tick_lower + params.lower_threshold_diff,
                    key.tick_upper - params.upper_threshold_diff,
                    Zero::zero(),
                    Zero::zero(),
                );
            }

            let lower_difference = (params.initial_current_tick - params.initial_tick_lower)
                - (last_rebalanced_tick - key.tick_lower);
            let upper_difference = (params.initial_tick_upper - params.initial_current_tick)
                - (key.tick_upper - last_rebalanced_tick);

            let adjusted_lower_difference = params.lower_threshold_diff
                + if lower_difference.is_negative() {
                    -lower_difference
                } else {
                    lower_difference
                };
            let adjusted_upper_difference = params.upper_threshold_diff
                + if upper_difference.is_negative() {
                    -upper_difference
                } else {
                    upper_difference
                };

            (
                if adjusted_lower_difference.is_negative() {
                    key.tick_lower + adjusted_lower_difference
                } else {
                    key.tick_lower - adjusted_lower_difference
                },
                if adjusted_upper_difference.is_negative() {
                    key.tick_upper - adjusted_upper_difference
                } else {
                    key.tick_upper + adjusted_upper_difference
                },
                adjusted_lower_difference,
                adjusted_upper_difference,
            )
        }
    }

    #[abi(embed_v0)]
    impl RebaseExtension of IExtension<ContractState> {
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

        fn after_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters,
            delta: Delta,
        ) {
            self._execute_strategies(pool_key.to_id());
        }

        fn before_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters,
        ) {
            assert(false, 'Call point not used');
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
            if data.action_name == Constants::ACTIVE_REBALANCE && data.data.len() > 0 {
                let (_, lower_preference_diff, upper_preference_diff, _, _, _) = deserialize::<
                    (u32, i129, i129, i129, i129, i129),
                >(data.data);
                if (lower_preference_diff.is_negative() || lower_preference_diff.is_zero())
                    || (upper_preference_diff.is_negative() || upper_preference_diff.is_zero()) {
                    assert(false, Errors::INVALID_REBASE_THRESHOLD_DIFFERENCE);
                };
                return true;
            }

            assert(false, Errors::REBASE_STRATEGY_DATA_CANNOT_BE_ZERO);
            false
        }
    }
}
