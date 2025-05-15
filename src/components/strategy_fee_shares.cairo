pub mod StrategyFeeShares {
    use starknet::storage::{
        StoragePointerReadAccess, StoragePointerWriteAccess, StoragePath, Mutable,
    };

    use clt_ekubo::components::constants::Constants::Q128;
    use clt_ekubo::components::math::Math;
    use clt_ekubo::interfaces::clt_base::StrategyData;

    pub fn update_strategy_fees(
        strategy_storage: StoragePath<Mutable<StrategyData>>, fee0: u256, fee1: u256,
    ) -> StrategyData {
        let mut strategy = strategy_storage.read();
        if strategy.account.total_shares > 0 {
            strategy.account.fee0 += fee0;
            strategy.account.fee1 += fee1;

            strategy
                .account
                .fee_growth_inside_0_last_X128 +=
                    Math::mul_div(fee0, Q128, strategy.account.total_shares);
            strategy
                .account
                .fee_growth_inside_1_last_X128 +=
                    Math::mul_div(fee1, Q128, strategy.account.total_shares);

            strategy_storage.write(strategy);
        }

        strategy
    }
}
