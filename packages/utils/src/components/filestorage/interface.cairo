use starknet::ContractAddress;
#[starknet::interface]
pub trait IFileStorage<TContractState> {
    /// Create a new file with given metadata. Only callable once per file_id.
    fn create_file(ref self: TContractState, file_id: felt252, metadata: FileMetadata);

    /// Write a 1KB chunk at the given offset (in KB) to the specified file.
    ///
    /// This function overwrites existing data at the given offset.
    /// If the offset is greater than or equal to the current file size,
    /// the function will revert with an error.
    ///
    /// To add data beyond the end of the file, use append functions instead.
    fn write_chunk(ref self: TContractState, file_id: felt252, offset_kb: u32, chunk: OneKilobyte);

    /// Appends a 1KB chunk to the end of the file.
    fn append_1kb(ref self: TContractState, file_id: felt252, chunk: OneKilobyte);

    // /// Appends 4 consecutive 1KB chunks to the end of the file.
    // fn append_4kb(ref self: TContractState, file_id: felt252, chunks: [OneKilobyte; 4]);

    // /// Appends 16 consecutive 1KB chunks to the end of the file.
    // fn append_16kb(ref self: TContractState, file_id: felt252, chunks: [OneKilobyte; 16]);

    /// Read a 1KB chunk from a specific offset(in KB).
    fn read_chunk(self: @TContractState, file_id: felt252, offset_kb: u32) -> OneKilobyte;

    /// Get metadata about the file (owner, size, timestamps, etc.)
    fn get_metadata(self: @TContractState, file_id: felt252) -> FileMetadata;

    /// Delete a file. Only callable by the owner. Does not erase chunks, only marks metadata.
    fn delete_file(ref self: TContractState, file_id: felt252);
}

#[derive(Drop, Copy, Serde)]
pub struct OneKilobyte {
    pub data: [felt252; 33] // 1KB chunk represented as an array of felt252
}

impl DefaultOneKilobyte of Default<OneKilobyte> {
    fn default() -> OneKilobyte {
        OneKilobyte { data: [0; 33] }
    }
}

impl SerdeOneKilobyte of Serde<[felt252; 33]> {
    fn serialize(self: @[felt252; 33], ref output: Array<felt252>) {
        for element in self.span() {
            output.append(*element);
        }
    }

    fn deserialize(ref serialized: Span<felt252>) -> Option<[felt252; 33]> {
        /// todo : impl.
        if serialized.len() != 33 {
            return Option::None;
        }
        let data = serialized.multi_pop_front::<33>().unwrap().unbox();
        Option::Some(data)
    }
}


#[derive(Debug, PartialEq, Drop, Serde, Copy, starknet::Store)]
pub struct FileMetadata {
    /// File size in kilobytes (number of 1KB chunks)
    pub size_in_kb: u32,
    /// Block number when the file was created
    pub created_at_block: u64,
    /// Block number of the last modification
    pub modified_at_block: u64,
    /// Address that last modified the file
    pub last_modifier: ContractAddress,
}
