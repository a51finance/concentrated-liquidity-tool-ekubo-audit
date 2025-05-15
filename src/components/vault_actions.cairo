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


    pub fn partial_withdraw(
        strategy: StrategyData, recipient: ContractAddress, liquidity: u256,
    ) { // let vault0 = IERC4626Dispatcher { contract_address: strategy.vault0 };
    // let shares0 = Math::mul_div(
    //     vault0.total_assets(), liquidity, strategy.account.total_shares,
    // );

    // if shares0 > 0 {
    //     let pool_id: PoolKey = strategy.pool_key.into();
    //     return vault_withdraw(vault0, pool_id, strategy.pool_key.token0, recipient, shares0);
    // } else {
    //     0
    // }

    // let vault1 = IERC4626Dispatcher { contract_address: strategy.vault1 };
    // let assets1 = Math::mul_div(
    //     vault1.total_assets(), liquidity, strategy.account.total_shares,
    // );

    // if assets1 > 0 {
    //     let shares = vault1.withdraw(assets1, get_contract_address(), recipient);
    //     return shares;
    // }
    // 0
    }

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
