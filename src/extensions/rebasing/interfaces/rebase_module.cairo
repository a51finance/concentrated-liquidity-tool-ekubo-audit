use ekubo::types::i129::i129;

use clt_ekubo::types::pool_id::PoolId;

#[derive(Copy, Drop, Serde)]
pub struct ExecutableStrategiesData {
    pub strategy_id: PoolId,
    pub mode: u256,
    pub actions: Span<felt252>,
    pub action_status: Span<felt252>,
    pub action_name: felt252,
}


#[derive(Copy, Drop, Serde)]
pub struct StrategyProcessingDetails {
    pub rebase_count: u256,
    pub manual_swaps_count: u256,
    pub last_update_timeStamp: u256,
    pub last_rebalanced_ticks: i129,
}

#[derive(Copy, Drop, Serde)]
pub struct ThresholdParams {
    pub lower_threshold_diff: i129,
    pub upper_threshold_diff: i129,
    pub initial_current_tick: i129,
    pub initial_tick_lower: i129,
    pub initial_tick_upper: i129,
}

#[derive(Copy, Drop, Serde)]
pub struct AdjustedThresholdData {
    pub adjusted_lower_difference: i129,
    pub adjusted_upper_difference: i129,
}

pub mod Errors {
    pub const INVALID_REBASE_THRESHOLD_DIFFERENCE: felt252 = 'REBASE: IRTD';
    pub const REBASE_STRATEGY_DATA_CANNOT_BE_ZERO: felt252 = 'REBASE: RSDCBZ';
}
