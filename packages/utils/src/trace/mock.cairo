#[starknet::interface]
pub trait IMockTrace<TContractState> {
    fn insert(ref self: TContractState, key: u64, value: u128);
    fn last(self: @TContractState) -> (u64, u128);
    fn second_last(self: @TContractState) -> (u64, u128);
    fn length(self: @TContractState) -> u64;
    fn is_empty(self: @TContractState) -> bool;
    fn last_mutable(ref self: TContractState) -> (u64, u128);
    fn length_mutable(ref self: TContractState) -> u64;
    fn second_last_mutable(ref self: TContractState) -> (u64, u128);
    fn is_empty_mutable(ref self: TContractState) -> bool;
    fn at(self: @TContractState, pos: u64) -> (u64, u128);
    fn at_mutable(ref self: TContractState, pos: u64) -> (u64, u128);
    fn third_last(self: @TContractState) -> (u64, u128);
    fn third_last_mutable(ref self: TContractState) -> (u64, u128);
}

#[starknet::contract]
pub mod MockTrace {
    use starkware_utils::trace::trace::{MutableTraceTrait, Trace, TraceTrait};

    #[storage]
    struct Storage {
        trace: Trace,
    }

    #[abi(embed_v0)]
    impl MockTraceImpl of super::IMockTrace<ContractState> {
        fn insert(ref self: ContractState, key: u64, value: u128) {
            self.trace.insert(:key, :value)
        }

        fn last(self: @ContractState) -> (u64, u128) {
            match self.trace.last() {
                Result::Ok((key, value)) => (key, value),
                Result::Err(e) => panic!("{}", e),
            }
        }

        fn second_last(self: @ContractState) -> (u64, u128) {
            match self.trace.second_last() {
                Result::Ok((key, value)) => (key, value),
                Result::Err(e) => panic!("{}", e),
            }
        }

        fn length(self: @ContractState) -> u64 {
            self.trace.length()
        }

        fn last_mutable(ref self: ContractState) -> (u64, u128) {
            match self.trace.last() {
                Result::Ok((key, value)) => (key, value),
                Result::Err(e) => panic!("{}", e),
            }
        }

        fn second_last_mutable(ref self: ContractState) -> (u64, u128) {
            match self.trace.second_last() {
                Result::Ok((key, value)) => (key, value),
                Result::Err(e) => panic!("{}", e),
            }
        }

        fn length_mutable(ref self: ContractState) -> u64 {
            self.trace.length()
        }

        fn is_empty(self: @ContractState) -> bool {
            self.trace.is_empty()
        }

        fn is_empty_mutable(ref self: ContractState) -> bool {
            self.trace.is_empty()
        }

        fn at(self: @ContractState, pos: u64) -> (u64, u128) {
            self.trace.at(:pos)
        }

        fn at_mutable(ref self: ContractState, pos: u64) -> (u64, u128) {
            self.trace.at(:pos)
        }

        fn third_last(self: @ContractState) -> (u64, u128) {
            match self.trace.third_last() {
                Result::Ok((key, value)) => (key, value),
                Result::Err(e) => panic!("{}", e),
            }
        }

        fn third_last_mutable(ref self: ContractState) -> (u64, u128) {
            match self.trace.third_last() {
                Result::Ok((key, value)) => (key, value),
                Result::Err(e) => panic!("{}", e),
            }
        }
    }
}
