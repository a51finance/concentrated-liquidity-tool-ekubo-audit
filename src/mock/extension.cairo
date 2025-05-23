#[starknet::interface]
pub trait IMockExtension<TContractState> {
    fn get_before_execute(self: @TContractState) -> u8;
    fn get_after_execute(self: @TContractState) -> u8;
}

#[starknet::contract]
pub mod Mockextension {
    use starknet::{ContractAddress};
    use starknet::storage::{StoragePointerWriteAccess, StoragePointerReadAccess};
    use ekubo::interfaces::core::{
        ICoreDispatcher, ICoreDispatcherTrait, IExtension, SwapParameters, UpdatePositionParameters,
    };
    use ekubo::types::call_points::CallPoints;
    use ekubo::types::bounds::Bounds;
    use ekubo::types::delta::Delta;
    use ekubo::types::i129::i129;
    use ekubo::types::keys::PoolKey;

    use clt_ekubo::interfaces::extension_input_validation::IExtensionInputValidation;
    use clt_ekubo::interfaces::clt_modules::StrategyPayload;

    use super::IMockExtension;

    #[storage]
    struct Storage {
        order: u8,
        before_execute: u8,
        after_execute: u8,
    }

    #[constructor]
    pub fn constructor(ref self: ContractState, core: ICoreDispatcher, order: u8) {
        self.order.write(order);
        core
            .set_call_points(
                CallPoints {
                    before_initialize_pool: true,
                    after_initialize_pool: true,
                    before_swap: true,
                    after_swap: true,
                    before_update_position: true,
                    after_update_position: true,
                    before_collect_fees: true,
                    after_collect_fees: true,
                },
            )
    }

    #[abi(embed_v0)]
    impl MockextensionNativeImpl of IMockExtension<ContractState> {
        fn get_before_execute(self: @ContractState) -> u8 {
            self.before_execute.read()
        }

        fn get_after_execute(self: @ContractState) -> u8 {
            self.after_execute.read()
        }
    }

    #[abi(embed_v0)]
    impl MockextensionImpl of IExtension<ContractState> {
        fn before_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129,
        ) {
            self.before_execute.write(self.order.read());
        }

        fn after_initialize_pool(
            ref self: ContractState, caller: ContractAddress, pool_key: PoolKey, initial_tick: i129,
        ) {
            self.after_execute.write(self.order.read());
        }

        fn before_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters,
        ) {
            self.before_execute.write(self.order.read() + 10);
        }

        fn after_swap(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: SwapParameters,
            delta: Delta,
        ) {
            self.after_execute.write(self.order.read() + 10);
        }

        fn before_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters,
        ) {
            self.before_execute.write(self.order.read());
        }

        fn after_update_position(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            params: UpdatePositionParameters,
            delta: Delta,
        ) {
            self.after_execute.write(self.order.read());
        }

        fn before_collect_fees(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            salt: felt252,
            bounds: Bounds,
        ) {
            self.before_execute.write(self.order.read());
        }

        fn after_collect_fees(
            ref self: ContractState,
            caller: ContractAddress,
            pool_key: PoolKey,
            salt: felt252,
            bounds: Bounds,
            delta: Delta,
        ) {
            self.after_execute.write(self.order.read());
        }
    }

    #[abi(embed_v0)]
    impl InputValidationImpl of IExtensionInputValidation<ContractState> {
        fn check_input_data(self: @ContractState, data: StrategyPayload) -> bool {
            true
        }
    }
}
