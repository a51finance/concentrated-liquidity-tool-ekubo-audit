#[starknet::contract]
pub mod GovernanceFeeHandler {
    use starknet::event::EventEmitter;
    use starknet::{ContractAddress, get_caller_address};
    use starknet::storage::{
        StoragePointerWriteAccess, StorableStoragePointerReadAccess, StoragePointerReadAccess,
    };

    use clt_ekubo::components::constants::Constants;
    use clt_ekubo::interfaces::governance_fee_handler::{
        IGovernanceFeeHandler, ProtocolFeeRegistry, Errors,
    };

    #[storage]
    struct Storage {
        pub timelock: ContractAddress,
        pub public_strategy_fee_registry: ProtocolFeeRegistry,
        pub private_strategy_fee_registry: ProtocolFeeRegistry,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PublicFeeRegistryUpdated {
        new_registry: ProtocolFeeRegistry,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PrivateFeeRegistryUpdated {
        new_registry: ProtocolFeeRegistry,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    pub enum Event {
        PublicFeeRegistryUpdated: PublicFeeRegistryUpdated,
        PrivateFeeRegistryUpdated: PrivateFeeRegistryUpdated,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        timelock: ContractAddress,
        public_strategy_fee_registry: ProtocolFeeRegistry,
        private_strategy_fee_registry: ProtocolFeeRegistry,
    ) {
        self.timelock.write(timelock);
        self.public_strategy_fee_registry.write(public_strategy_fee_registry);
        self.private_strategy_fee_registry.write(private_strategy_fee_registry);
    }

    pub fn _check_limit(fee_params: ProtocolFeeRegistry) {
        assert(
            fee_params.lp_automation_fee <= Constants::MAX_AUTOMATION_FEE,
            Errors::LP_AUTOMATION_FEE_LIMIT_EXCEED,
        );
        assert(
            fee_params.strategy_creation_fee <= Constants::MAX_STRATEGY_CREATION_FEE,
            Errors::STRATEGY_FEE_LIMIT_EXCEED,
        );
    }

    #[generate_trait]
    pub impl Internal of InternalTrait {
        fn _only_timelock(self: @ContractState) {
            assert(self.timelock.read() == get_caller_address(), 'UNAUTHORIZED');
        }
    }

    #[abi(embed_v0)]
    impl GovernanceFeeHandlerImpl of IGovernanceFeeHandler<ContractState> {
        fn get_governance_fee(self: @ContractState, is_private: bool) -> (u256, u256) {
            if is_private {
                let private_strategy_fee_registry = self.private_strategy_fee_registry.read();
                return (
                    private_strategy_fee_registry.lp_automation_fee,
                    private_strategy_fee_registry.strategy_creation_fee,
                );
            }

            let public_strategy_fee_registry = self.public_strategy_fee_registry.read();
            (
                public_strategy_fee_registry.lp_automation_fee,
                public_strategy_fee_registry.strategy_creation_fee,
            )
        }

        fn set_public_fee_registry(
            ref self: ContractState, new_public_strategy_fee_registry: ProtocolFeeRegistry,
        ) {
            self._only_timelock();
            _check_limit(new_public_strategy_fee_registry);
            self.public_strategy_fee_registry.write(new_public_strategy_fee_registry);
            self.emit(PublicFeeRegistryUpdated { new_registry: new_public_strategy_fee_registry });
        }

        fn set_private_fee_registry(
            ref self: ContractState, new_private_strategy_fee_registry: ProtocolFeeRegistry,
        ) {
            self._only_timelock();
            _check_limit(new_private_strategy_fee_registry);
            self.private_strategy_fee_registry.write(new_private_strategy_fee_registry);
            self
                .emit(
                    PrivateFeeRegistryUpdated { new_registry: new_private_strategy_fee_registry },
                );
        }
    }
}
