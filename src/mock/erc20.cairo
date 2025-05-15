#[starknet::contract]
pub mod MockERC20 {
    use starknet::ContractAddress;
    use openzeppelin::token::erc20::ERC20Component;

    component!(path: ERC20Component, storage: erc20, event: Erc20Event);

    #[abi(embed_v0)]
    impl Erc20 = ERC20Component::ERC20MixinImpl<ContractState>;

    impl Erc20Internal = ERC20Component::InternalImpl<ContractState>;
    impl Erc20HooksImpl of ERC20Component::ERC20HooksTrait<ContractState>;

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    pub enum Event {
        #[flat]
        Erc20Event: ERC20Component::Event,
    }

    #[constructor]
    pub fn constructor(
        ref self: ContractState, name: ByteArray, symbol: ByteArray, recipient: ContractAddress,
    ) {
        self.erc20.initializer(name, symbol);
        self.erc20.mint(recipient, 10000000000000000000 * 1_000_000_000_000_000_000);
    }
}
