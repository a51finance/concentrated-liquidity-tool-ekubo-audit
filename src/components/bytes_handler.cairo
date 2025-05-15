pub mod BytesHandler {
    use starknet::storage::{
        Map, StoragePointerWriteAccess, StoragePointerReadAccess, StoragePathEntry, StoragePath,
        Mutable,
    };

    #[starknet::storage_node]
    pub struct Bytes {
        count: u32, //the index upto which bytes are stored in felt252 type
        data: Map<u32, felt252> //byte w.r.t to it's index
    }

    pub fn read(bytes_storage: StoragePath<Bytes>) -> Span<felt252> {
        let mut bytes = array![];
        for index in 0..bytes_storage.count.read() {
            bytes.append(bytes_storage.data.entry(index).read());
        };
        bytes.span()
    }

    pub fn write(bytes_storage: StoragePath<Mutable<Bytes>>, bytes: Span<felt252>) {
        //store new bytes
        for index in 0..bytes.len() {
            let byte = *(bytes.get(index).unwrap().unbox());
            bytes_storage.data.entry(index).write(byte);
        };

        //clear additional bytes
        let stored_bytes_count = bytes_storage.count.read();
        let new_bytes_count = bytes.len();
        if stored_bytes_count > new_bytes_count {
            for index in (new_bytes_count - 1)..stored_bytes_count {
                bytes_storage.data.entry(index).write(0);
            }
        }

        //update bytes counter
        bytes_storage.count.write(new_bytes_count);
    }
}
