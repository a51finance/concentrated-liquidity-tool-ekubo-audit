// External crates
use core::num::traits::{Bounded, Zero};
use starknet::{contract_address_const, get_contract_address, get_block_timestamp};

// Starknet Forge and OpenZeppelin
use snforge_std::{
    declare, DeclareResultTrait, CheatSpan, cheat_caller_address, start_cheat_caller_address,
    start_cheat_caller_address_global, stop_cheat_caller_address, stop_cheat_caller_address_global,
    start_cheat_block_timestamp_global,
};
use openzeppelin::token::erc721::{ERC721ABIDispatcher, ERC721ABIDispatcherTrait};

// Ekubo Core & Math
use ekubo::interfaces::core::ICoreDispatcherTrait;
use ekubo::interfaces::mathlib::{IMathLibDispatcherTrait, dispatcher as ekubo_math};
use ekubo::types::i129::i129;
use ekubo::types::keys::{PoolKey, PositionKey};
use clt_ekubo::types::pool_id::{PoolIdTrait};

// CLT-Ekubo Components
use clt_ekubo::components::constants::Constants;
use clt_ekubo::components::liquidity_shares::LiquidityShares;
use clt_ekubo::components::math::Math;
use clt_ekubo::components::util::serialize;
use clt_ekubo::components::user_positions::{
    IUserPositionsDispatcher, IUserPositionsDispatcherTrait,
};

// CLT-Ekubo Interfaces
use clt_ekubo::interfaces::clt_base::{
    ClaimFeeParams, DepositParams, ICLTBaseDispatcher, ICLTBaseDispatcherTrait, StrategyParams,
    UpdatePositionParams, WithdrawParams,
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
use crate::utils::erc20::{approve, balance_of, transfer};
use crate::utils::fixtures::{
    base_init, get_strategy_reserves, set_actions, token2, create_custom_actions,
};
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

    // start_cheat_caller_address(base.contract_address, owner());
    base.toggle_operator(exit_module.contract_address);
    // stop_cheat_caller_address(base.contract_address);

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

    let pool_key2 = get_ekubo_pool_key(
        token0.contract_address, token1.contract_address, multiextension, 1, //1%
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

    // let actions = set_actions(modules, extension);
    //create default strategy
    base
        .create_strategy(
            StrategyParams {
                pool_key: pool_key2,
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
    (base, pool_key2, actions2)
}

#[test]
#[fork("mainnet")]
fn test_simple_deposit() {
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
            PositionKey {
                salt: pool_key.to_id(), owner: base.contract_address, bounds: strategy.key.into(),
            },
        )
        .liquidity;

    assert_eq!(strategy.account.ekubo_liquidity, ekubo_share);

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

    //the amount left in ekubo
    let dust: u256 = 1;

    assert_eq!(
        balance_before0, balance_of(pool_key.token0, get_contract_address()) + ekubo_fee + dust,
    );
    assert_eq!(
        balance_before1, balance_of(pool_key.token0, get_contract_address()) + ekubo_fee + dust,
    );

    assert_eq!(balance_of(pool_key.token0, ekubo_core().contract_address), ekubo_fee + dust);
    assert_eq!(balance_of(pool_key.token1, ekubo_core().contract_address), ekubo_fee + dust);
}

#[test]
#[fork("mainnet")]
fn test_deposit_with_correct_shares() {
    let (base, pool_key, _) = setup();

    let deposit_amount: u256 = ether(1);

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
    assert_eq!(strategy.account.balance0, 0);
    assert_eq!(strategy.account.balance1, 0);
    assert_eq!(strategy.account.total_shares, deposit_amount);
    assert_eq!(strategy.account.ekubo_liquidity, 16667175004998608611507);

    let position = IUserPositionsDispatcher { contract_address: base.contract_address }
        .get_position(1);
    assert_eq!(position.liquidity_share, deposit_amount);

    let recipient_balance = ERC721ABIDispatcher { contract_address: base.contract_address }
        .balanceOf(get_contract_address());
    assert_eq!(recipient_balance, 1);

    assert_eq!(balance_of(pool_key.token0, ekubo_core().contract_address), deposit_amount);
    assert_eq!(balance_of(pool_key.token1, ekubo_core().contract_address), deposit_amount);
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('CLTBASE: invalid share',))]
fn test_deposit_revert_zero_amount() {
    let (base, pool_key, _) = setup();

    let deposit_amount: u256 = ether(0);

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
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('CLTBASE: invalid share',))]
fn test_deposit_revert_min_share() {
    let (base, pool_key, _) = setup();

    let deposit_amount: u256 = Constants::MIN_INITIAL_SHARES - 1;

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
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('ERC20: insufficient balance',))]
fn test_deposit_revert_insufficient_funds() {
    let (base, pool_key, _) = setup();

    let deposit_amount: u256 = ether(2);

    let user2 = contract_address_const::<1>();

    transfer(pool_key.token0, user2, ether(1));
    transfer(pool_key.token1, user2, ether(1));

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
}

#[test]
#[fork("mainnet")]
#[should_panic(expected: ('CLTBASE: not authorized',))]
fn test_deposit_revert_in_private_strategy() {
    let (base, modules, _) = base_init(0);
    let extension = deploy_mock_extension(1).contract_address;
    let (token0, token1) = token2();
    let pool_key = get_ekubo_pool_key(
        token0.contract_address, token1.contract_address, extension, 2, 200,
    );
    let actions = set_actions(modules, extension);

    let params = StrategyParams {
        pool_key,
        owner: get_contract_address(),
        actions,
        tick_lower: i129 { mag: 400, sign: false },
        tick_upper: i129 { mag: 600, sign: false },
        initial_tick: ekubo_math().sqrt_ratio_to_tick(SQRT_RATIO_1_1),
        management_fee: 0,
        performance_fee: 0,
        is_compound: false,
        is_private: true,
        vault0: Zero::zero(),
        vault1: Zero::zero(),
    };

    base.create_strategy(params);

    let deposit_amount: u256 = ether(1);

    start_cheat_caller_address_global(contract_address_const::<1>());

    approve(pool_key.token0, base.contract_address, deposit_amount);
    approve(pool_key.token1, base.contract_address, deposit_amount);

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

    stop_cheat_caller_address_global();
}

#[test]
#[fork("mainnet")]
fn test_deposit_multiple_users() {
    let (base, pool_key, _) = setup();

    let (user1, user2) = (contract_address_const::<1>(), contract_address_const::<2>());
    let deposit_amount = ether(5);

    transfer(pool_key.token0, user1, deposit_amount);
    transfer(pool_key.token1, user1, deposit_amount);

    transfer(pool_key.token0, user2, deposit_amount);
    transfer(pool_key.token1, user2, deposit_amount);

    start_cheat_caller_address(pool_key.token0, user1);
    approve(pool_key.token0, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token0);
    start_cheat_caller_address(pool_key.token1, user1);
    approve(pool_key.token1, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token1);

    start_cheat_caller_address(pool_key.token0, user2);
    approve(pool_key.token0, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token0);
    start_cheat_caller_address(pool_key.token1, user2);
    approve(pool_key.token1, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token1);

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

    let user1_position = base.positions(2);
    assert_eq!(user1_position.liquidity_share, deposit_amount);

    let (strategy, _) = base.strategies(pool_key.to_id());
    assert_eq!(strategy.account.total_shares, deposit_amount * 2);

    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);
    swap(pool_key, ether(1), false);
    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);
    swap(pool_key, ether(4), false);
    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);

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

    let user2_position = base.positions(3);

    let (strategy, _) = base.strategies(pool_key.to_id());
    assert_gt!(strategy.account.balance0, 0);
    assert_gt!(strategy.account.balance1, 0);
    assert_eq!(
        strategy.account.total_shares, (deposit_amount * 2) + user2_position.liquidity_share,
    );
}

#[test]
#[fork("mainnet")]
fn test_deposit_out_of_range_poc1() {
    let (base, modules, _) = base_init(0);
    let extension = deploy_mock_extension(1).contract_address;
    let (token0, token1) = token2();
    let pool_key = get_ekubo_pool_key(
        token0.contract_address, token1.contract_address, extension, 2, 200,
    );
    let actions = set_actions(modules, extension);

    let params = StrategyParams {
        pool_key,
        owner: get_contract_address(),
        actions,
        tick_lower: i129 { mag: 400, sign: false },
        tick_upper: i129 { mag: 600, sign: false },
        initial_tick: ekubo_math().sqrt_ratio_to_tick(SQRT_RATIO_1_1),
        management_fee: 0,
        performance_fee: 0,
        is_compound: false,
        is_private: false,
        vault0: Zero::zero(),
        vault1: Zero::zero(),
    };

    base.create_strategy(params);

    let deposit_amount: u256 = ether(5);

    approve(pool_key.token0, base.contract_address, Bounded::MAX);

    base
        .deposit(
            DepositParams {
                strategy_id: pool_key.to_id(),
                amount0_desired: deposit_amount,
                amount1_desired: 0,
                amount0_min: 0,
                amount1_min: 0,
                recipient: get_contract_address(),
            },
        );

    assert_eq!(balance_of(pool_key.token0, ekubo_core().contract_address), deposit_amount);
    assert_eq!(balance_of(pool_key.token1, ekubo_core().contract_address), 0);

    base
        .update_position_liquidity(
            UpdatePositionParams {
                token_id: 1,
                amount0_desired: deposit_amount,
                amount1_desired: 0,
                amount0_min: 0,
                amount1_min: 0,
            },
        );

    assert_eq!(balance_of(pool_key.token0, ekubo_core().contract_address), deposit_amount * 2);
    assert_eq!(balance_of(pool_key.token1, ekubo_core().contract_address), 0);
}

#[test]
#[fork("mainnet")]
fn test_deposit_out_of_range_poc2() {
    let (base, modules, _) = base_init(0);
    let extension = deploy_mock_extension(1).contract_address;
    let (token0, token1) = token2();
    let pool_key = get_ekubo_pool_key(
        token0.contract_address, token1.contract_address, extension, 2, 200,
    );
    let actions = set_actions(modules, extension);

    let params = StrategyParams {
        pool_key,
        owner: get_contract_address(),
        actions,
        tick_lower: i129 { mag: 400, sign: false },
        tick_upper: i129 { mag: 600, sign: false },
        initial_tick: ekubo_math().sqrt_ratio_to_tick(SQRT_RATIO_1_1),
        management_fee: 0,
        performance_fee: 0,
        is_compound: false,
        is_private: false,
        vault0: Zero::zero(),
        vault1: Zero::zero(),
    };

    base.create_strategy(params);

    let deposit_amount: u256 = ether(5);

    approve(pool_key.token0, base.contract_address, Bounded::MAX);

    base
        .deposit(
            DepositParams {
                strategy_id: pool_key.to_id(),
                amount0_desired: deposit_amount,
                amount1_desired: 0,
                amount0_min: 0,
                amount1_min: 0,
                recipient: get_contract_address(),
            },
        );

    assert_eq!(base.positions(1).liquidity_share, deposit_amount);

    base
        .deposit(
            DepositParams {
                strategy_id: pool_key.to_id(),
                amount0_desired: deposit_amount * 2,
                amount1_desired: 0,
                amount0_min: 0,
                amount1_min: 0,
                recipient: get_contract_address(),
            },
        );

    assert_eq!(base.positions(2).liquidity_share, deposit_amount * 2);
}

#[test]
#[fork("mainnet")]
fn test_deposit_out_of_range_poc3() {
    let (base, modules, _) = base_init(0);
    let extension = deploy_mock_extension(1).contract_address;
    let (token0, token1) = token2();
    let pool_key = get_ekubo_pool_key(
        token0.contract_address, token1.contract_address, extension, 2, 200,
    );
    let actions = set_actions(modules, extension);

    let params = StrategyParams {
        pool_key,
        owner: get_contract_address(),
        actions,
        tick_lower: i129 { mag: 400, sign: false },
        tick_upper: i129 { mag: 600, sign: false },
        initial_tick: ekubo_math().sqrt_ratio_to_tick(SQRT_RATIO_1_1),
        management_fee: 0,
        performance_fee: 0,
        is_compound: false,
        is_private: false,
        vault0: Zero::zero(),
        vault1: Zero::zero(),
    };

    base.create_strategy(params);

    let deposit_amount: u256 = ether(5);

    approve(pool_key.token1, base.contract_address, Bounded::MAX);

    base
        .deposit(
            DepositParams {
                strategy_id: pool_key.to_id(),
                amount0_desired: 0,
                amount1_desired: deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
                recipient: get_contract_address(),
            },
        );

    assert_eq!(base.positions(1).liquidity_share, deposit_amount);

    base
        .deposit(
            DepositParams {
                strategy_id: pool_key.to_id(),
                amount0_desired: 0,
                amount1_desired: deposit_amount * 2,
                amount0_min: 0,
                amount1_min: 0,
                recipient: get_contract_address(),
            },
        );

    assert_eq!(base.positions(2).liquidity_share, deposit_amount * 2);
}

#[test]
#[fork("mainnet")]
fn test_deposit_poc_scenario() {
    let (base, pool_key, actions) = setup();
    let (user1, user2) = (contract_address_const::<1>(), contract_address_const::<2>());

    let deposit_amount = ether(10);

    transfer(pool_key.token0, user1, deposit_amount);
    transfer(pool_key.token1, user1, deposit_amount);

    transfer(pool_key.token0, user2, deposit_amount);
    transfer(pool_key.token1, user2, deposit_amount);

    start_cheat_caller_address(pool_key.token0, user1);
    approve(pool_key.token0, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token0);
    start_cheat_caller_address(pool_key.token1, user1);
    approve(pool_key.token1, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token1);

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

    let pool_key2 = get_ekubo_pool_key(pool_key.token0, pool_key.token1, Zero::zero(), 2, 200);
    base
        .create_strategy(
            StrategyParams {
                pool_key: pool_key2,
                owner: get_contract_address(),
                actions,
                tick_lower: i129 { mag: 200, sign: true },
                tick_upper: i129 { mag: 200, sign: false },
                initial_tick: ekubo_math().sqrt_ratio_to_tick(SQRT_RATIO_1_1),
                management_fee: 0,
                performance_fee: 0,
                is_compound: false,
                is_private: false,
                vault0: Zero::zero(),
                vault1: Zero::zero(),
            },
        );

    cheat_caller_address(base.contract_address, user2, CheatSpan::TargetCalls(1));
    base
        .deposit(
            DepositParams {
                strategy_id: pool_key2.to_id(),
                amount0_desired: deposit_amount,
                amount1_desired: deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
                recipient: user2,
            },
        );

    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);
    swap(pool_key, ether(2), true);
    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);
    swap(pool_key2, ether(2), true);
    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);

    let (_, s1_fee0, s1_fee1) = base.get_strategy_reserves(pool_key.to_id(), true);
    let (_, s2_fee0, s2_fee1) = base.get_strategy_reserves(pool_key2.to_id(), true);

    println!("s2_fee0: {}", s2_fee0);
    println!("s2_fee1: {}", s2_fee1);
    println!("s1_fee0: {}", s1_fee0);
    println!("s1_fee1: {}", s1_fee1);
    cheat_caller_address(base.contract_address, user2, CheatSpan::TargetCalls(1));
    base.claim_position_fee(ClaimFeeParams { recipient: user2, token_id: 2 });
    assert_eq!(balance_of(pool_key2.token0, user2), s2_fee0 - 1);

    let (_, s1_fee0, s1_fee1) = base.get_strategy_reserves(pool_key.to_id(), true);
    let (_, s2_fee0, s2_fee1) = base.get_strategy_reserves(pool_key2.to_id(), true);
}

#[test]
#[fork("mainnet")]
fn test_deposit_multipleUsers_non_compound() {
    let (base, pool_key, actions) = setup();
    let (user2, user3) = (contract_address_const::<1>(), contract_address_const::<2>());

    let deposit_amount = ether(10);

    transfer(pool_key.token0, user2, deposit_amount);
    transfer(pool_key.token1, user2, deposit_amount);

    transfer(pool_key.token0, user3, deposit_amount);
    transfer(pool_key.token1, user3, deposit_amount);

    start_cheat_caller_address(pool_key.token0, user2);
    approve(pool_key.token0, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token0);
    start_cheat_caller_address(pool_key.token1, user2);
    approve(pool_key.token1, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token1);

    start_cheat_caller_address(pool_key.token0, user3);
    approve(pool_key.token0, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token0);
    start_cheat_caller_address(pool_key.token1, user3);
    approve(pool_key.token1, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token1);

    let pool_key2 = get_ekubo_pool_key(pool_key.token0, pool_key.token1, Zero::zero(), 1, 200);
    base
        .create_strategy(
            StrategyParams {
                pool_key: pool_key2,
                owner: get_contract_address(),
                actions,
                tick_lower: i129 { mag: 200, sign: true },
                tick_upper: i129 { mag: 200, sign: false },
                initial_tick: ekubo_math().sqrt_ratio_to_tick(SQRT_RATIO_1_1),
                management_fee: 0,
                performance_fee: 0,
                is_compound: false,
                is_private: false,
                vault0: Zero::zero(),
                vault1: Zero::zero(),
            },
        );

    let strategy_id = pool_key2.to_id();

    base
        .deposit(
            DepositParams {
                strategy_id,
                amount0_desired: deposit_amount,
                amount1_desired: deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
                recipient: get_contract_address() //user1
            },
        );

    let user_share1 = base.positions(1).liquidity_share;
    let (strategy, _) = base.strategies(strategy_id);
    let (liquidity_user1, _, _) = LiquidityShares::calculate_share(
        deposit_amount, deposit_amount, 0, 0, 0,
    );
    assert_eq!(user_share1, liquidity_user1);
    assert_eq!(strategy.account.total_shares, liquidity_user1);

    cheat_caller_address(base.contract_address, user2, CheatSpan::TargetCalls(1));
    base
        .deposit(
            DepositParams {
                strategy_id,
                amount0_desired: deposit_amount,
                amount1_desired: deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
                recipient: user2,
            },
        );

    let user_share2 = base.positions(2).liquidity_share;
    let (strategy, _) = base.strategies(strategy_id);
    assert_eq!(user_share2, deposit_amount);
    assert_eq!(strategy.account.total_shares, deposit_amount * 2);

    assert_eq!(strategy.account.balance0, 0);
    assert_eq!(strategy.account.balance1, 0);

    swap(pool_key2, ether(2), true);
    swap(pool_key2, ether(2), false);

    let (strategy, _) = base.strategies(strategy_id);
    let (reserve0, reserve1) = get_strategy_reserves(
        pool_key2, strategy.key, strategy.account.ekubo_liquidity,
    );
    let (liquidity_user3, _, _) = LiquidityShares::calculate_share(
        deposit_amount, deposit_amount, reserve0, reserve1, strategy.account.total_shares,
    );

    cheat_caller_address(base.contract_address, user3, CheatSpan::TargetCalls(1));
    base
        .deposit(
            DepositParams {
                strategy_id,
                amount0_desired: deposit_amount,
                amount1_desired: deposit_amount,
                amount0_min: 0,
                amount1_min: 0,
                recipient: user3,
            },
        );

    let user_share3 = base.positions(3).liquidity_share;
    let (strategy, _) = base.strategies(strategy_id);
    assert_eq!(user_share3, liquidity_user3);
    assert_eq!(strategy.account.total_shares, (liquidity_user1 * 2) + liquidity_user3);
}

#[test]
#[fork("mainnet")]
fn test_deposit_succeeds_with_correct_fee_growth() {
    let (base, pool_key, actions) = setup();

    let deposit_amount = ether(4);
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

    let params = DepositParams {
        strategy_id: pool_key.to_id(),
        amount0_desired: deposit_amount,
        amount1_desired: deposit_amount,
        amount0_min: 0,
        amount1_min: 0,
        recipient: get_contract_address(),
    };

    base.deposit(params);

    swap(pool_key, ether(2), false);
    swap(pool_key, ether(2), true);

    let (_, total_fee0, total_fee1) = base.get_strategy_reserves(pool_key.to_id(), true);

    base.deposit(params);

    let position = base.positions(2);
    assert_eq!(
        position.fee_growth_inside_0_last_X128,
        Math::mul_div(total_fee0, Constants::Q128, deposit_amount),
    );
    assert_eq!(
        position.fee_growth_inside_1_last_X128,
        Math::mul_div(total_fee1, Constants::Q128, deposit_amount),
    );
}


#[test]
#[fork("mainnet")]
fn test_deposit_succeeds_artialDepositToken0() {
    let (base, pool_key, actions) = setup();
    let strategy_id = pool_key.to_id();
    let deposit_amount = ether(10);

    let (strategy, _) = base.strategies(strategy_id);
}


#[test]
#[fork("mainnet")]
fn test_compound_strategy_fee_reinvestment() {
    let (base, pool_key, _) = setup();
    let (user1, user2) = (contract_address_const::<1>(), contract_address_const::<2>());

    let deposit_amount = ether(20);

    transfer(pool_key.token0, user1, deposit_amount);
    transfer(pool_key.token1, user1, deposit_amount);

    transfer(pool_key.token0, user2, deposit_amount);
    transfer(pool_key.token1, user2, deposit_amount);

    start_cheat_caller_address(pool_key.token0, user1);
    approve(pool_key.token0, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token0);
    start_cheat_caller_address(pool_key.token1, user1);
    approve(pool_key.token1, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token1);

    start_cheat_caller_address(pool_key.token0, user2);
    approve(pool_key.token0, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token0);
    start_cheat_caller_address(pool_key.token1, user2);
    approve(pool_key.token1, base.contract_address, deposit_amount);
    stop_cheat_caller_address(pool_key.token1);

    // Initial deposit
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

    let (strategy, _) = base.strategies(pool_key.to_id());

    let ekubo_liquidity_before_compound = strategy.account.ekubo_liquidity;
    println!("ekubo_liquidity_before_compound: {}", ekubo_liquidity_before_compound);

    // Generate fees through multiple swaps
    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);
    swap(pool_key, ether(1), true);
    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);
    swap(pool_key, ether(1), false);
    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);

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

    // Check that fees were reinvested
    let (strategy, _) = base.strategies(pool_key.to_id());
    let ekubo_liquidity_after_compound = strategy.account.ekubo_liquidity;
    println!("ekubo_liquidity_after_compound: {}", ekubo_liquidity_after_compound);

    assert_gt!(ekubo_liquidity_after_compound, ekubo_liquidity_before_compound);
}
