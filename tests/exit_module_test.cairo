use core::num::traits::{Bounded, Zero};
use snforge_std::{declare, DeclareResultTrait, start_cheat_block_timestamp_global};
use starknet::{get_contract_address, get_block_timestamp};
use ekubo::interfaces::mathlib::{dispatcher as ekubo_math, IMathLibDispatcherTrait};
use ekubo::types::i129::i129;
use ekubo::types::keys::PoolKey;

use clt_ekubo::components::util::serialize;
use clt_ekubo::extensions::multiextension::interfaces::multiextension_deployer::IMultiextensionDeployerDispatcherTrait;
use clt_ekubo::extensions::multiextension::utils::activate_extension::{
    generate_extension_data, ExtStruct, ExtMethodStruct,
};
use clt_ekubo::extensions::multiextension::utils::bit_math::ExtensionMethod;
use clt_ekubo::interfaces::clt_base::{
    ICLTBaseDispatcher, ICLTBaseDispatcherTrait, StrategyParams, DepositParams, WithdrawParams,
};
use clt_ekubo::interfaces::clt_twap_quoter::{ICLTTwapQuoterDispatcher};
use clt_ekubo::extensions::oracle::interfaces::oracle::{IOracleDispatcher};

use clt_ekubo::interfaces::clt_modules::StrategyPayload;
use clt_ekubo::types::pool_id::PoolIdTrait;


use crate::utils::deploy::{
    deploy_oracle, deploy_twap_quoter, deploy_exit_module, deploy_multiextension_deployer,
};
use crate::utils::ekubo::{ekubo_core, get_ekubo_pool_key, swap};
use crate::utils::erc20::approve;
use crate::utils::fixtures::{token2, base_init, create_custom_actions};
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

    //exit module extension
    let exit_module = deploy_exit_module(base, ekubo_core(), twap_quoter);

    base.toggle_operator(exit_module.contract_address);

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

    //ekubo pool key with multiextension set as an extension
    let pool_key = get_ekubo_pool_key(
        token0.contract_address, token1.contract_address, multiextension, 1, //1%
        60,
    );

    //create intent
    let actions = create_custom_actions(
        modules,
        exit_module.contract_address,
        StrategyPayload {
            intent: hash_intent('EXIT_STRATEGY'),
            action_name: hash_intent('EXIT_AND_HOLD'),
            data: serialize::<
                (u32, i129, i129),
            >(@(3600, i129 { mag: 20, sign: true }, i129 { mag: 20, sign: false }))
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
                tick_lower: i129 { mag: 120, sign: true },
                tick_upper: i129 { mag: 120, sign: false },
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
fn test_exit_and_hold() {
    let (base, pool_key, _, _, _) = setup();
    let deposit_amount = ether(4);
    // Deposit into the strategy
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
    assert_eq!(strategy.account.ekubo_liquidity, 66668700019994434446028);

    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);
    swap(pool_key, ether(1), true);
    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);
    swap(pool_key, ether(1), false);
    start_cheat_block_timestamp_global(get_block_timestamp() + 3600);

    let (strategy, _) = base.strategies(pool_key.to_id());

    assert_eq!(strategy.account.balance0 > 0, true);
    assert_eq!(strategy.account.balance1 > 0, true);
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

    let (strategy, _) = base.strategies(pool_key.to_id());

    assert_eq!(strategy.account.balance0 == 0, true);
    assert_eq!(strategy.account.balance1 == 0, true);
}
