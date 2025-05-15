use starknet::ContractAddress;

//extension wrapper
#[derive(Copy, Drop, Serde, PartialEq, starknet::Store)]
pub struct PacketExtension {
    pub extension: ContractAddress,
    pub extension_queue: u32,
}

#[starknet::interface]
pub trait IMultiextension<TContractState> {
    //initialize contract with initial extensions
    fn init_extensions(
        ref self: TContractState,
        init_extensions: Span<PacketExtension>,
        init_activated_extensions: u256,
    );
    //set new extensions as pending one
    fn change_extensions(
        ref self: TContractState,
        updated_extensions: Span<PacketExtension>,
        updated_activated_extensions: u256,
    );
    //replace the extensions with pending one, when timelock passed
    fn accept_new_extensions(ref self: TContractState);
    //reject the pending extensions
    fn reject_new_extensions(ref self: TContractState);
}

pub mod Errors {
    pub const MAX_EXTENSIONS_COUNT_EXCEEDED: felt252 = 'MAX_EXTENSIONS_COUNT_EXCEEDED';
    pub const NO_EXTENSIONS_PENDING_APPROVAL: felt252 = 'NO_EXTENSIONS_PENDING_APPROVAL';
    pub const EXTENSIONS_APPROVAL_TIMEOUT: felt252 = 'EXTENSIONS_APPROVAL_TIMEOUT';
    pub const ALREADY_INITIALIZED: felt252 = 'ALREADY_INITIALIZED';
    pub const CHANGE_PENDING: felt252 = 'CHANGE_PENDING';
    pub const NOT_INITIALIZED: felt252 = 'NOT_INITIALIZED';
}


pub mod Constants {
    pub const MAX_EXTENSIONS_COUNT: u32 = 16;

    //bit shifters for extracting 20 bits of each method from the total of 160 (20*8)
    pub const BEFORE_INIT_POOL_BIT_SHIFT: u256 = 0x100000000000000000000000000000000000; //2^140
    pub const AFTER_INIT_POOL_BIT_SHIFT: u256 = 0x1000000000000000000000000000000; //2^120
    pub const BEFORE_SWAP_BIT_SHIFT: u256 = 0x10000000000000000000000000; //2^100
    pub const AFTER_SWAP_BIT_SHIFT: u256 = 0x100000000000000000000; //2^80
    pub const BEFORE_UPDATE_POSITION_BIT_SHIFT: u256 = 0x1000000000000000; //2^60
    pub const AFTER_UPDATE_POSITION_BIT_SHIFT: u256 = 0x10000000000; //2^40
    pub const BEFORE_COLLECT_FEES_BIT_SHIFT: u256 = 0x100000; //2^20
    pub const AFTER_COLLECT_FEES_BIT_SHIFT: u256 = 0x1; //2^0

    //bit shifters for extracting 4 bits for execution order of each method from the total of 32
    //(4*8)
    pub const BEFORE_INIT_POOL_QUEUE_BIT_SHIFT: u32 = 0x10000000; //2^28
    pub const AFTER_INIT_POOL_QUEUE_BIT_SHIFT: u32 = 0x1000000; //2^24
    pub const BEFORE_SWAP_QUEUE_BIT_SHIFT: u32 = 0x100000; //2^20
    pub const AFTER_SWAP_QUEUE_BIT_SHIFT: u32 = 0x10000; //2^16
    pub const BEFORE_UPDATE_POSITION_QUEUE_BIT_SHIFT: u32 = 0x1000; //2^12
    pub const AFTER_UPDATE_POSITION_QUEUE_BIT_SHIFT: u32 = 0x100; //2^8
    pub const BEFORE_COLLECT_FEES_QUEUE_BIT_SHIFT: u32 = 0x10; //2^4
    pub const AFTER_COLLECT_FEES_QUEUE_BIT_SHIFT: u32 = 0x1; //2^0
}
