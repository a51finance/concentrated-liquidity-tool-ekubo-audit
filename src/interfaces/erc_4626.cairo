use starknet::ContractAddress;

#[starknet::interface]
pub trait IERC4626<TContractState> {
    fn allowance(self: @TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn asset(self: @TContractState) -> ContractAddress;
    fn balance_of(self: @TContractState, account: ContractAddress) -> u256;
    fn convert_to_assets(self: @TContractState, shares: u256) -> u256;
    fn convert_to_shares(self: @TContractState, assets: u256) -> u256;
    fn decimals(self: @TContractState) -> u8;
    fn deposit(ref self: TContractState, assets: u256, receiver: ContractAddress) -> u256;
    fn max_deposit(self: @TContractState, address: ContractAddress) -> u256;
    fn max_mint(self: @TContractState, receiver: ContractAddress) -> u256;
    fn max_redeem(self: @TContractState, owner: ContractAddress) -> u256;
    fn max_withdraw(self: @TContractState, owner: ContractAddress) -> u256;
    fn mint(ref self: TContractState, shares: u256, receiver: ContractAddress) -> u256;
    fn name(self: @TContractState) -> ByteArray;
    fn preview_deposit(self: @TContractState, assets: u256) -> u256;
    fn preview_mint(self: @TContractState, shares: u256) -> u256;
    fn preview_redeem(self: @TContractState, shares: u256) -> u256;
    fn preview_withdraw(self: @TContractState, assets: u256) -> u256;
    fn redeem(
        ref self: TContractState, shares: u256, receiver: ContractAddress, owner: ContractAddress,
    ) -> u256;
    fn symbol(self: @TContractState) -> ByteArray;
    fn total_assets(self: @TContractState) -> u256;
    fn total_supply(self: @TContractState) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256,
    ) -> bool;
    fn withdraw(
        ref self: TContractState, assets: u256, receiver: ContractAddress, owner: ContractAddress,
    ) -> u256;
}
