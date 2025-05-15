pub mod LiquidityShares {
    use core::num::traits::Zero;
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};

    use starknet::{get_contract_address};

    use clt_ekubo::interfaces::erc_4626::{IERC4626Dispatcher, IERC4626DispatcherTrait};
    use clt_ekubo::components::liquidity_amounts::LiquidityAmounts;
    use clt_ekubo::components::math::Math;
    use clt_ekubo::interfaces::clt_base::{StrategyData, Errors};

    pub fn compute_liquidity_share(
        strategy: StrategyData, core: ICoreDispatcher, amount0_max: u256, amount1_max: u256,
    ) -> (u256, u256, u256) {
        let sqrt_ratio = core.get_pool_price(strategy.pool_key.into()).sqrt_ratio;
        let (mut reserve0, mut reserve1) = LiquidityAmounts::get_amounts_for_liquidity(
            sqrt_ratio, strategy.key.into(), strategy.account.ekubo_liquidity,
        );

        if strategy.account.balance0 > 0 {
            reserve0 += strategy.account.balance0;
        }

        if strategy.account.balance1 > 0 {
            reserve1 += strategy.account.balance1;
        }

        if strategy.vault0 != Zero::zero() {
            let vault0 = IERC4626Dispatcher { contract_address: strategy.vault0 };
            let vault0_max_withdraw = vault0.max_withdraw(get_contract_address());

            if vault0_max_withdraw > 0 {
                reserve0 += vault0_max_withdraw;
            }
        }

        if strategy.vault1 != Zero::zero() {
            let vault1 = IERC4626Dispatcher { contract_address: strategy.vault1 };
            let vault1_max_withdraw = vault1.max_withdraw(get_contract_address());

            if vault1_max_withdraw > 0 {
                reserve1 += vault1_max_withdraw;
            }
        }

        assert(
            strategy.account.total_shares == 0 || reserve0 != 0 || reserve1 != 0,
            Errors::EMPTY_STRATEGY,
        );

        calculate_share(amount0_max, amount1_max, reserve0, reserve1, strategy.account.total_shares)
    }

    pub fn calculate_share(
        amount0_max: u256, amount1_max: u256, reserve0: u256, reserve1: u256, total_supply: u256,
    ) -> (u256, u256, u256) {
        let (mut amount0, mut amount1, mut shares): (u256, u256, u256) = (0, 0, 0);

        if total_supply == 0 {
            amount0 = amount0_max;
            amount1 = amount1_max;
            if amount0 > amount1 {
                shares = amount0;
            } else {
                shares = amount1;
            }
        } else if reserve0 == 0 {
            amount1 = amount1_max;
            shares = Math::mul_div(amount1, total_supply, reserve1);
        } else if reserve1 == 0 {
            amount0 = amount0_max;
            shares = Math::mul_div(amount0, total_supply, reserve0);
        } else {
            amount0 = Math::mul_div(amount1_max, reserve0, reserve1);
            if amount0 < amount0_max {
                amount1 = amount1_max;
                shares = Math::mul_div(amount1, total_supply, reserve1);
            } else {
                amount0 = amount0_max;
                amount1 = Math::mul_div(amount0, reserve1, reserve0);
                shares = Math::mul_div(amount0, total_supply, reserve0);
            }
        }

        (shares, amount0, amount1)
    }
}
