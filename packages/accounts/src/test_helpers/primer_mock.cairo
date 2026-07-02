use starknet::ClassHash;

/// Stand-in for the real `Primer` (`packages/primer`), so the factory tests can deploy one under
/// the workspace toolchain. Its class hash therefore differs from the cemented on-chain hash; the
/// factory's `#[cfg(target: "test")]` `PRIMER_CLASS_HASH` must equal it (a guard test enforces
/// this).
#[starknet::interface]
pub trait IPrimerMock<TContractState> {
    fn set_class_hash(ref self: TContractState, new_class_hash: ClassHash);
}

#[starknet::contract]
pub mod PrimerTestMock {
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::syscalls::replace_class_syscall;
    use starknet::{ClassHash, ContractAddress, SyscallResultTrait, get_caller_address};
    use super::IPrimerMock;

    #[storage]
    struct Storage {
        deployer_address: ContractAddress,
    }

    #[constructor]
    pub fn constructor(ref self: ContractState) {
        self.deployer_address.write(get_caller_address());
    }

    #[abi(embed_v0)]
    impl PrimerMockImpl of IPrimerMock<ContractState> {
        fn set_class_hash(ref self: ContractState, new_class_hash: ClassHash) {
            assert(get_caller_address() == self.deployer_address.read(), 'INVALID_CALLER');
            replace_class_syscall(new_class_hash).unwrap_syscall();
        }
    }
}
