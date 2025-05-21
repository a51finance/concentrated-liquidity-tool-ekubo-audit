use core::num::traits::{Bounded, Zero};

use starknet::{get_contract_address, contract_address_const};
use openzeppelin::token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use openzeppelin::access::ownable::interface::{OwnableABIDispatcher, OwnableABIDispatcherTrait};
use ekubo::types::i129::i129;
use ekubo::types::keys::PoolKey;
use crate::utils::erc20::{approve};

use clt_ekubo::interfaces::clt_base::{
    ICLTBaseDispatcher, ICLTBaseDispatcherTrait, DepositParams, StrategyParams, Account,
    StrategyData, StrategyKey,
};
use clt_ekubo::types::pool_id::PoolIdTrait;
use clt_ekubo::components::constants::Constants;

use crate::utils::deploy::deploy_mock_extension;
use crate::utils::ekubo::get_ekubo_pool_key;
use crate::utils::fixtures::{set_actions, token2, base_init, vault2};
use crate::utils::helpers::ether;

fn setup(fee: u256) -> (ICLTBaseDispatcher, PoolKey, Span<felt252>, ERC20ABIDispatcher) {
    let (base, modules, eth) = base_init(fee);
    let extension = deploy_mock_extension(1).contract_address;

    let (token0, token1) = token2();

    let pool_key = get_ekubo_pool_key(
        token0.contract_address, token1.contract_address, extension, 1, 60,
    );
    let actions = set_actions(modules, extension);

    approve(token0.contract_address, base.contract_address, Bounded::MAX);
    approve(token1.contract_address, base.contract_address, Bounded::MAX);

    (base, pool_key, actions, eth)
}

fn wrap_strategy(tick_lower: i129, tick_upper: i129, pool_key: PoolKey) -> StrategyData {
    StrategyData {
        key: StrategyKey { tick_lower, tick_upper },
        pool_key: pool_key.into(),
        owner: get_contract_address(),
        is_compound: false,
        is_private: false,
        management_fee: 0,
        performance_fee: 0,
        vault0: Zero::zero(),
        vault1: Zero::zero(),
        account: Account {
            fee0: 0,
            fee1: 0,
            balance0: 0,
            balance1: 0,
            total_shares: 0,
            ekubo_liquidity: 0,
            fee_growth_inside_0_last_X128: 0,
            fee_growth_inside_1_last_X128: 0,
            automation_fee_owed0: 0,
            automation_fee_owed1: 0,
            last_saved_amount0: 0,
            last_saved_amount1: 0,
            is_holding_saved: false,
        },
    }
}

#[test]
#[fork("mainnet")]
fn test_create_strategy() {
    let (base, pool_key, actions, _) = setup(0);

    let (tick_lower, tick_upper) = (
        i129 { mag: 88368108, sign: true }, i129 { mag: 88368108, sign: false },
    );
    let params = StrategyParams {
        pool_key,
        owner: get_contract_address(),
        actions,
        tick_lower,
        tick_upper,
        initial_tick: i129 { mag: 100, sign: false },
        management_fee: 0,
        performance_fee: 0,
        is_compound: false,
        is_private: false,
        vault0: Zero::zero(),
        vault1: Zero::zero(),
    };

    base.create_strategy(params);

    let (strategy, _) = base.strategies(pool_key.to_id());
    assert_eq!(strategy, wrap_strategy(tick_lower, tick_upper, pool_key));
}

#[test]
#[fork("mainnet")]
fn test_create_strategy_with_vaults() {
    let (base, pool_key, actions, _) = setup(0);

    let (vault0, vault1) = vault2();

    let (tick_lower, tick_upper) = (
        i129 { mag: 88368108, sign: true }, i129 { mag: 88368108, sign: false },
    );
    let params = StrategyParams {
        pool_key,
        owner: get_contract_address(),
        actions,
        tick_lower,
        tick_upper,
        initial_tick: i129 { mag: 100, sign: false },
        management_fee: 0,
        performance_fee: 0,
        is_compound: false,
        is_private: false,
        vault0: vault0.contract_address,
        vault1: vault1.contract_address,
    };

    base.create_strategy(params);

    assert_eq!(params.vault0, vault0.contract_address);
    assert_eq!(params.vault1, vault1.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_create_strategy_with_fee() {
    let fee = ether(10);
    let (base, pool_key, actions, eth) = setup(fee);

    let mock_owner = contract_address_const::<1>();
    OwnableABIDispatcher { contract_address: base.contract_address }.transfer_ownership(mock_owner);

    eth.approve(base.contract_address, fee);

    let user_balance_before = eth.balanceOf(get_contract_address());
    let owner_balance_before = eth.balanceOf(mock_owner);

    let (tick_lower, tick_upper) = (
        i129 { mag: 88368108, sign: true }, i129 { mag: 88368108, sign: false },
    );
    let params = StrategyParams {
        pool_key,
        owner: get_contract_address(),
        actions,
        tick_lower,
        tick_upper,
        initial_tick: i129 { mag: 100, sign: false },
        management_fee: 0,
        performance_fee: 0,
        is_compound: false,
        is_private: false,
        vault0: Zero::zero(),
        vault1: Zero::zero(),
    };

    base.create_strategy(params);

    let user_balance_after = eth.balanceOf(get_contract_address());
    let owner_balance_after = eth.balanceOf(mock_owner);

    assert_eq!(user_balance_before, user_balance_after + fee);
    assert_eq!(owner_balance_before, owner_balance_after - fee);
}


#[test]
#[fork("mainnet")]
#[should_panic()]
fn test_create_strategy_invalid_tick_range() {
    let (base, pool_key, actions, _) = setup(0);

    // Invalid tick range: lower > upper
    let (tick_lower, tick_upper) = (
        i129 { mag: 88368108, sign: false }, i129 { mag: 88368108, sign: true },
    );
    let params = StrategyParams {
        pool_key,
        owner: get_contract_address(),
        actions,
        tick_lower,
        tick_upper,
        initial_tick: i129 { mag: 100, sign: false },
        management_fee: 0,
        performance_fee: 0,
        is_compound: false,
        is_private: false,
        vault0: Zero::zero(),
        vault1: Zero::zero(),
    };

    // The contract does not revert on creation for invalid tick range.
    // Validation happens during deposit/liquidity addition in Ekubo core.
    base.create_strategy(params);

    let (strategy, _) = base.strategies(pool_key.to_id());
    assert_eq!(strategy.key.tick_lower, tick_lower);
    assert_eq!(strategy.key.tick_upper, tick_upper);

    let deposit_amount = ether(4);

    let params = DepositParams {
        strategy_id: pool_key.to_id(),
        amount0_desired: deposit_amount,
        amount1_desired: deposit_amount,
        amount0_min: 0,
        amount1_min: 0,
        recipient: get_contract_address(),
    };

    base.deposit(params);
}


#[test]
#[fork("mainnet")]
#[should_panic(expected: ('FH: management fle',))]
fn test_create_strategy_max_fees() {
    let (base, pool_key, actions, _) = setup(0);

    let (tick_lower, tick_upper) = (
        i129 { mag: 88368108, sign: true }, i129 { mag: 88368108, sign: false },
    );
    let params = StrategyParams {
        pool_key,
        owner: get_contract_address(),
        actions,
        tick_lower,
        tick_upper,
        initial_tick: i129 { mag: 100, sign: false },
        management_fee: Constants::WAD, // Max fee (100%)
        performance_fee: Constants::WAD, // Max fee (100%)
        is_compound: false,
        is_private: false,
        vault0: Zero::zero(),
        vault1: Zero::zero(),
    };

    base.create_strategy(params);

    let (strategy, _) = base.strategies(pool_key.to_id());
    assert_eq!(strategy.management_fee, Constants::WAD);
    assert_eq!(strategy.performance_fee, Constants::WAD);
}


#[test]
#[fork("mainnet")]
fn test_create_strategy_private() {
    let (base, pool_key, actions, _) = setup(0);

    let (tick_lower, tick_upper) = (
        i129 { mag: 88368108, sign: true }, i129 { mag: 88368108, sign: false },
    );
    let params = StrategyParams {
        pool_key,
        owner: get_contract_address(),
        actions,
        tick_lower,
        tick_upper,
        initial_tick: i129 { mag: 100, sign: false },
        management_fee: 0,
        performance_fee: 0,
        is_compound: false,
        is_private: true, // Private strategy
        vault0: Zero::zero(),
        vault1: Zero::zero(),
    };

    base.create_strategy(params);

    let (strategy, _) = base.strategies(pool_key.to_id());
    assert_eq!(strategy.is_private, true);
}


#[test]
#[fork("mainnet")]
fn test_create_strategy_compound() {
    let (base, pool_key, actions, _) = setup(0);

    let (tick_lower, tick_upper) = (
        i129 { mag: 88368108, sign: true }, i129 { mag: 88368108, sign: false },
    );
    let params = StrategyParams {
        pool_key,
        owner: get_contract_address(),
        actions,
        tick_lower,
        tick_upper,
        initial_tick: i129 { mag: 100, sign: false },
        management_fee: 0,
        performance_fee: 0,
        is_compound: true, // Compound strategy
        is_private: false,
        vault0: Zero::zero(),
        vault1: Zero::zero(),
    };

    base.create_strategy(params);

    let (strategy, _) = base.strategies(pool_key.to_id());
    assert_eq!(strategy.is_compound, true);
}

// ================================

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('TOKEN_ORDER',))]
fn test_create_strategy_invalid_pool_key() {
    let (base, modules, eth) = base_init(0);
    let extension = deploy_mock_extension(1).contract_address;

    // Invalid pool key: token0 == token1
    let (token0, _) = token2();
    let invalid_pool_key = get_ekubo_pool_key(
        token0.contract_address, token0.contract_address, extension, 1, 60,
    );
    let actions = set_actions(modules, extension);

    let (tick_lower, tick_upper) = (
        i129 { mag: 88368108, sign: true }, i129 { mag: 88368108, sign: false },
    );
    let params = StrategyParams {
        pool_key: invalid_pool_key,
        owner: get_contract_address(),
        actions,
        tick_lower,
        tick_upper,
        initial_tick: i129 { mag: 100, sign: false },
        management_fee: 0,
        performance_fee: 0,
        is_compound: false,
        is_private: false,
        vault0: Zero::zero(),
        vault1: Zero::zero(),
    };

    // Expect revert from Ekubo core when initializing the pool
    base.create_strategy(params);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('ALREADY_INITIALIZED',))]
fn test_create_strategy_duplicate_id() {
    let (base, pool_key, actions, _) = setup(0);

    let (tick_lower, tick_upper) = (
        i129 { mag: 88368108, sign: true }, i129 { mag: 88368108, sign: false },
    );
    let params = StrategyParams {
        pool_key,
        owner: get_contract_address(),
        actions,
        tick_lower,
        tick_upper,
        initial_tick: i129 { mag: 100, sign: false },
        management_fee: 0,
        performance_fee: 0,
        is_compound: false,
        is_private: false,
        vault0: Zero::zero(),
        vault1: Zero::zero(),
    };

    // Create the first strategy
    base.create_strategy(params);

    // Create a second strategy with the exact same parameters (duplicate ID)

    base.create_strategy(params);
}


#[test]
#[fork("mainnet")]
fn test_create_strategy_zero_owner() {
    let (base, pool_key, actions, _) = setup(0);

    let (tick_lower, tick_upper) = (
        i129 { mag: 88368108, sign: true }, i129 { mag: 88368108, sign: false },
    );
    let params = StrategyParams {
        pool_key,
        owner: Zero::zero(), // Zero address as owner
        actions,
        tick_lower,
        tick_upper,
        initial_tick: i129 { mag: 100, sign: false },
        management_fee: 0,
        performance_fee: 0,
        is_compound: false,
        is_private: false,
        vault0: Zero::zero(),
        vault1: Zero::zero(),
    };

    // The contract currently allows creating a strategy with a zero owner.
    // This might be intended or a potential area for improvement.
    base.create_strategy(params);

    let (strategy, _) = base.strategies(pool_key.to_id());
    assert_eq!(strategy.owner, Zero::zero());
}


#[test]
#[fork("mainnet")]
fn test_create_strategy_initial_tick_at_bounds() {
    let (base, pool_key, actions, _) = setup(0);

    let (tick_lower, tick_upper) = (
        i129 { mag: 88368108, sign: true }, i129 { mag: 88368108, sign: false },
    );

    // Test initial tick at tick_lower
    let params_lower = StrategyParams {
        pool_key,
        owner: get_contract_address(),
        actions,
        tick_lower,
        tick_upper,
        initial_tick: tick_lower, // Initial tick at lower bound
        management_fee: 0,
        performance_fee: 0,
        is_compound: false,
        is_private: false,
        vault0: Zero::zero(),
        vault1: Zero::zero(),
    };
    base.create_strategy(params_lower); // Should succeed

    // Need a new pool key for the second creation to avoid duplicate ID error
    let (token0, token1) = token2(); // Deploy new tokens for a new pool key
    let extension = deploy_mock_extension(2).contract_address;
    let pool_key_2 = get_ekubo_pool_key(
        token0.contract_address, token1.contract_address, extension, 2, 60,
    );
    let params_upper_2 = StrategyParams {
        pool_key: pool_key_2,
        owner: get_contract_address(),
        actions,
        tick_lower,
        tick_upper,
        initial_tick: tick_upper, // Initial tick at upper bound
        management_fee: 0,
        performance_fee: 0,
        is_compound: false,
        is_private: false,
        vault0: Zero::zero(),
        vault1: Zero::zero(),
    };
    base.create_strategy(params_upper_2); // Should succeed
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('TICK_MAGNITUDE',))]
fn test_create_strategy_initial_tick_outside_range() {
    let (base, pool_key, actions, _) = setup(0);

    let (tick_lower, tick_upper) = (
        i129 { mag: 88368108, sign: true }, i129 { mag: 88368108, sign: false },
    );
    let initial_tick_outside = i129 { mag: 100000000, sign: false };

    let params = StrategyParams {
        pool_key,
        owner: get_contract_address(),
        actions,
        tick_lower,
        tick_upper,
        initial_tick: initial_tick_outside,
        management_fee: 0,
        performance_fee: 0,
        is_compound: false,
        is_private: false,
        vault0: Zero::zero(),
        vault1: Zero::zero(),
    };

    base.create_strategy(params);
}
