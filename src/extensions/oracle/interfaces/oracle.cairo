use starknet::ContractAddress;
use ekubo::types::i129::i129;
use ekubo::types::keys::PoolKey;

#[starknet::interface]
pub trait IOracle<TContractState> {
    // Returns the timestamp of the earliest observation for a given pair, or Option::None if the
    // pair has no observations
    fn get_earliest_observation_time(
        self: @TContractState, token_a: ContractAddress, token_b: ContractAddress,
    ) -> Option<u64>;

    // Returns the time weighted average tick between the given start and end time
    fn get_average_tick_over_period(
        self: @TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        start_time: u64,
        end_time: u64,
        pool_key: PoolKey,
    ) -> i129;

    // Returns the time weighted average tick between the given start and end time
    fn get_average_tick_over_periods(
        self: @TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        start_and_end_times: Span<(u64, u64)>,
        pool_key: PoolKey,
    ) -> Span<i129>;

    // Returns the time weighted average tick over the last `period` seconds
    fn get_average_tick_over_last(
        self: @TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        period: u64,
        pool_key: PoolKey,
    ) -> i129;

    // Returns the a list of ticks representing the TWAP history from `end_time - (num_intervals *
    // interval_seconds)` to `end_time`
    fn get_average_tick_history(
        self: @TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        end_time: u64,
        num_intervals: u32,
        interval_seconds: u32,
        pool_key: PoolKey,
    ) -> Span<i129>;

    // Returns the realized volatility over the period in ticks, extrapolated to the given number of
    // seconds.
    // E.g.: to get the 7 day realized volatility using hourly observations, call with the following
    //  parameters:
    //      end_time = now, num_intervals = 168, interval_seconds = 3600, extrapolated_to = 604800
    // E.g.: to get the annualized realized volatility using half-hourly observations for the last
    //  day, call with the following parameters:
    //      end_time = now, num_intervals = 48, interval_seconds = 1800, extrapolated_to = 31557600
    fn get_realized_volatility_over_period(
        self: @TContractState,
        token_a: ContractAddress,
        token_b: ContractAddress,
        end_time: u64,
        num_intervals: u32,
        interval_seconds: u32,
        extrapolated_to: u32,
        pool_key: PoolKey,
    ) -> u64;

    // Returns the geomean average price of a token as a 128.128 between the given start and end
    // time
    fn get_price_x128_over_period(
        self: @TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        start_time: u64,
        end_time: u64,
        pool_key: PoolKey,
    ) -> u256;

    // Returns the geomean average price of a token as a 128.128 over the last `period` seconds
    fn get_price_x128_over_last(
        self: @TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        period: u64,
        pool_key: PoolKey,
    ) -> u256;


    // Returns the a list of prices representing the TWAP history from `end_time - (num_intervals *
    // interval_seconds)` to `end_time`
    fn get_average_price_x128_history(
        self: @TContractState,
        base_token: ContractAddress,
        quote_token: ContractAddress,
        end_time: u64,
        num_intervals: u32,
        interval_seconds: u32,
        pool_key: PoolKey,
    ) -> Span<u256>;

    // Updates the call points for the latest version of this extension, or simply registers it on
    // the first call
    fn set_call_points(ref self: TContractState);

    // Returns the set oracle token
    fn get_oracle_token(self: @TContractState) -> ContractAddress;
}
