#[starknet::contract]
pub mod MockERC4626 {
    use core::num::traits::Bounded;
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use starknet::storage::{
        StoragePointerWriteAccess, StoragePointerReadAccess, StorageMapWriteAccess,
    };
    use openzeppelin::token::erc20::{
        ERC20ABIDispatcher, ERC20Component, ERC20Component::Errors as ERC20Errors,
        interface::{ERC20ABIDispatcherTrait},
    };

    use clt_ekubo::interfaces::erc_4626::IERC4626;

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    impl ERC20MetadataImpl = ERC20Component::ERC20MetadataImpl<ContractState>;
    impl ERC20InternalImpl = ERC20Component::InternalImpl<ContractState>;
    impl Erc20HooksImpl of ERC20Component::ERC20HooksTrait<ContractState>;

    pub mod Errors {
        pub const EXCEEDED_MAX_DEPOSIT: felt252 = 'ERC4626: exceeded max deposit';
        pub const EXCEEDED_MAX_MINT: felt252 = 'ERC4626: exceeded max mint';
        pub const EXCEEDED_MAX_REDEEM: felt252 = 'ERC4626: exceeded max redeem';
        pub const EXCEEDED_MAX_WITHDRAW: felt252 = 'ERC4626: exceeded max withdraw';
    }

    #[storage]
    struct Storage {
        asset: ContractAddress,
        underlying_decimals: u8,
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        Deposit: Deposit,
        Withdraw: Withdraw,
        ERC20Event: ERC20Component::Event,
    }

    #[derive(Drop, starknet::Event)]
    struct Deposit {
        #[key]
        sender: ContractAddress,
        #[key]
        owner: ContractAddress,
        assets: u256,
        shares: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Withdraw {
        #[key]
        sender: ContractAddress,
        #[key]
        receiver: ContractAddress,
        #[key]
        owner: ContractAddress,
        assets: u256,
        shares: u256,
    }


    #[constructor]
    fn constructor(
        ref self: ContractState, asset: ContractAddress, name: ByteArray, symbol: ByteArray,
    ) {
        let dispatcher = ERC20ABIDispatcher { contract_address: asset };
        let decimals = dispatcher.decimals();
        ERC20InternalImpl::initializer(ref self.erc20, name, symbol);
        self.asset.write(asset);
        self.underlying_decimals.write(decimals);
    }

    #[abi(embed_v0)]
    impl ERC4626 of IERC4626<ContractState> {
        fn allowance(
            self: @ContractState, owner: ContractAddress, spender: ContractAddress,
        ) -> u256 {
            ERC20Impl::allowance(self, owner, spender)
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            ERC20Impl::approve(ref self, spender, amount)
        }

        fn asset(self: @ContractState) -> ContractAddress {
            self.asset.read()
        }

        fn balance_of(self: @ContractState, account: ContractAddress) -> u256 {
            ERC20Impl::balance_of(self, account)
        }

        fn convert_to_assets(self: @ContractState, shares: u256) -> u256 {
            self._convert_to_assets(shares)
        }

        fn convert_to_shares(self: @ContractState, assets: u256) -> u256 {
            self._convert_to_shares(assets)
        }

        fn decimals(self: @ContractState) -> u8 {
            self.underlying_decimals.read()
        }

        fn deposit(ref self: ContractState, assets: u256, receiver: ContractAddress) -> u256 {
            let max_assets = self.max_deposit(receiver);
            assert(max_assets >= assets, Errors::EXCEEDED_MAX_DEPOSIT);

            let caller = get_caller_address();
            let shares = self.preview_deposit(assets);
            InternalImpl::_deposit(ref self, caller, receiver, assets, shares);

            shares
        }

        fn max_deposit(self: @ContractState, address: ContractAddress) -> u256 {
            Bounded::MAX
        }

        fn max_mint(self: @ContractState, receiver: ContractAddress) -> u256 {
            Bounded::MAX
        }

        fn max_redeem(self: @ContractState, owner: ContractAddress) -> u256 {
            ERC20Impl::balance_of(self, owner)
        }

        fn max_withdraw(self: @ContractState, owner: ContractAddress) -> u256 {
            self._convert_to_assets(ERC20Impl::balance_of(self, owner))
        }

        fn mint(ref self: ContractState, shares: u256, receiver: ContractAddress) -> u256 {
            let max_shares = self.max_mint(receiver);
            assert(max_shares >= shares, Errors::EXCEEDED_MAX_MINT);

            let caller = get_caller_address();
            let assets = self.preview_mint(shares);
            InternalImpl::_deposit(ref self, caller, receiver, assets, shares);

            assets
        }

        fn name(self: @ContractState) -> ByteArray {
            ERC20MetadataImpl::name(self)
        }

        fn preview_deposit(self: @ContractState, assets: u256) -> u256 {
            self._convert_to_shares(assets)
        }

        fn preview_mint(self: @ContractState, shares: u256) -> u256 {
            self._convert_to_assets(shares)
        }

        fn preview_redeem(self: @ContractState, shares: u256) -> u256 {
            self._convert_to_assets(shares)
        }

        fn preview_withdraw(self: @ContractState, assets: u256) -> u256 {
            self._convert_to_shares(assets)
        }

        fn redeem(
            ref self: ContractState,
            shares: u256,
            receiver: ContractAddress,
            owner: ContractAddress,
        ) -> u256 {
            let max_shares = self.max_redeem(owner);
            assert(shares <= max_shares, Errors::EXCEEDED_MAX_REDEEM);

            let caller = get_caller_address();
            let assets = self.preview_redeem(shares);
            InternalImpl::_withdraw(ref self, caller, receiver, owner, assets, shares);

            assets
        }

        fn symbol(self: @ContractState) -> ByteArray {
            ERC20MetadataImpl::symbol(self)
        }

        fn total_assets(self: @ContractState) -> u256 {
            let dispatcher = ERC20ABIDispatcher { contract_address: self.asset.read() };
            dispatcher.balance_of(get_contract_address())
        }

        fn total_supply(self: @ContractState) -> u256 {
            ERC20Impl::total_supply(self)
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            ERC20Impl::transfer(ref self, recipient, amount)
        }

        fn transfer_from(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256,
        ) -> bool {
            ERC20Impl::transfer_from(ref self, sender, recipient, amount)
        }

        fn withdraw(
            ref self: ContractState,
            assets: u256,
            receiver: ContractAddress,
            owner: ContractAddress,
        ) -> u256 {
            let max_assets = self.max_withdraw(owner);
            assert(assets <= max_assets, Errors::EXCEEDED_MAX_WITHDRAW);

            let caller = get_caller_address();
            let shares = self.preview_withdraw(assets);
            InternalImpl::_withdraw(ref self, caller, receiver, owner, assets, shares);

            shares
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalImplTrait {
        fn _convert_to_assets(self: @ContractState, shares: u256) -> u256 {
            shares * (self.total_assets() + 1) / (ERC20Impl::total_supply(self) + 1)
        }

        fn _convert_to_shares(self: @ContractState, assets: u256) -> u256 {
            assets * (ERC20Impl::total_supply(self) + 1) / (self.total_assets() + 1)
        }

        fn _deposit(
            ref self: ContractState,
            caller: ContractAddress,
            receiver: ContractAddress,
            assets: u256,
            shares: u256,
        ) {
            let dispatcher = ERC20ABIDispatcher { contract_address: self.asset.read() };
            dispatcher.transfer_from(caller, get_contract_address(), assets);
            ERC20InternalImpl::mint(ref self.erc20, receiver, shares);

            self.emit(Deposit { sender: caller, owner: receiver, assets, shares });
        }

        fn _withdraw(
            ref self: ContractState,
            caller: ContractAddress,
            receiver: ContractAddress,
            owner: ContractAddress,
            assets: u256,
            shares: u256,
        ) {
            if (caller != owner) {
                let allowance = ERC20Impl::allowance(@self, owner, caller);
                if (allowance != Bounded::MAX) {
                    assert(allowance >= shares, ERC20Errors::APPROVE_FROM_ZERO);
                    self.erc20.ERC20_allowances.write((owner, caller), allowance - shares);
                }
            }

            ERC20InternalImpl::burn(ref self.erc20, owner, shares);
            let dispatcher = ERC20ABIDispatcher { contract_address: self.asset.read() };
            dispatcher.transfer(receiver, assets);

            self.emit(Withdraw { sender: caller, receiver, owner, assets, shares });
        }
    }
}
