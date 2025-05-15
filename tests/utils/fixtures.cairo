use starknet::{ContractAddress, get_contract_address};
use ekubo::interfaces::core::ICoreDispatcherTrait;
use ekubo::types::keys::PoolKey;
use openzeppelin::token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

use clt_ekubo::components::liquidity_amounts::LiquidityAmounts;
use clt_ekubo::components::util::serialize;
use clt_ekubo::interfaces::clt_base::{ICLTBaseDispatcher, StrategyKey};
use clt_ekubo::interfaces::clt_modules::{
    ICLTModulesDispatcher, ICLTModulesDispatcherTrait, StrategyPayload,
};

use clt_ekubo::interfaces::governance_fee_handler::ProtocolFeeRegistry;

use clt_ekubo::interfaces::erc_4626::IERC4626Dispatcher;
use ekubo::types::i129::i129;
use clt_ekubo::types::base_init::BaseInitParams;
use crate::utils::deploy::{
    deploy_mock_token, deploy_clt_modules, deploy_fee_handler, deploy_clt_base, deploy_mock_vault,
};
use crate::utils::helpers::{hash_intent};

use crate::utils::ekubo::{ekubo_core};


pub fn set_actions(modules: ICLTModulesDispatcher, extension: ContractAddress) -> Span<felt252> {
    create_custom_actions(
        modules,
        extension,
        StrategyPayload {
            intent: hash_intent('MY INTENT'),
            action_name: hash_intent('ACTION ONE'),
            data: serialize::<(u8, u8)>(@(5, 4)).span(),
        },
    )
}

pub fn create_custom_actions(
    modules: ICLTModulesDispatcher, extension: ContractAddress, payload: StrategyPayload,
) -> Span<felt252> {
    let action_data: (u256, Array<StrategyPayload>) = (1, array![payload]);
    let serialized_action_data: Span<felt252> = serialize::<
        (u256, Array<StrategyPayload>),
    >(@action_data)
        .span();

    modules.set_intent(payload.intent);
    modules.set_intent_address(payload.intent, extension);
    modules.set_intent_action(payload.intent, payload.action_name);
    serialized_action_data
}

pub fn token2() -> (ERC20ABIDispatcher, ERC20ABIDispatcher) {
    (
        deploy_mock_token("TokenA", "TA", get_contract_address()),
        deploy_mock_token("TokenA", "TA", get_contract_address()),
    )
}

pub fn base_init(fee: u256) -> (ICLTBaseDispatcher, ICLTModulesDispatcher, ERC20ABIDispatcher) {
    let owner = get_contract_address();

    let clt_modules = deploy_clt_modules(owner);
    let eth = deploy_mock_token("Ethereum", "Eth", owner);

    let fee_registry = ProtocolFeeRegistry { lp_automation_fee: 1000, strategy_creation_fee: fee };
    let fee_handler = deploy_fee_handler(owner, fee_registry, fee_registry);

    let clt_base = deploy_clt_base(
        BaseInitParams {
            owner,
            name: "A51",
            symbol: "A51",
            core: ekubo_core(),
            clt_modules,
            fee_handler,
            eth: eth.contract_address,
        },
    );

    (clt_base, clt_modules, eth)
}

pub fn vault2() -> (IERC4626Dispatcher, IERC4626Dispatcher) {
    let (token0, token1) = token2();
    let vault0 = deploy_mock_vault(token0.contract_address, "VaultA", "VA");
    let vault1 = deploy_mock_vault(token1.contract_address, "VaultB", "VB");
    (vault0, vault1)
}

pub fn get_strategy_reserves(
    pool_key: PoolKey, key: StrategyKey, liquidity_desired: u128,
) -> (u256, u256) {
    let sqrt_ratio = ekubo_core().get_pool_price(pool_key).sqrt_ratio;
    if liquidity_desired > 0 {
        return LiquidityAmounts::get_amounts_for_liquidity(
            sqrt_ratio, key.into(), liquidity_desired,
        );
    }
    (0, 0)
}

pub fn get_pool_current_tick(pool_key: PoolKey) -> i129 {
    ekubo_core().get_pool_price(pool_key).tick
}
