use clt_ekubo::interfaces::clt_base::{
    DepositParams, ShiftLiquidityParams, ICLTBaseDispatcher, ICLTBaseDispatcherTrait,
    StrategyParams, SwapOrderParams,
};

use clt_ekubo::interfaces::erc_4626::IERC4626Dispatcher;
use clt_ekubo::types::pool_id::PoolIdTrait;
use core::num::traits::{Bounded, Zero};
use ekubo::interfaces::core::ICoreDispatcherTrait;
use ekubo::interfaces::mathlib::{IMathLibDispatcherTrait, dispatcher as ekubo_math};
use ekubo::types::i129::i129;
use ekubo::types::keys::{PoolKey, PositionKey};
use snforge_std::{start_cheat_block_timestamp_global};
use starknet::{get_contract_address, get_block_timestamp};
use crate::utils::deploy::deploy_mock_extension;
use crate::utils::ekubo::{ekubo_core, get_ekubo_pool_key, swap};
use crate::utils::erc20::{approve, balance_of};
use crate::utils::fixtures::{base_init, set_actions, token2};
use crate::utils::helpers::{SQRT_RATIO_1_1, ether};


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
                is_compound: true,
                is_private: false,
                vault0: Zero::zero(),
                vault1: Zero::zero(),
            },
        );

    approve(token0.contract_address, base.contract_address, Bounded::MAX);
    approve(token1.contract_address, base.contract_address, Bounded::MAX);

    (base, pool_key, actions)
}

// scarb test clt_ekubo_tests::exit_module_test::test_exit_and_hold --exact
#[test]
#[fork("mainnet")]
fn test_simple_shift() {
    let (base, pool_key, _) = setup();

    let (balance_before0, balance_before1) = (
        balance_of(pool_key.token0, get_contract_address()),
        balance_of(pool_key.token1, get_contract_address()),
    );

    let deposit_amount = ether(20);
    //the current pool is with 1% fee.
    let ekubo_fee: u256 =
        200000000000000000; //ekubo charge withdraw fee same the fee tier set by user.

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

    assert_eq!(
        balance_before0, balance_of(pool_key.token0, get_contract_address()) + deposit_amount,
    );
    assert_eq!(
        balance_before1, balance_of(pool_key.token1, get_contract_address()) + deposit_amount,
    );

    assert_eq!(balance_of(pool_key.token0, ekubo_core().contract_address), deposit_amount);
    assert_eq!(balance_of(pool_key.token1, ekubo_core().contract_address), deposit_amount);

    let (strategy, _) = base.strategies(pool_key.to_id());

    let ekubo_share = ekubo_core()
        .get_position(
            pool_key,
            PositionKey { salt: 0, owner: base.contract_address, bounds: strategy.key.into() },
        )
        .liquidity;

    assert_eq!(strategy.account.ekubo_liquidity, ekubo_share);

    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);
    swap(pool_key, ether(1), true);
    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);
    swap(pool_key, ether(1), true);
    // base
//     .shift_liquidity(
//         ShiftLiquidityParams {
//             exchange_address: Zero::zero(),
//             exchange_address: Zero::zero(),
//             order: SwapOrderParams {

    //             },
//             swap_data: "".into(),
//             swap_selector: "".into(),
//         },
//     )
}
