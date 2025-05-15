use starknet::{ContractAddress, ClassHash};

use clt_ekubo::extensions::multiextension::interfaces::multiextension::PacketExtension;

#[starknet::interface]
pub trait IMultiextensionDeployer<TContractState> {
    fn deploy_multiextension(self: @TContractState) -> ContractAddress;

    fn init_multiextension(
        self: @TContractState,
        multiextension: ContractAddress,
        extensions: Span<PacketExtension>,
        activated_extensions: u256,
    );

    fn deploy_multiextension_and_init(
        self: @TContractState, extensions: Span<PacketExtension>, activated_extensions: u256,
    ) -> ContractAddress;

    fn update_class_hash(ref self: TContractState, class_hash: ClassHash);
}
