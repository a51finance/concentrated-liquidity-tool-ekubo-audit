//struct to store protocol fee
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct ProtocolFeeRegistry {
    pub lp_automation_fee: u256,
    pub strategy_creation_fee: u256,
}

#[starknet::interface]
pub trait IGovernanceFeeHandler<TContractState> {
    //get the fee data
    fn get_governance_fee(self: @TContractState, is_private: bool) -> (u256, u256);
    //set fee data for public strategies
    fn set_public_fee_registry(
        ref self: TContractState, new_public_strategy_fee_registry: ProtocolFeeRegistry,
    );
    //set fee data for private strategies
    fn set_private_fee_registry(
        ref self: TContractState, new_private_strategy_fee_registry: ProtocolFeeRegistry,
    );
}

//fee handler errors
pub mod Errors {
    pub const STRATEGY_FEE_LIMIT_EXCEED: felt252 = 'FH: strategy fle';
    pub const MANAGEMENT_FEE_LIMIT_EXCEED: felt252 = 'FH: management fle';
    pub const PERFORMANCE_FEE_LIMIT_EXCEED: felt252 = 'FH: performance fle';
    pub const LP_AUTOMATION_FEE_LIMIT_EXCEED: felt252 = 'FH: lp automation fle';
}
