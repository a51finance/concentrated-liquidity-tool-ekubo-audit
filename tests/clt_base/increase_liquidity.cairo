use core::num::traits::{Bounded, Zero};
use snforge_std::{cheat_caller_address, CheatSpan};
use starknet::{get_contract_address, contract_address_const};
use ekubo::interfaces::mathlib::{dispatcher as ekubo_math, IMathLibDispatcherTrait};
use ekubo::types::i129::i129;
use ekubo::types::keys::PoolKey;

use clt_ekubo::components::constants::Constants;
use clt_ekubo::components::util::serialize;
use clt_ekubo::interfaces::clt_base::{
    ICLTBaseDispatcher, ICLTBaseDispatcherTrait, StrategyParams, DepositParams,
    UpdatePositionParams, ShiftLiquidityParams, SwapOrderParams,
};
use clt_ekubo::interfaces::erc_4626::IERC4626Dispatcher;
use clt_ekubo::types::pool_id::PoolIdTrait;

use crate::utils::deploy::deploy_mock_extension;
use crate::utils::ekubo::{get_ekubo_pool_key};
use crate::utils::erc20::approve;
use crate::utils::fixtures::{set_actions, token2, base_init};
use crate::utils::helpers::{ether, SQRT_RATIO_1_1};

fn setup() -> (ICLTBaseDispatcher, PoolKey, Span<felt252>) {
    let (base, modules, _) = base_init(0);
    let extension = deploy_mock_extension(1).contract_address;

    let (token0, token1) = token2();

    let pool_key = get_ekubo_pool_key(
        token0.contract_address, token1.contract_address, extension, 1, //1%
        60,
    );
    let actions = set_actions(modules, extension);

    //create default strategy
    base
        .create_strategy(
            StrategyParams {
                pool_key,
                owner: get_contract_address(),
                actions,
                tick_lower: i129 { mag: 120, sign: true },
                tick_upper: i129 { mag: 120, sign: false },
                initial_tick: ekubo_math().sqrt_ratio_to_tick(SQRT_RATIO_1_1),
                management_fee: 0,
                performance_fee: 0,
                is_compound: false,
                is_private: false,
                vault0: Zero::zero(),
                vault1: Zero::zero(),
            },
        );

    approve(token0.contract_address, base.contract_address, Bounded::MAX);
    approve(token1.contract_address, base.contract_address, Bounded::MAX);

    (base, pool_key, actions)
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('CLTBASE: not authorized',))]
fn test_increase_liq_reverts_only_owner_in_private_strategy() {
    let (base, pool_key, actions) = setup();
    let pool_key = get_ekubo_pool_key(pool_key.token0, pool_key.token1, Zero::zero(), 1, 200);

    base
        .create_strategy(
            StrategyParams {
                pool_key,
                owner: get_contract_address(),
                actions,
                tick_lower: i129 { mag: 200, sign: true },
                tick_upper: i129 { mag: 200, sign: false },
                initial_tick: ekubo_math().sqrt_ratio_to_tick(SQRT_RATIO_1_1),
                management_fee: 0,
                performance_fee: 0,
                is_compound: true,
                is_private: true,
                vault0: Zero::zero(),
                vault1: Zero::zero(),
            },
        );

    let deposit_amount = ether(4);
    base
        .deposit(
            DepositParams {
                strategy_id: pool_key.to_id(),
                amount0_desired: deposit_amount,
                amount1_desired: deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
                recipient: get_contract_address(),
            },
        );

    let user1 = contract_address_const::<1>();
    cheat_caller_address(base.contract_address, user1, CheatSpan::TargetCalls(1));
    base
        .update_position_liquidity(
            UpdatePositionParams {
                token_id: 1,
                amount0_desired: deposit_amount,
                amount1_desired: deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
            },
        );
}

#[test]
#[fork("mainnet")]
fn test_increase_liq_succeeds_with_correct_share() {
    let (base, pool_key, _) = setup();

    let deposit_amount = ether(4);
    base
        .deposit(
            DepositParams {
                strategy_id: pool_key.to_id(),
                amount0_desired: deposit_amount,
                amount1_desired: deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
                recipient: get_contract_address(),
            },
        );

    let liquidity_share_before = base.positions(1).liquidity_share;

    base
        .update_position_liquidity(
            UpdatePositionParams {
                token_id: 1,
                amount0_desired: deposit_amount,
                amount1_desired: deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
            },
        );

    let liquidity_share_after = base.positions(1).liquidity_share;

    assert_eq!(liquidity_share_after, liquidity_share_before + deposit_amount);

    base
        .deposit(
            DepositParams {
                strategy_id: pool_key.to_id(),
                amount0_desired: deposit_amount,
                amount1_desired: deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
                recipient: get_contract_address(),
            },
        );

    let liquidity_share_before = base.positions(2).liquidity_share;

    base
        .update_position_liquidity(
            UpdatePositionParams {
                token_id: 2,
                amount0_desired: deposit_amount,
                amount1_desired: deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
            },
        );

    let liquidity_share_after = base.positions(1).liquidity_share;

    assert_eq!(liquidity_share_after, liquidity_share_before + deposit_amount);
}

// #[test]
// #[fork("mainnet")]
fn test_increase_liq_succeeds_after_exit() {
    let (base, pool_key, _) = setup();

    let deposit_amount = ether(4);
    base
        .deposit(
            DepositParams {
                strategy_id: pool_key.to_id(),
                amount0_desired: deposit_amount,
                amount1_desired: deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
                recipient: get_contract_address(),
            },
        );

    let (strategy, _) = base.strategies(pool_key.to_id());

    base
        .shift_liquidity(
            ShiftLiquidityParams {
                is_manager_locked: false,
                exchange_address: Zero::zero(),
                order: SwapOrderParams {
                    key: strategy.key,
                    should_mint: false,
                    pool_key,
                    zero_for_one: false,
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

    base
        .shift_liquidity(
            ShiftLiquidityParams {
                is_manager_locked: false,
                exchange_address: Zero::zero(),
                order: SwapOrderParams {
                    key: strategy.key,
                    should_mint: false,
                    pool_key,
                    zero_for_one: false,
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

    let (strategy, _) = base.strategies(pool_key.to_id());

    let balance0_before = strategy.account.balance0;
    let balance1_before = strategy.account.balance1;

    base
        .update_position_liquidity(
            UpdatePositionParams {
                token_id: 1,
                amount0_desired: deposit_amount,
                amount1_desired: deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
            },
        );

    let (strategy, _) = base.strategies(pool_key.to_id());
    assert_eq!(strategy.account.balance0, balance0_before + deposit_amount);
    assert_eq!(strategy.account.balance1, balance1_before + deposit_amount);
}
