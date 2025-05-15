use core::num::traits::Zero;
use starknet::{get_contract_address, contract_address_const};
use openzeppelin::token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use openzeppelin::access::ownable::interface::{OwnableABIDispatcher, OwnableABIDispatcherTrait};
use ekubo::types::i129::i129;
use ekubo::types::keys::PoolKey;

use clt_ekubo::interfaces::clt_base::{
    ICLTBaseDispatcher, ICLTBaseDispatcherTrait, StrategyParams, Account, StrategyData, StrategyKey,
};
use clt_ekubo::types::pool_id::PoolIdTrait;

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
