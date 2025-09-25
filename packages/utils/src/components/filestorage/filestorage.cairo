#[starknet::component]
pub(crate) mod FileStorage {
    use starknet::storage::{
        Map, StorageMapReadAccess, StorageMapWriteAccess, StoragePointerReadAccess,
        StoragePointerWriteAccess,
    };
    use starkware_utils::components::filestorage::interface::{
        FileMetadata, IFileStorage, OneKilobyte,
    };

    #[storage]
    pub struct Storage {
        pub metadata: Map<felt252, FileMetadata>,
        pub storage: Map<(felt252, u64), felt252>,
    }

    #[event]
    #[derive(Drop, PartialEq, starknet::Event)]
    pub enum Event {}


    #[embeddable_as(DepositImpl)]
    impl FileStorage<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of IFileStorage<ComponentState<TContractState>> {
        /// Create a new file with given metadata. Only callable once per file_id.
        fn create_file(
            ref self: ComponentState<TContractState>, file_id: felt252, metadata: FileMetadata,
        ) {}

        /// Write a 1KB chunk at the given offset (in KB) to the specified file.
        ///
        /// This function overwrites existing data at the given offset.
        /// If the offset is greater than or equal to the current file size,
        /// the function will revert with an error.
        ///
        /// To add data beyond the end of the file, use append functions instead.
        fn write_chunk(
            ref self: ComponentState<TContractState>,
            file_id: felt252,
            offset_kb: u32,
            chunk: OneKilobyte,
        ) {}

        /// Appends a 1KB chunk to the end of the file.
        fn append_1kb(
            ref self: ComponentState<TContractState>, file_id: felt252, chunk: OneKilobyte,
        ) {}

        // /// Appends 4 consecutive 1KB chunks to the end of the file.
        // fn append_4kb(ref self: TContractState, file_id: felt252, chunks: [OneKilobyte; 4]);

        // /// Appends 16 consecutive 1KB chunks to the end of the file.
        // fn append_16kb(ref self: TContractState, file_id: felt252, chunks: [OneKilobyte; 16]);

        /// Read a 1KB chunk from a specific offset(in KB).
        fn read_chunk(
            self: @ComponentState<TContractState>, file_id: felt252, offset_kb: u32,
        ) -> OneKilobyte {
            OneKilobyte { data: [0; 33] } // Placeholder implementation
        }

        /// Get metadata about the file (owner, size, timestamps, etc.)
        fn get_metadata(self: @ComponentState<TContractState>, file_id: felt252) -> FileMetadata {
            self.get_metadata(file_id)
        }

        /// Delete a file. Only callable by the owner. Does not erase chunks, only marks metadata.
        fn delete_file(ref self: ComponentState<TContractState>, file_id: felt252) {}
    }
}
