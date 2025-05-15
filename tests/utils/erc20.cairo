use starknet::ContractAddress;
use openzeppelin::token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

pub fn approve(token_address: ContractAddress, spender: ContractAddress, amount: u256) {
    ERC20ABIDispatcher { contract_address: token_address }.approve(spender, amount);
}

pub fn balance_of(token_address: ContractAddress, account: ContractAddress) -> u256 {
    ERC20ABIDispatcher { contract_address: token_address }.balanceOf(account)
}

pub fn transfer(token_address: ContractAddress, recipient: ContractAddress, amount: u256) {
    ERC20ABIDispatcher { contract_address: token_address }.transfer(recipient, amount);
}
