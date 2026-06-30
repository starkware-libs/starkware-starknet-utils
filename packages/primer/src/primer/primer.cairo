use starknet::ClassHash;
#[starknet::interface]
pub trait IPrimer<TContractState> {
    fn set_class_hash(ref self: TContractState, new_class_hash: ClassHash);
}

#[starknet::contract]
pub mod Primer {
    use contracts::primer::primer::IPrimer;
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use starknet::syscalls::replace_class_syscall;
    use starknet::{ClassHash, ContractAddress, SyscallResultTrait, get_caller_address};

    #[storage]
    struct Storage {
        deployer_address: ContractAddress,
    }

    #[constructor]
    pub fn constructor(ref self: ContractState) {
        self.deployer_address.write(get_caller_address());
    }

    #[abi(embed_v0)]
    impl PrimerImpl of IPrimer<ContractState> {
        /// Upgrades to the account contract with the given class hash.
        fn set_class_hash(ref self: ContractState, new_class_hash: ClassHash) {
            assert(get_caller_address() == self.deployer_address.read(), 'INVALID_CALLER');
            replace_class_syscall(new_class_hash).unwrap_syscall();
        }
    }
}
