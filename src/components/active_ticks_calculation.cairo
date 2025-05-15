pub mod ActiveTicksCalculation {
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait};
    use ekubo::types::keys::PoolKey;
    use ekubo::types::i129::i129;

    use clt_ekubo::interfaces::clt_base::StrategyKey;

    pub fn shift_active(
        core: ICoreDispatcher, key: StrategyKey, pool_key: PoolKey,
    ) -> (i129, i129) {
        let tick_spacing = pool_key.tick_spacing;
        let current_tick = core.get_pool_price(pool_key).tick;
        let position_width = _get_active_position_width(key.tick_lower, key.tick_upper);

        let tick_lower = _floor_active_tick(
            current_tick - (position_width / i129 { sign: false, mag: 2 }), tick_spacing,
        );
        let tick_upper = _floor_active_tick(
            current_tick + (position_width / i129 { sign: false, mag: 2 }), tick_spacing,
        );

        (tick_lower, tick_upper)
    }

    fn _floor_active_tick(tick: i129, tick_spacing: u128) -> i129 {
        let mut compressed = tick / tick_spacing.into();
        if tick.sign && tick.mag % tick_spacing != 0 {
            compressed -= i129 { sign: false, mag: 1 };
        }
        compressed * tick_spacing.into()
    }

    fn _get_active_position_width(tick_lower: i129, tick_upper: i129) -> i129 {
        (tick_lower - tick_upper)
    }
}
