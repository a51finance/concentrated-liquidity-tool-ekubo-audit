use starknet::ContractAddress;

//struct to represent specific intent
#[derive(Copy, Drop, Serde)]
pub struct StrategyPayload {
    pub intent: felt252,
    pub action_name: felt252,
    pub data: Span<felt252>,
}

#[starknet::interface]
pub trait ICLTModules<TContractState> {
    //init new intent
    fn set_intent(ref self: TContractState, intent_key: felt252);
    //assign extension to a particular intent
    fn set_intent_address(
        ref self: TContractState, intent_key: felt252, extension: ContractAddress,
    );
    //assign action to particular intent
    fn set_intent_action(ref self: TContractState, intent_key: felt252, action: felt252);
    //validate data of an intent
    fn validate_modes(
        self: @TContractState,
        action_data: Span<felt252>,
        management_fee: u256,
        performance_fee: u256,
    );
}

//clt module errors
pub mod Errors {
    pub const INVALID_MODE: felt252 = 'CLTMOD: invalid mode';
    pub const INVALID_INTENT: felt252 = 'CLTMOD: invalid intent';
    pub const INVALID_INTENT_ACTION: felt252 = 'CLTMOD: invalid intent action';
}
