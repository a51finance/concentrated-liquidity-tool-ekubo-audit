use snforge_std::ContractClassTrait;
use ekubo::interfaces::core::ICoreDispatcherTrait;
use core::num::traits::{Bounded, Zero};

use snforge_std::{declare, DeclareResultTrait, start_cheat_block_timestamp_global};
use starknet::{get_contract_address, get_block_timestamp};

use ekubo::interfaces::mathlib::{dispatcher as ekubo_math, IMathLibDispatcherTrait};
use ekubo::types::i129::i129;
use openzeppelin::token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
use clt_ekubo::components::util::{serialize};

use clt_ekubo::extensions::multiextension::interfaces::multiextension_deployer::IMultiextensionDeployerDispatcherTrait;
use clt_ekubo::extensions::multiextension::utils::activate_extension::{
    generate_extension_data, ExtStruct, ExtMethodStruct,
};
use clt_ekubo::extensions::multiextension::utils::bit_math::ExtensionMethod;
use clt_ekubo::interfaces::clt_base::{
    ICLTBaseDispatcher, ICLTBaseDispatcherTrait, StrategyParams, DepositParams, SwapOrderParams,
    ShiftLiquidityParams, WithdrawParams,
};
use clt_ekubo::interfaces::clt_twap_quoter::{ICLTTwapQuoterDispatcher};
use clt_ekubo::extensions::oracle::interfaces::oracle::{IOracleDispatcher};
use ekubo::types::keys::{PoolKey, PositionKey};
use clt_ekubo::components::constants::Constants;


use clt_ekubo::interfaces::clt_modules::StrategyPayload;
use clt_ekubo::types::pool_id::PoolIdTrait;


use crate::utils::deploy::{
    deploy_oracle, deploy_twap_quoter, deploy_rebase_module, deploy_multiextension_deployer,
};
use crate::utils::ekubo::{ekubo_core, get_ekubo_pool_key, swap};
use crate::utils::erc20::{approve, balance_of};
use crate::utils::fixtures::{token2, base_init, create_custom_actions, get_strategy_reserves};
use crate::utils::helpers::{ether, hash_intent, SQRT_RATIO_1_1};


fn setup() -> (
    ICLTBaseDispatcher, PoolKey, ICLTTwapQuoterDispatcher, Span<felt252>, IOracleDispatcher,
) {
    //init base and modules
    let (base, modules, _) = base_init(0);

    //two mock erc20 tokens
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

    //rebase module extension
    let rebase_module = deploy_rebase_module(base, ekubo_core(), twap_quoter);

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
                extension: rebase_module.contract_address,
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

    //ekubo pool key with multiextension set as an extension
    let pool_key = get_ekubo_pool_key(
        token0.contract_address, token1.contract_address, multiextension, 1, //1%
        60,
    );

    //create intent
    let actions = create_custom_actions(
        modules,
        rebase_module.contract_address,
        StrategyPayload {
            intent: hash_intent('REBASE_STRATEGY'),
            action_name: hash_intent('ACTIVE_REBALANCE'),
            data: serialize::<
                (u32, i129, i129, i129, i129, i129),
            >(
                @(
                    3600,
                    i129 { mag: 50, sign: false },
                    i129 { mag: 50, sign: false },
                    i129 { mag: 0, sign: true },
                    i129 { mag: 60, sign: true },
                    i129 { mag: 60, sign: false },
                ),
            )
                .span(),
        },
    );

    //create default strategy
    base
        .create_strategy(
            StrategyParams {
                pool_key,
                owner: get_contract_address(),
                actions,
                tick_lower: i129 { mag: 60, sign: true },
                tick_upper: i129 { mag: 60, sign: false },
                initial_tick: ekubo_math().sqrt_ratio_to_tick(SQRT_RATIO_1_1),
                management_fee: 10000000000000000,
                performance_fee: 10000000000000000,
                is_compound: false,
                is_private: false,
                vault0: Zero::zero(),
                vault1: Zero::zero(),
            },
        );

    //approve both tokens
    approve(token0.contract_address, base.contract_address, Bounded::MAX);
    approve(token1.contract_address, base.contract_address, Bounded::MAX);

    (base, pool_key, twap_quoter, actions, oracle_extension)
}


#[test]
#[fork("mainnet")]
fn test_simple_deposit() {
    let (base, pool_key, _, _, _) = setup();

    let mock_exchange_class = declare("MockExchange").unwrap().contract_class();
    let (mock_exchange_address, _) = mock_exchange_class.deploy(@array![]).unwrap();

    let (balance_before0, balance_before1) = (
        balance_of(pool_key.token0, get_contract_address()),
        balance_of(pool_key.token1, get_contract_address()),
    );

    let deposit_amount = ether(5);

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

    let balance_before0 = strategy.account.balance0;
    let balance_before1 = strategy.account.balance1;

    assert_eq!(balance_before0, 0);
    assert_eq!(balance_before1, 0);

    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);
    swap(pool_key, ether(1), true);
    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);

    swap(pool_key, ether(1), false);
    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);

    // Swapping tokens (Which will be done by the bot)
    let (strategy, _) = base.strategies(pool_key.to_id());
    let order_data = base
        .orders(3176453472216532674590368553792389600886457708763093679974738718070362524082);
    let order_data_module_status = base
        .order_module_status(
            3176453472216532674590368553792389600886457708763093679974738718070362524082,
        );
    let mut src_token: felt252 = 0;
    let mut dst_token: felt252 = 0;
    let mut recipient: felt252 = 0;
    let mut swap_amount: felt252 = 0;

    if order_data.zero_for_one {
        src_token = order_data.pool_key.token0.into();
        dst_token = order_data.pool_key.token1.into();
    } else {
        src_token = order_data.pool_key.token1.into();
        dst_token = order_data.pool_key.token0.into();
    };

    let funding_amount = ether(10);
    let src_token_dispatcher = ERC20ABIDispatcher {
        contract_address: src_token.try_into().unwrap(),
    };
    src_token_dispatcher.transfer(mock_exchange_address, funding_amount);

    let dst_token_dispatcher = ERC20ABIDispatcher {
        contract_address: dst_token.try_into().unwrap(),
    };
    dst_token_dispatcher.transfer(mock_exchange_address, funding_amount);

    let mut call_data_values = array![];
    recipient = get_contract_address().into();
    swap_amount = order_data.swap_amount.try_into().unwrap();

    let amount_in_u256: u256 = order_data.swap_amount;
    let amount_out_u256: u256 = if amount_in_u256 > 0_u256 {
        amount_in_u256
    } else {
        0_u256
    };

    call_data_values.append(src_token);
    call_data_values.append(dst_token);
    call_data_values.append(amount_in_u256.low.into());
    call_data_values.append(amount_in_u256.high.into());
    call_data_values.append(recipient.into());
    call_data_values.append(amount_out_u256.low.into());
    call_data_values.append(amount_out_u256.high.into());

    let swap_data_span = call_data_values.span();
    base
        .shift_liquidity(
            ShiftLiquidityParams {
                is_manager_locked: true,
                exchange_address: mock_exchange_address,
                order: SwapOrderParams {
                    key: strategy.key,
                    pool_key: strategy.pool_key.into(),
                    should_mint: true,
                    zero_for_one: order_data.zero_for_one,
                    swap_amount: order_data.swap_amount,
                    min_amount: order_data.min_amount,
                    deadline: order_data.deadline,
                    action_name: Constants::ACTIVE_REBALANCE,
                    module_status: order_data_module_status,
                },
                swap_data: swap_data_span.into(),
                swap_selector: selector!("swap_exact_tokens_to"),
            },
        );
}

#[test]
#[fork("mainnet")]
fn test_withdraw_with_automation_fee() {
    let (base, pool_key, _, _, _) = setup();

    let mock_exchange_class = declare("MockExchange").unwrap().contract_class();
    let (mock_exchange_address, _) = mock_exchange_class.deploy(@array![]).unwrap();

    let (balance_before0, balance_before1) = (
        balance_of(pool_key.token0, get_contract_address()),
        balance_of(pool_key.token1, get_contract_address()),
    );

    let deposit_amount = ether(5);

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

    let balance_before0 = strategy.account.balance0;
    let balance_before1 = strategy.account.balance1;

    assert_eq!(balance_before0, 0);
    assert_eq!(balance_before1, 0);

    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);
    swap(pool_key, ether(1), true);
    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);

    swap(pool_key, ether(1), true);
    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);

    // Swapping tokens (Which will be done by the bot)
    let (strategy, _) = base.strategies(pool_key.to_id());
    let order_data = base
        .orders(2013957557109430788375208643764093596270139048790813959234409733532618074945);
    let order_data_module_status = base
        .order_module_status(
            2013957557109430788375208643764093596270139048790813959234409733532618074945,
        );
    let mut src_token: felt252 = 0;
    let mut dst_token: felt252 = 0;
    let mut recipient: felt252 = 0;
    let mut swap_amount: felt252 = 0;

    if order_data.zero_for_one {
        src_token = order_data.pool_key.token0.into();
        dst_token = order_data.pool_key.token1.into();
    } else {
        src_token = order_data.pool_key.token1.into();
        dst_token = order_data.pool_key.token0.into();
    };

    let funding_amount = ether(10);
    let src_token_dispatcher = ERC20ABIDispatcher {
        contract_address: src_token.try_into().unwrap(),
    };
    src_token_dispatcher.transfer(mock_exchange_address, funding_amount);

    let dst_token_dispatcher = ERC20ABIDispatcher {
        contract_address: dst_token.try_into().unwrap(),
    };
    dst_token_dispatcher.transfer(mock_exchange_address, funding_amount);

    let mut call_data_values = array![];
    recipient = base.contract_address.into();
    swap_amount = order_data.swap_amount.try_into().unwrap();
    let amount_in_u256: u256 = order_data.swap_amount;
    let amount_out_u256: u256 = if amount_in_u256 > 0_u256 {
        amount_in_u256
    } else {
        0_u256
    };

    call_data_values.append(src_token);
    call_data_values.append(dst_token);
    call_data_values.append(amount_in_u256.low.into());
    call_data_values.append(amount_in_u256.high.into());
    call_data_values.append(recipient.into());
    call_data_values.append(amount_out_u256.low.into());
    call_data_values.append(amount_out_u256.high.into());

    let swap_data_span = call_data_values.span();

    base
        .shift_liquidity(
            ShiftLiquidityParams {
                is_manager_locked: true,
                exchange_address: mock_exchange_address,
                order: SwapOrderParams {
                    key: strategy.key,
                    pool_key: strategy.pool_key.into(),
                    should_mint: true,
                    zero_for_one: order_data.zero_for_one,
                    swap_amount: order_data.swap_amount,
                    min_amount: order_data.min_amount,
                    deadline: order_data.deadline,
                    action_name: Constants::REBASE_STRATEGY,
                    module_status: order_data_module_status,
                },
                swap_data: swap_data_span.into(),
                swap_selector: selector!("swap_exact_tokens_to"),
            },
        );

    let (_strategy, _) = base.strategies(pool_key.to_id());

    let position = base.positions(1);
    base
        .withdraw(
            WithdrawParams {
                token_id: 1,
                liquidity: position.liquidity_share,
                amount0_min: 0,
                amount1_min: 0,
                recipient: get_contract_address(),
            },
        );
}

