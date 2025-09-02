#[starknet::interface]
pub trait IMockTrace<TContractState> {
    fn insert(ref self: TContractState, key: u64, value: u128);
    fn latest(self: @TContractState) -> (u64, u128);
    fn penultimate(self: @TContractState) -> (u64, u128);
    fn length(self: @TContractState) -> u64;
    fn is_empty(self: @TContractState) -> bool;
    fn latest_mutable(ref self: TContractState) -> (u64, u128);
    fn length_mutable(ref self: TContractState) -> u64;
    fn penultimate_mutable(ref self: TContractState) -> (u64, u128);
    fn is_empty_mutable(ref self: TContractState) -> bool;
    fn at(self: @TContractState, pos: u64) -> (u64, u128);
    fn at_mutable(ref self: TContractState, pos: u64) -> (u64, u128);
    fn antepenultimate(self: @TContractState) -> (u64, u128);
    fn antepenultimate_mutable(ref self: TContractState) -> (u64, u128);
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

        fn latest(self: @ContractState) -> (u64, u128) {
            match self.trace.latest() {
                Result::Ok((key, value)) => (key, value),
                Result::Err(e) => panic!("{}", e),
            }
        }

        fn penultimate(self: @ContractState) -> (u64, u128) {
            match self.trace.penultimate() {
                Result::Ok((key, value)) => (key, value),
                Result::Err(e) => panic!("{}", e),
            }
        }

        fn length(self: @ContractState) -> u64 {
            self.trace.length()
        }

        fn latest_mutable(ref self: ContractState) -> (u64, u128) {
            match self.trace.latest() {
                Result::Ok((key, value)) => (key, value),
                Result::Err(e) => panic!("{}", e),
            }
        }

        fn penultimate_mutable(ref self: ContractState) -> (u64, u128) {
            match self.trace.penultimate() {
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

        fn antepenultimate(self: @ContractState) -> (u64, u128) {
            match self.trace.antepenultimate() {
                Result::Ok((key, value)) => (key, value),
                Result::Err(e) => panic!("{}", e),
            }
        }

        fn antepenultimate_mutable(ref self: ContractState) -> (u64, u128) {
            match self.trace.antepenultimate() {
                Result::Ok((key, value)) => (key, value),
                Result::Err(e) => panic!("{}", e),
            }
        }
    }
}
