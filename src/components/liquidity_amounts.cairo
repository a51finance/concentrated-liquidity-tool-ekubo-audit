pub mod LiquidityAmounts {
    use ekubo::interfaces::mathlib::{dispatcher, IMathLibDispatcherTrait};
    use ekubo::types::bounds::Bounds;

    pub fn get_liquidity_for_amounts(
        sqrt_ratio: u256, bounds: Bounds, amount0: u256, amount1: u256,
    ) -> u128 {
        let ekubo_math = dispatcher();

        let mut sqrt_ratio_lower = ekubo_math.tick_to_sqrt_ratio(bounds.lower);
        let mut sqrt_ratio_upper = ekubo_math.tick_to_sqrt_ratio(bounds.upper);

        // Ensure sqrt_ratio_lower <= sqrt_ratio_upper for Ekubo math
        if sqrt_ratio_lower > sqrt_ratio_upper {
            let temp_sqrt_ratio = sqrt_ratio_lower;
            sqrt_ratio_lower = sqrt_ratio_upper;
            sqrt_ratio_upper = temp_sqrt_ratio;
        }

        ekubo_math
            .max_liquidity(
                sqrt_ratio,
                sqrt_ratio_lower,
                sqrt_ratio_upper,
                amount0: amount0.try_into().unwrap(),
                amount1: amount1.try_into().unwrap(),
            )
    }

    pub fn get_amounts_for_liquidity(
        sqrt_ratio: u256, bounds: Bounds, liquidity: u128,
    ) -> (u256, u256) {
        let ekubo_math = dispatcher();
        let mut sqrt_ratio_a = ekubo_math.tick_to_sqrt_ratio(bounds.lower);
        let mut sqrt_ratio_b = ekubo_math.tick_to_sqrt_ratio(bounds.upper);

        let mut amount0: u128 = 0;
        let mut amount1: u128 = 0;

        if sqrt_ratio_a > sqrt_ratio_b {
            let sqrt_ratio_c = sqrt_ratio_a;
            sqrt_ratio_a = sqrt_ratio_b;
            sqrt_ratio_b = sqrt_ratio_c;
        }

        if sqrt_ratio <= sqrt_ratio_a {
            amount0 = ekubo_math.amount0_delta(sqrt_ratio_a, sqrt_ratio_b, liquidity, true);
        } else if sqrt_ratio < sqrt_ratio_b {
            amount0 = ekubo_math.amount0_delta(sqrt_ratio, sqrt_ratio_b, liquidity, true);
            amount1 = ekubo_math.amount1_delta(sqrt_ratio_a, sqrt_ratio, liquidity, true);
        } else {
            amount1 = ekubo_math.amount1_delta(sqrt_ratio_a, sqrt_ratio_b, liquidity, true);
        }

        (amount0.into(), amount1.into())
    }
}
