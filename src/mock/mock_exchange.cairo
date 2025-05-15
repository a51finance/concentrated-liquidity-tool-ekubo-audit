#[starknet::contract]
mod MockExchange {
    use starknet::ContractAddress;
    use openzeppelin::token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

    #[storage]
    struct Storage {}

    #[external(v0)]
    fn swap_exact_tokens_to(
        ref self: ContractState,
        src_token: ContractAddress,
        dst_token: ContractAddress,
        amountIn: u256,
        recipient: ContractAddress,
        amountOut: u256,
    ) {
        ERC20ABIDispatcher { contract_address: src_token }
            .transfer_from(
                starknet::get_caller_address(), starknet::get_contract_address(), amountIn,
            );
        ERC20ABIDispatcher { contract_address: dst_token }.transfer(recipient, amountOut);
    }
}
