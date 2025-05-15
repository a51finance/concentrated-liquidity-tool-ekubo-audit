#[starknet::contract]
pub mod CLTModules {
    use starknet::event::EventEmitter;
    use starknet::ContractAddress;
    use starknet::storage::{
        Map, StoragePointerWriteAccess, StoragePointerReadAccess, StoragePathEntry,
    };
    use openzeppelin::access::ownable::OwnableComponent;

    use clt_ekubo::components::constants::Constants;
    use clt_ekubo::components::util::deserialize;
    use clt_ekubo::interfaces::clt_modules::{ICLTModules, StrategyPayload, Errors};
    use clt_ekubo::interfaces::governance_fee_handler::{Errors as FeeHandlerErrors};
    use clt_ekubo::interfaces::extension_input_validation::{
        IExtensionInputValidationDispatcher, IExtensionInputValidationDispatcherTrait,
    };

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl Ownable = OwnableComponent::OwnableImpl<ContractState>;

    impl OwnableInternal = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        pub intent: Map<felt252, bool>,
        pub intent_extension: Map<felt252, ContractAddress>,
        pub intent_action: Map<felt252, Map<felt252, bool>>,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[derive(Drop, starknet::Event)]
    pub struct IntentAdded {
        intent_key: felt252,
    }

    #[derive(Drop, starknet::Event)]
    pub struct IntentExtensionAdded {
        intent_key: felt252,
        extension: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    pub struct IntentActionAdded {
        intent_key: felt252,
        action: felt252,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    pub enum Event {
        IntentAdded: IntentAdded,
        IntentExtensionAdded: IntentExtensionAdded,
        IntentActionAdded: IntentActionAdded,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, owner: ContractAddress) {
        self.ownable.initializer(owner);
    }

    #[generate_trait]
    pub impl Internal of InternalTrait {
        fn _check_intent_key(self: @ContractState, intent_key: felt252) {
            assert(self.intent.entry(intent_key).read(), Errors::INVALID_INTENT);
        }

        fn _check_mode_ids(self: @ContractState, data: StrategyPayload) {
            assert(
                self.intent_action.entry(data.intent).entry(data.action_name).read(),
                Errors::INVALID_INTENT_ACTION,
            );
        }

        fn _validate_input_data(self: @ContractState, data: StrategyPayload) {
            let extension = self.intent_extension.entry(data.intent).read();
            IExtensionInputValidationDispatcher { contract_address: extension }
                .check_input_data(data);
        }
    }

    #[abi(embed_v0)]
    impl ICLTModulesImpl of ICLTModules<ContractState> {
        fn set_intent(ref self: ContractState, intent_key: felt252) {
            self.ownable.assert_only_owner();
            self.intent.entry(intent_key).write(true);
            self.emit(IntentAdded { intent_key });
        }

        fn set_intent_address(
            ref self: ContractState, intent_key: felt252, extension: ContractAddress,
        ) {
            self.ownable.assert_only_owner();
            self._check_intent_key(intent_key);
            self.intent_extension.entry(intent_key).write(extension);
            self.emit(IntentExtensionAdded { intent_key, extension });
        }

        fn set_intent_action(ref self: ContractState, intent_key: felt252, action: felt252) {
            self.ownable.assert_only_owner();
            self._check_intent_key(intent_key);
            self.intent_action.entry(intent_key).entry(action).write(true);
            self.emit(IntentActionAdded { intent_key, action });
        }

        fn validate_modes(
            self: @ContractState,
            action_data: Span<felt252>,
            management_fee: u256,
            performance_fee: u256,
        ) {
            let (mode, data) = deserialize::<(u256, Array<StrategyPayload>)>(action_data);
            assert(mode >= 1 && mode <= 4, Errors::INVALID_MODE);
            assert(
                management_fee <= Constants::MAX_MANAGEMENT_FEE,
                FeeHandlerErrors::MANAGEMENT_FEE_LIMIT_EXCEED,
            );
            assert(
                performance_fee <= Constants::MAX_PERFORMANCE_FEE,
                FeeHandlerErrors::PERFORMANCE_FEE_LIMIT_EXCEED,
            );

            for index in 0..data.len() {
                let strategy_payload = *(data.get(index).unwrap().unbox());
                self._check_mode_ids(strategy_payload);
                self._validate_input_data(strategy_payload);
            }
        }
    }
}
