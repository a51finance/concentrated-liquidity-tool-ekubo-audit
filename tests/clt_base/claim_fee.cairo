use core::num::traits::{Bounded, Zero};
use snforge_std::{
    spy_events, start_cheat_caller_address, stop_cheat_caller_address, cheat_caller_address,
    CheatSpan, EventSpyAssertionsTrait,
};
use starknet::{get_contract_address, contract_address_const};
use ekubo::interfaces::mathlib::{dispatcher as ekubo_math, IMathLibDispatcherTrait};
use ekubo::types::i129::i129;
use ekubo::types::keys::PoolKey;

use clt_ekubo::clt_base::CLTBase;
use clt_ekubo::components::constants::Constants;
use clt_ekubo::components::math::Math;
use clt_ekubo::interfaces::clt_base::{
    ICLTBaseDispatcher, ICLTBaseDispatcherTrait, StrategyParams, DepositParams, WithdrawParams,
    ClaimFeeParams,
};
use clt_ekubo::interfaces::erc_4626::IERC4626Dispatcher;
use clt_ekubo::types::pool_id::PoolIdTrait;

use crate::utils::deploy::deploy_mock_extension;
use crate::utils::ekubo::{get_ekubo_pool_key, swap};
use crate::utils::erc20::{approve, balance_of, transfer};
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
fn test_claim_fee_emit_correct_values() {
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

    swap(pool_key, ether(2), true);
    swap(pool_key, ether(2), false);

    let (_, fee0, fee1) = base.get_strategy_reserves(pool_key.to_id(), true);

    let mut spy = spy_events();
    base.claim_position_fee(ClaimFeeParams { recipient: get_contract_address(), token_id: 1 });

    spy
        .assert_emitted(
            @array![
                (
                    base.contract_address,
                    CLTBase::Event::Collect(
                        CLTBase::Collect {
                            token_id: 1,
                            recipient: get_contract_address(),
                            amount0_collected: fee0 - 1,
                            amount1_collected: fee1 - 1,
                        },
                    ),
                ),
            ],
        );
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('CLTBASE: only non compounders',))]
fn test_claim_fee_reverts_if_compounder() {
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
                is_private: false,
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

    swap(pool_key, ether(2), true);
    base.claim_position_fee(ClaimFeeParams { recipient: get_contract_address(), token_id: 1 });
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('CLTBASE: no liquidity',))]
fn test_claim_fee_reverts_if_no_liquidity() {
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

    base
        .withdraw(
            WithdrawParams {
                token_id: 1,
                liquidity: deposit_amount,
                recipient: get_contract_address(),
                amount0_min: 0,
                amount1_min: 0,
            },
        );

    base.claim_position_fee(ClaimFeeParams { recipient: get_contract_address(), token_id: 1 });
}

#[test]
#[fork("mainnet")]
fn test_claim_fee_fee_share() {
    let (base, pool_key, _) = setup();

    let deposit_amount = ether(4);

    let user1 = contract_address_const::<1>();

    transfer(pool_key.token0, user1, deposit_amount);
    transfer(pool_key.token1, user1, deposit_amount);

    start_cheat_caller_address(pool_key.token0, user1);
    approve(pool_key.token0, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token0);
    start_cheat_caller_address(pool_key.token1, user1);
    approve(pool_key.token1, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token1);

    cheat_caller_address(base.contract_address, user1, CheatSpan::TargetCalls(1));
    base
        .deposit(
            DepositParams {
                strategy_id: pool_key.to_id(),
                amount0_desired: deposit_amount,
                amount1_desired: deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
                recipient: user1,
            },
        );

    swap(pool_key, ether(2), true);
    swap(pool_key, ether(2), false);

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

    cheat_caller_address(base.contract_address, user1, CheatSpan::TargetCalls(1));
    base.claim_position_fee(ClaimFeeParams { recipient: user1, token_id: 1 });

    assert_eq!(balance_of(pool_key.token0, user1), strategy.account.fee0 - 1);
    assert_eq!(balance_of(pool_key.token1, user1), strategy.account.fee1 - 1);
}

#[test]
#[fork("mainnet")]
fn test_claim_fee_multiple_user_share() {
    let (base, pool_key, _) = setup();

    let user1_deposit = ether(4);
    let user2_deposit = ether(12);

    let (user1, user2) = (contract_address_const::<1>(), contract_address_const::<2>());

    transfer(pool_key.token0, user1, user1_deposit);
    transfer(pool_key.token1, user1, user1_deposit);

    start_cheat_caller_address(pool_key.token0, user1);
    approve(pool_key.token0, base.contract_address, user1_deposit);
    stop_cheat_caller_address(pool_key.token0);
    start_cheat_caller_address(pool_key.token1, user1);
    approve(pool_key.token1, base.contract_address, user1_deposit);
    stop_cheat_caller_address(pool_key.token1);

    transfer(pool_key.token0, user2, user2_deposit);
    transfer(pool_key.token1, user2, user2_deposit);

    start_cheat_caller_address(pool_key.token0, user2);
    approve(pool_key.token0, base.contract_address, user2_deposit);
    stop_cheat_caller_address(pool_key.token0);
    start_cheat_caller_address(pool_key.token1, user2);
    approve(pool_key.token1, base.contract_address, user2_deposit);
    stop_cheat_caller_address(pool_key.token1);

    cheat_caller_address(base.contract_address, user1, CheatSpan::TargetCalls(1));
    base
        .deposit(
            DepositParams {
                strategy_id: pool_key.to_id(),
                amount0_desired: user1_deposit,
                amount1_desired: user1_deposit,
                amount0_min: 0,
                amount1_min: 0,
                recipient: user1,
            },
        );

    cheat_caller_address(base.contract_address, user2, CheatSpan::TargetCalls(1));
    base
        .deposit(
            DepositParams {
                strategy_id: pool_key.to_id(),
                amount0_desired: user2_deposit,
                amount1_desired: user2_deposit,
                amount0_min: 0,
                amount1_min: 0,
                recipient: user2,
            },
        );

    swap(pool_key, ether(2), true);

    let (_, total_fee0, _) = base.get_strategy_reserves(pool_key.to_id(), true);

    cheat_caller_address(base.contract_address, user1, CheatSpan::TargetCalls(1));
    base.claim_position_fee(ClaimFeeParams { recipient: user1, token_id: 1 });

    cheat_caller_address(base.contract_address, user2, CheatSpan::TargetCalls(1));
    base.claim_position_fee(ClaimFeeParams { recipient: user2, token_id: 2 });

    assert_eq!(balance_of(pool_key.token0, user1), Math::mul_div(total_fee0, 25, 100));
    assert_eq!(balance_of(pool_key.token0, user2), Math::mul_div(total_fee0, 75, 100));
}

#[test]
#[fork("mainnet")]
fn test_claim_fee_multiple_user_with_different_share() {
    let (base, pool_key, _) = setup();

    let deposit_amount = ether(10);

    let (user1, user2) = (contract_address_const::<1>(), contract_address_const::<2>());

    transfer(pool_key.token0, user1, deposit_amount);
    transfer(pool_key.token1, user1, deposit_amount);

    start_cheat_caller_address(pool_key.token0, user1);
    approve(pool_key.token0, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token0);
    start_cheat_caller_address(pool_key.token1, user1);
    approve(pool_key.token1, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token1);

    transfer(pool_key.token0, user2, deposit_amount);
    transfer(pool_key.token1, user2, deposit_amount);

    start_cheat_caller_address(pool_key.token0, user2);
    approve(pool_key.token0, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token0);
    start_cheat_caller_address(pool_key.token1, user2);
    approve(pool_key.token1, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token1);

    cheat_caller_address(base.contract_address, user1, CheatSpan::TargetCalls(1));
    base
        .deposit(
            DepositParams {
                strategy_id: pool_key.to_id(),
                amount0_desired: deposit_amount,
                amount1_desired: deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
                recipient: user1,
            },
        );

    swap(pool_key, ether(2), true);

    cheat_caller_address(base.contract_address, user2, CheatSpan::TargetCalls(1));
    base
        .deposit(
            DepositParams {
                strategy_id: pool_key.to_id(),
                amount0_desired: deposit_amount,
                amount1_desired: deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
                recipient: user2,
            },
        );

    swap(pool_key, ether(2), true);

    let (_, total_fee0, _) = base.get_strategy_reserves(pool_key.to_id(), true);

    cheat_caller_address(base.contract_address, user1, CheatSpan::TargetCalls(1));
    base.claim_position_fee(ClaimFeeParams { recipient: user1, token_id: 1 });

    cheat_caller_address(base.contract_address, user2, CheatSpan::TargetCalls(1));
    base.claim_position_fee(ClaimFeeParams { recipient: user2, token_id: 2 });
}

#[test]
#[fork("mainnet")]
fn test_claimFee_should_pay_strategist_fee() {
    let (base, pool_key, actions) = setup();
    let pool_key = get_ekubo_pool_key(pool_key.token0, pool_key.token1, Zero::zero(), 1, 200);

    let (user1, user2) = (contract_address_const::<1>(), contract_address_const::<2>());

    let performance_fee = 100000000000000000; //0.1% in wei

    base
        .create_strategy(
            StrategyParams {
                pool_key,
                owner: user1,
                actions,
                tick_lower: i129 { mag: 200, sign: true },
                tick_upper: i129 { mag: 200, sign: false },
                initial_tick: ekubo_math().sqrt_ratio_to_tick(SQRT_RATIO_1_1),
                management_fee: 0,
                performance_fee,
                is_compound: false,
                is_private: false,
                vault0: Zero::zero(),
                vault1: Zero::zero(),
            },
        );

    let deposit_amount = ether(10);

    transfer(pool_key.token0, user2, deposit_amount);
    transfer(pool_key.token1, user2, deposit_amount);

    start_cheat_caller_address(pool_key.token0, user2);
    approve(pool_key.token0, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token0);
    start_cheat_caller_address(pool_key.token1, user2);
    approve(pool_key.token1, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token1);

    cheat_caller_address(base.contract_address, user2, CheatSpan::TargetCalls(1));
    base
        .deposit(
            DepositParams {
                strategy_id: pool_key.to_id(),
                amount0_desired: deposit_amount,
                amount1_desired: deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
                recipient: user2,
            },
        );

    swap(pool_key, ether(2), true);
    swap(pool_key, ether(2), false);

    let (fee0, fee1) = base.get_user_fees(1);
    let strategy_owner_share0 = Math::mul_div(fee0, performance_fee, Constants::WAD);
    let strategy_owner_share1 = Math::mul_div(fee1, performance_fee, Constants::WAD);

    cheat_caller_address(base.contract_address, user2, CheatSpan::TargetCalls(1));
    base.claim_position_fee(ClaimFeeParams { recipient: user2, token_id: 1 });

    assert_eq!(balance_of(pool_key.token0, user2), fee0 - strategy_owner_share0);
    assert_eq!(balance_of(pool_key.token1, user2), fee0 - strategy_owner_share1);

    assert_eq!(balance_of(pool_key.token0, user1), strategy_owner_share0);
    assert_eq!(balance_of(pool_key.token1, user1), strategy_owner_share1);
}
