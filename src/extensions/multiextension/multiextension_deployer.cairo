#[starknet::contract]
pub mod MultiextensionDeployer {
    use starknet::{ContractAddress, ClassHash, get_contract_address};
    use starknet::event::EventEmitter;
    use starknet::storage::{StoragePointerWriteAccess, StoragePointerReadAccess};
    use starknet::syscalls::deploy_syscall;
    use ekubo::interfaces::core::ICoreDispatcher;
    use openzeppelin::access::ownable::OwnableComponent;

    use clt_ekubo::extensions::multiextension::interfaces::multiextension::{
        IMultiextensionDispatcher, IMultiextensionDispatcherTrait, PacketExtension,
    };
    use clt_ekubo::extensions::multiextension::interfaces::multiextension_deployer::IMultiextensionDeployer;
    use clt_ekubo::components::util::serialize;

    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);

    #[abi(embed_v0)]
    impl Ownable = OwnableComponent::OwnableImpl<ContractState>;

    impl OwnableInternal = OwnableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        multiextension_class_hash: ClassHash,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
    }

    #[derive(Drop, starknet::Event)]
    pub struct UpdatedClassHash {
        new_class_hash: ClassHash,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    pub enum Event {
        UpdatedClassHash: UpdatedClassHash,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        core: ICoreDispatcher,
        multiextension_class_hash: ClassHash,
        owner: ContractAddress,
    ) {
        self.ownable.initializer(owner);
        self.core.write(core);
        self.multiextension_class_hash.write(multiextension_class_hash);
    }

    #[abi(embed_v0)]
    impl MultiextensionDeployerImpl of IMultiextensionDeployer<ContractState> {
        fn deploy_multiextension(self: @ContractState) -> ContractAddress {
            let constructor_calldata = serialize::<
                (ICoreDispatcher, u64, ContractAddress),
            >(@(self.core.read(), 0, get_contract_address()))
                .span();

            let (deployed_address, _) = deploy_syscall(
                self.multiextension_class_hash.read(), 0, constructor_calldata, false,
            )
                .unwrap();

            deployed_address
        }

        fn init_multiextension(
            self: @ContractState,
            multiextension: ContractAddress,
            extensions: Span<PacketExtension>,
            activated_extensions: u256,
        ) {
            IMultiextensionDispatcher { contract_address: multiextension }
                .init_extensions(extensions, activated_extensions);
        }

        fn deploy_multiextension_and_init(
            self: @ContractState, extensions: Span<PacketExtension>, activated_extensions: u256,
        ) -> ContractAddress {
            let deployed_address = self.deploy_multiextension();
            self.init_multiextension(deployed_address, extensions, activated_extensions);

            deployed_address
        }

        fn update_class_hash(ref self: ContractState, class_hash: ClassHash) {
            self.ownable.assert_only_owner();
            self.multiextension_class_hash.write(class_hash);
            self.emit(UpdatedClassHash { new_class_hash: class_hash });
        }
    }
}
