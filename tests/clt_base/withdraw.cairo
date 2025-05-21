// External crates
use core::num::traits::{Bounded, Zero};
use starknet::{contract_address_const, get_contract_address};

// Starknet Forge and OpenZeppelin
use snforge_std::{declare, DeclareResultTrait, CheatSpan, cheat_caller_address};

// Ekubo Core & Math
use ekubo::interfaces::mathlib::{IMathLibDispatcherTrait, dispatcher as ekubo_math};
use ekubo::types::i129::i129;
use ekubo::types::keys::{PoolKey};
use clt_ekubo::types::pool_id::{PoolIdTrait};

// CLT-Ekubo Components
use clt_ekubo::components::util::serialize;

// CLT-Ekubo Interfaces
use clt_ekubo::interfaces::clt_base::{
    DepositParams, ICLTBaseDispatcher, ICLTBaseDispatcherTrait, StrategyParams, WithdrawParams,
};
use clt_ekubo::interfaces::clt_modules::StrategyPayload;

// CLT-Ekubo Extensions
use clt_ekubo::extensions::multiextension::interfaces::multiextension_deployer::IMultiextensionDeployerDispatcherTrait;
use clt_ekubo::extensions::multiextension::utils::bit_math::ExtensionMethod;
use clt_ekubo::extensions::multiextension::utils::activate_extension::{
    generate_extension_data, ExtStruct, ExtMethodStruct,
};

// Local Utils
use crate::utils::deploy::{
    deploy_mock_extension, deploy_twap_quoter, deploy_multiextension_deployer, deploy_oracle,
    deploy_exit_module,
};
use crate::utils::ekubo::{ekubo_core, get_ekubo_pool_key, swap};
use crate::utils::erc20::{approve, balance_of};
use crate::utils::fixtures::{base_init, token2, create_custom_actions, set_actions};
use crate::utils::helpers::{SQRT_RATIO_1_1, ether, hash_intent};

fn setup() -> (ICLTBaseDispatcher, PoolKey, Span<felt252>) {
    let (base, modules, _) = base_init(0);
    let extension = deploy_mock_extension(1).contract_address;
    let (token0, token1) = token2();

    //deploy multiextension deployer
    let multiextension_class = *declare("Multiextension").unwrap().contract_class().class_hash;
    let deployer = deploy_multiextension_deployer(multiextension_class, get_contract_address());
    //deploy multiextension
    let multiextension = deployer.deploy_multiextension();

    //oracle extension with token0 as base/oracle tokens
    let oracle_extension = deploy_oracle(
        get_contract_address(), ekubo_core(), token0.contract_address, multiextension,
    );

    //clt twap quoter
    let twap_quoter = deploy_twap_quoter(ekubo_core(), oracle_extension, get_contract_address());

    //exit module extension
    let exit_module = deploy_exit_module(base, ekubo_core(), twap_quoter);

    //create multiextension data
    let (activated_extensions, extensions) = generate_extension_data(
        array![
            ExtStruct {
                extension: oracle_extension.contract_address,
                methods: array![
                    ExtMethodStruct {
                        method: ExtensionMethod::BeforeInitPool, position: 0, activate: true,
                    },
                    ExtMethodStruct {
                        method: ExtensionMethod::BeforeSwap, position: 0, activate: true,
                    },
                    ExtMethodStruct {
                        method: ExtensionMethod::BeforeUpdatePosition, position: 0, activate: true,
                    },
                ]
                    .span(),
            },
            ExtStruct {
                extension: exit_module.contract_address,
                methods: array![
                    ExtMethodStruct {
                        method: ExtensionMethod::AfterSwap, position: 0, activate: true,
                    },
                ]
                    .span(),
            },
        ]
            .span(),
    );

    //init multiextension with extensions and activation
    deployer.init_multiextension(multiextension, extensions.span(), activated_extensions);

    let pool_key = get_ekubo_pool_key(
        token0.contract_address, token1.contract_address, extension, 1, //1%
        60,
    );

    //create intent
    let actions2 = create_custom_actions(
        modules,
        exit_module.contract_address,
        StrategyPayload {
            intent: hash_intent('EXIT_STRATEGY'),
            action_name: hash_intent('EXIT_AND_HOLD'),
            data: serialize::<
                (u32, i129, i129),
            >(@(3600, i129 { mag: 10, sign: true }, i129 { mag: 10, sign: false }))
                .span(),
        },
    );

    //create default strategy
    base
        .create_strategy(
            StrategyParams {
                pool_key: pool_key,
                owner: get_contract_address(),
                actions: actions2,
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
    (base, pool_key, actions2)
}

#[test]
#[fork("mainnet")]
fn test_withdraw_entire_position() {
    let (base, pool_key, _) = setup();
    let desired_deposit_amount = ether(20);

    // First deposit
    // Capture the actual amounts deposited, liquidity minted, and token_id
    let (token_id, liquidity_minted, amount0_deposited, amount1_deposited) = base
        .deposit(
            DepositParams {
                strategy_id: pool_key.to_id(),
                amount0_desired: desired_deposit_amount,
                amount1_desired: desired_deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
                recipient: get_contract_address(),
            },
        );

    let (balance_before_withdraw0, balance_before_withdraw1) = (
        balance_of(pool_key.token0, get_contract_address()),
        balance_of(pool_key.token1, get_contract_address()),
    );

    // Withdraw entire position
    // Use the actual token_id and liquidity_minted from the deposit
    // Capture the amounts actually withdrawn as returned by the contract
    let (amount0_withdrawn, amount1_withdrawn) = base
        .withdraw(
            WithdrawParams {
                token_id: token_id,
                liquidity: liquidity_minted,
                recipient: get_contract_address(),
                amount0_min: 0,
                amount1_min: 0,
            },
        );

    // Verify position is empty
    let position = base.positions(token_id);
    assert_eq!(position.liquidity_share, 0);

    // Verify balances after withdraw
    let (balance_after_withdraw0, balance_after_withdraw1) = (
        balance_of(pool_key.token0, get_contract_address()),
        balance_of(pool_key.token1, get_contract_address()),
    );

    //the amount left in ekubo
    let dust: u256 = 1;

    let ekubo_fee: u256 =
        200000000000000000; //ekubo charge withdraw fee same the fee tier set by user.

    assert_eq!(
        balance_after_withdraw0,
        balance_before_withdraw0 + amount0_withdrawn,
        "Balance0 mismatch after withdraw",
    );
    assert_eq!(
        balance_after_withdraw1,
        balance_before_withdraw1 + amount1_withdrawn,
        "Balance1 mismatch after withdraw",
    );

    assert_eq!(
        amount0_withdrawn + dust + ekubo_fee,
        amount0_deposited,
        "Withdrawn token0 amount does not match deposited amount",
    );
    assert_eq!(
        amount1_withdrawn + dust + ekubo_fee,
        amount1_deposited,
        "Withdrawn token1 amount does not match deposited amount",
    );
}

#[test]
#[fork("mainnet")]
fn test_withdraw_partial_position() {
    let (base, pool_key, _) = setup();
    let deposit_amount = ether(20);
    let withdraw_amount = ether(10);

    // First deposit
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

    let (balance_before0, balance_before1) = (
        balance_of(pool_key.token0, get_contract_address()),
        balance_of(pool_key.token1, get_contract_address()),
    );

    //the amount left in ekubo
    let dust: u256 = 1;

    let ekubo_fee: u256 = withdraw_amount
        * 1
        / 100; //ekubo charge withdraw fee same the fee tier set by user.

    // Withdraw partial position
    base
        .withdraw(
            WithdrawParams {
                token_id: 1,
                liquidity: withdraw_amount,
                recipient: get_contract_address(),
                amount0_min: 0,
                amount1_min: 0,
            },
        );

    // Verify balances after withdraw
    let (balance_after0, balance_after1) = (
        balance_of(pool_key.token0, get_contract_address()),
        balance_of(pool_key.token1, get_contract_address()),
    );

    assert_eq!(balance_after0 + dust + ekubo_fee, balance_before0 + withdraw_amount);
    assert_eq!(balance_after1 + dust + ekubo_fee, balance_before1 + withdraw_amount);

    // Verify remaining position
    let position = base.positions(1);
    assert_eq!(position.liquidity_share, deposit_amount - withdraw_amount);
}


#[test]
#[fork("mainnet")]
fn test_withdraw_with_fees() {
    let (base, modules, _) = base_init(0);
    let extension = deploy_mock_extension(1).contract_address;
    let (token0, token1) = token2();
    let pool_key = get_ekubo_pool_key(
        token0.contract_address, token1.contract_address, extension, 1, //1%
        60,
    );
    let deposit_amount = ether(20);
    let management_fee = 1000; // 10%
    let performance_fee = 2000; // 20%

    let actions = set_actions(modules, extension);
    // Create strategy with fees
    base
        .create_strategy(
            StrategyParams {
                pool_key,
                owner: get_contract_address(),
                actions,
                tick_lower: i129 { mag: 120, sign: true },
                tick_upper: i129 { mag: 120, sign: false },
                initial_tick: ekubo_math().sqrt_ratio_to_tick(SQRT_RATIO_1_1),
                management_fee,
                performance_fee,
                is_compound: false,
                is_private: false,
                vault0: Zero::zero(),
                vault1: Zero::zero(),
            },
        );

    approve(pool_key.token0, base.contract_address, Bounded::MAX);
    approve(pool_key.token1, base.contract_address, Bounded::MAX);

    // Deposit
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

    let (balance_before0, balance_before1) = (
        balance_of(pool_key.token0, get_contract_address()),
        balance_of(pool_key.token1, get_contract_address()),
    );

    // Generate some fees
    swap(pool_key, ether(1), true);
    swap(pool_key, ether(2), false);

    let (balance_after_swap0, balance_after_swap1) = (
        balance_of(pool_key.token0, get_contract_address()),
        balance_of(pool_key.token1, get_contract_address()),
    );

    // Get balances before withdraw

    // Withdraw
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

    // Verify balances after withdraw (should be less than deposit amount due to fees)
    let (balance_after0, balance_after1) = (
        balance_of(pool_key.token0, get_contract_address()),
        balance_of(pool_key.token1, get_contract_address()),
    );

    assert_lt!(balance_after0 - balance_before0, deposit_amount);
    assert_lt!(balance_after1 - balance_before1, deposit_amount);

    // Verify position is empty
    let position = base.positions(1);
    assert_eq!(position.liquidity_share, 0);
}


#[test]
#[fork("mainnet")]
#[should_panic(expected: ('CLTBASE: minimum amount exceeds',))]
fn test_withdraw_with_high_minimum_amounts() {
    let (base, pool_key, _) = setup();
    let deposit_amount = ether(20);
    let withdraw_amount = ether(10);
    let min_amount = ether(11);

    // First deposit
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

    // Try to withdraw with high minimum amounts
    base
        .withdraw(
            WithdrawParams {
                token_id: 1,
                liquidity: withdraw_amount,
                recipient: get_contract_address(),
                amount0_min: min_amount,
                amount1_min: min_amount,
            },
        );
}
