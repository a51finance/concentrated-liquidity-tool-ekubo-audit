pub mod ModesTicksCalculation {
    use core::num::traits::Zero;
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};
    use ekubo::types::keys::PoolKey;
    use ekubo::types::i129::i129;

    use clt_ekubo::interfaces::clt_base::StrategyKey;

    const LIQUIDITY_SHIFT_NOT_NEEDED: felt252 = 'liquidity shift not needed';

    pub fn shift_left(
        core: ICoreDispatcher, key: StrategyKey, pool_key: PoolKey, mut current_tick: i129,
    ) -> (i129, i129) {
        assert(current_tick < key.tick_lower, LIQUIDITY_SHIFT_NOT_NEEDED);

        let tick_spacing = pool_key.tick_spacing;
        current_tick = core.get_pool_price(pool_key).tick;
        current_tick = _floor_tick(current_tick, tick_spacing);

        let position_width = _get_position_width(current_tick, key.tick_lower, key.tick_upper);
        let tick_lower = current_tick + tick_spacing.into();
        let tick_upper = _floor_tick(tick_lower + position_width, tick_spacing);

        (tick_lower, tick_upper)
    }

    pub fn shift_right(
        core: ICoreDispatcher, key: StrategyKey, pool_key: PoolKey, mut current_tick: i129,
    ) -> (i129, i129) {
        assert(current_tick > key.tick_upper, LIQUIDITY_SHIFT_NOT_NEEDED);

        let tick_spacing = pool_key.tick_spacing;
        current_tick = core.get_pool_price(pool_key).tick;
        current_tick = _floor_tick(current_tick, tick_spacing);

        let position_width = _get_position_width(current_tick, key.tick_lower, key.tick_upper);
        let tick_upper = current_tick - tick_spacing.into();
        let tick_lower = _floor_tick(tick_upper - position_width, tick_spacing);

        (tick_lower, tick_upper)
    }

    pub fn shift_both_side(
        core: ICoreDispatcher, key: StrategyKey, pool_key: PoolKey, mut current_tick: i129,
    ) -> (i129, i129) {
        if current_tick < key.tick_lower {
            return shift_left(core, key, pool_key, current_tick);
        }

        if current_tick > key.tick_upper {
            return shift_right(core, key, pool_key, current_tick);
        }

        assert(false, LIQUIDITY_SHIFT_NOT_NEEDED);

        //reverted earlier only for return type
        (Zero::zero(), Zero::zero())
    }

    fn _floor_tick(tick: i129, tick_spacing: u128) -> i129 {
        let mut compressed = tick / tick_spacing.into();
        if tick.sign && tick.mag % tick_spacing != 0 {
            compressed -= i129 { sign: false, mag: 1 };
        }
        compressed * tick_spacing.into()
    }

    fn _get_position_width(current_tick: i129, tick_lower: i129, tick_upper: i129) -> i129 {
        ((current_tick - tick_lower) + (tick_upper - current_tick))
    }
}
