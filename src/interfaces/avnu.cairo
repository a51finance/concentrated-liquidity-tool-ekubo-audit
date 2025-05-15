use starknet::{ClassHash, ContractAddress};


#[starknet::interface]
pub trait IOwnable<TContractState> {
    // Ownable entry points
    fn get_owner(self: @TContractState) -> ContractAddress;
    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);
}

#[starknet::interface]
pub trait IUpgradable<TContractState> {
    // Upgradeable entry point
    fn upgrade_class(ref self: TContractState, new_class_hash: ClassHash);
}


#[derive(Drop, Serde, Debug, PartialEq, starknet::Store)]
pub struct TokenFeeConfig {
    // Even though we have just 1 field now, we keep the struct so that we can support future token
    // specific customization
    pub weight: u32,
}

#[derive(Drop, Serde, Clone)]
pub struct Route {
    pub sell_token: ContractAddress,
    pub buy_token: ContractAddress,
    pub exchange_address: ContractAddress,
    pub percent: u128,
    pub additional_swap_params: Array<felt252>,
}

#[starknet::interface]
pub trait IFee<TContractState> {
    // Fees entrypoints
    fn get_fees_recipient(self: @TContractState) -> ContractAddress;
    fn set_fees_recipient(ref self: TContractState, fees_recipient: ContractAddress) -> bool;
    fn get_fees_bps_0(self: @TContractState) -> u128;
    fn set_fees_bps_0(ref self: TContractState, bps: u128) -> bool;
    fn get_fees_bps_1(self: @TContractState) -> u128;
    fn set_fees_bps_1(ref self: TContractState, bps: u128) -> bool;
    fn get_swap_exact_token_to_fees_bps(self: @TContractState) -> u128;
    fn set_swap_exact_token_to_fees_bps(ref self: TContractState, bps: u128) -> bool;
    fn get_token_fee_config(self: @TContractState, token: ContractAddress) -> TokenFeeConfig;
    fn set_token_fee_config(
        ref self: TContractState, token: ContractAddress, config: TokenFeeConfig,
    ) -> bool;
    fn is_integrator_whitelisted(self: @TContractState, integrator: ContractAddress) -> bool;
    fn set_whitelisted_integrator(
        ref self: TContractState, integrator: ContractAddress, whitelisted: bool,
    ) -> bool;
}

#[starknet::interface]
pub trait IExchange<TContractState> {
    // Exchange entrypoints
    fn get_adapter_class_hash(
        self: @TContractState, exchange_address: ContractAddress,
    ) -> ClassHash;
    fn set_adapter_class_hash(
        ref self: TContractState, exchange_address: ContractAddress, adapter_class_hash: ClassHash,
    ) -> bool;
    fn multi_route_swap(
        ref self: TContractState,
        sell_token_address: ContractAddress,
        sell_token_amount: u256,
        buy_token_address: ContractAddress,
        buy_token_amount: u256,
        buy_token_min_amount: u256,
        beneficiary: ContractAddress,
        integrator_fee_amount_bps: u128,
        integrator_fee_recipient: ContractAddress,
        routes: Array<Route>,
    ) -> bool;
    fn swap_exact_token_to(
        ref self: TContractState,
        sell_token_address: ContractAddress,
        sell_token_amount: u256,
        sell_token_max_amount: u256,
        buy_token_address: ContractAddress,
        buy_token_amount: u256,
        beneficiary: ContractAddress,
        routes: Array<Route>,
    ) -> bool;
}
