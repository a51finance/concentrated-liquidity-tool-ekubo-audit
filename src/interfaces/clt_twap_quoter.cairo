use ekubo::types::keys::PoolKey;
use ekubo::types::i129::i129;

use clt_ekubo::types::pool_id::PoolId;

#[starknet::interface]
pub trait ICLTTwapQuoter<TContractState> {
    //check given pool deviation
    fn check_deviation(self: @TContractState, key: PoolKey, twap_duration: u32);
    //get pool twap for a given period of time
    fn get_twap(self: @TContractState, key: PoolKey, twap_duration: u32) -> i129;
    //get pool deviation strategy
    fn pool_strategy(self: @TContractState, key: PoolId) -> i129;
}

//clt twap errors
pub mod Errors {
    pub const MAX_TWAP_DEVIATION_EXCEEDED: felt252 = 'CLTTwap: deviation exceeded';
}
