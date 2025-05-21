pub mod VaultActions {
    use starknet::{ContractAddress, get_contract_address};


    use ekubo::interfaces::core::{ICoreDispatcher};

    use clt_ekubo::types::pool_id::{PoolId};
    use clt_ekubo::interfaces::clt_base::{StrategyData};
    use clt_ekubo::interfaces::erc_4626::{IERC4626Dispatcher, IERC4626DispatcherTrait};


    pub fn deposit_to_vault(
        strategy: StrategyData,
        core: ICoreDispatcher,
        pool_id: PoolId,
        allowed0: bool,
        allowed1: bool,
    ) {}

    pub fn withdraw_from_vault(
        strategy: StrategyData,
        core: ICoreDispatcher,
        pool_id: PoolId,
        allowed0: bool,
        allowed1: bool,
    ) {}


    pub fn partial_withdraw(strategy: StrategyData, recipient: ContractAddress, liquidity: u256) {}

    pub fn vault_deposit(
        vault: IERC4626Dispatcher, pool_id: PoolId, token_address: ContractAddress, assets: u256,
    ) {}

    pub fn vault_withdraw(
        vault: IERC4626Dispatcher,
        pool_id: PoolId,
        token_address: ContractAddress,
        recipient: ContractAddress,
        assets: u256,
    ) {
        vault.withdraw(assets, recipient, get_contract_address());
    }
}
