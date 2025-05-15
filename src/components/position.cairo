pub mod Position {
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, StoragePath, Mutable,
    };

    use clt_ekubo::components::constants::Constants;
    use clt_ekubo::components::math::Math;
    use clt_ekubo::components::util::deserialize;
    use clt_ekubo::interfaces::clt_base::{StrategyData, StrategyKey};

    pub fn update(
        strategy_storage: StoragePath<Mutable<StrategyData>>,
        liquidity_added: u128,
        share: u256,
        amount0_desired: u256,
        amount1_desired: u256,
        amount0_added: u256,
        amount1_added: u256,
    ) -> StrategyData {
        let mut strategy = strategy_storage.read();

        let balance0 = amount0_desired - amount0_added;
        let balance1 = amount1_desired - amount1_added;

        if (balance0 > 0 || balance1 > 0) {
            strategy.account.balance0 += balance0;
            strategy.account.balance1 += balance1;
        }

        if (share > 0) {
            strategy.account.total_shares += share;
            strategy.account.ekubo_liquidity += liquidity_added;
        }

        strategy_storage.write(strategy);
        strategy
    }

    pub fn update_for_compound(
        strategy_storage: StoragePath<Mutable<StrategyData>>,
        liquidity_added: u128,
        amount0_added: u256,
        amount1_added: u256,
    ) -> StrategyData {
        let mut strategy = strategy_storage.read();
        strategy.account.balance0 = amount0_added;
        strategy.account.balance1 = amount1_added;

        strategy.account.fee0 = 0;
        strategy.account.fee1 = 0;

        strategy.account.ekubo_liquidity += liquidity_added;
        strategy_storage.write(strategy);
        strategy
    }

    pub fn reset_saved_amounts(strategy_storage: StoragePath<Mutable<StrategyData>>) {
        let mut strategy = strategy_storage.read();
        strategy.account.last_saved_amount0 = 0;
        strategy.account.last_saved_amount1 = 0;
        strategy.account.is_holding_saved = false;
        strategy_storage.write(strategy);
    }

    pub fn update_strategy(
        strategy_storage: StoragePath<Mutable<StrategyData>>,
        key: StrategyKey,
        liquidity: u128,
        balance0: u256,
        balance1: u256,
        automation_fee_owed0: u256,
        automation_fee_owed1: u256,
        amount0_saved: u128,
        amount1_saved: u128,
        fee0_saved: u256,
        fee1_saved: u256,
        is_holding_saved: bool,
    ) {
        let mut strategy = strategy_storage.read();
        strategy.key = key;

        strategy.account.balance0 = balance0;
        strategy.account.balance1 = balance1;
        strategy.account.ekubo_liquidity = liquidity;

        if (strategy.is_compound) {
            strategy.account.fee0 = 0;
            strategy.account.fee1 = 0;
        }

        if automation_fee_owed0 > 0 {
            strategy.account.automation_fee_owed0 = automation_fee_owed0;
        }

        if automation_fee_owed1 > 0 {
            strategy.account.automation_fee_owed1 = automation_fee_owed1;
        }

        strategy.account.last_saved_amount0 = amount0_saved;
        strategy.account.last_saved_amount1 = amount1_saved;
        strategy.account.is_holding_saved = is_holding_saved;

        strategy_storage.write(strategy);
    }

    pub fn get_hodl_status(data: Span<felt252>) -> bool {
        if data.len() > 0 {
            return deserialize::<bool>(data);
        }
        false
    }

    pub fn get_partial_amount_status(data: Span<felt252>) -> bool {
        if data.len() > 0 {
            let (is_allowed, _, _) = deserialize::<(bool, u256, u256)>(data);
            return is_allowed;
        }
        false
    }

    pub fn update_partial_deposit_balance(
        strategy_storage: StoragePath<Mutable<StrategyData>>,
        data: Span<felt252>,
        amount0: u256,
        amount1: u256,
    ) -> (u256, u256, StrategyData) {
        let mut strategy = strategy_storage.read();
        let (_, percentage0, percentage1) = deserialize::<(bool, u256, u256)>(data);

        let partial_amount0 = Math::mul_div(amount0, percentage0, Constants::WAD);
        let partial_amount1 = Math::mul_div(amount1, percentage1, Constants::WAD);

        if partial_amount0 > 0 {
            strategy.account.balance0 += amount0 - partial_amount0;
        }

        if partial_amount1 > 0 {
            strategy.account.balance1 += amount1 - partial_amount1;
        }

        strategy_storage.write(strategy);

        (percentage0, percentage1, strategy)
    }
}
