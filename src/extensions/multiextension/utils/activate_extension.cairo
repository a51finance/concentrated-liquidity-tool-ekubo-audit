use starknet::{ContractAddress};

use clt_ekubo::extensions::multiextension::interfaces::multiextension::PacketExtension;
use clt_ekubo::extensions::multiextension::utils::bit_math::{
    ExtensionMethod, activate_extension, set_queue_position,
};

#[derive(Drop, Copy)]
pub struct ExtMethodStruct {
    pub method: ExtensionMethod,
    pub position: u8,
    pub activate: bool,
}

#[derive(Drop, Copy)]
pub struct ExtStruct {
    pub extension: ContractAddress,
    pub methods: Span<ExtMethodStruct>,
}

//add extension with methods in activated extensions
//return the updated activated extensions along with extension queue which have the order
//in which each method will be called
pub fn generate_activated_extensions(
    activated_extensions: u256, methods: Span<ExtMethodStruct>, extension_id: u8,
) -> (u256, u32) {
    let mut new_activated_extensions = activated_extensions;
    let mut extension_queue = 0_u32;
    for index in 0..methods.len() {
        let method_wrapper = *(methods.get(index).unwrap().unbox());
        new_activated_extensions =
            activate_extension(
                new_activated_extensions,
                method_wrapper.method,
                extension_id,
                method_wrapper.activate,
            );
        if method_wrapper.activate {
            extension_queue =
                set_queue_position(extension_queue, method_wrapper.method, method_wrapper.position);
        }
    };
    (new_activated_extensions, extension_queue)
}

//generate packet extensions
pub fn generate_extension_data(extensions: Span<ExtStruct>) -> (u256, Array<PacketExtension>) {
    let mut activated_extensions = 0_u256;
    let mut packet_extensions: Array<PacketExtension> = array![];

    for index in 0..extensions.len() {
        let extension_wrapper = *(extensions.get(index).unwrap().unbox());
        let (_activated_extensions, extension_queue) = generate_activated_extensions(
            activated_extensions, extension_wrapper.methods, index.try_into().unwrap(),
        );
        activated_extensions = _activated_extensions;
        packet_extensions
            .append(PacketExtension { extension: extension_wrapper.extension, extension_queue });
    };

    (activated_extensions, packet_extensions)
}

