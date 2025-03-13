use snforge_std::cheatcodes::events::Events;
use starknet::ContractAddress;

pub fn is_emitted<T, impl TEvent: starknet::Event<T>, impl TDrop: Drop<T>>(
    self: @Events, expected_emitted_by: @ContractAddress, expected_event: @T,
) -> bool {
    let mut expected_keys = array![];
    let mut expected_data = array![];
    expected_event.append_keys_and_data(ref expected_keys, ref expected_data);

    let mut i = 0;
    let mut is_emitted = false;
    while i != self.events.len() {
        let (from, event) = self.events.at(i);

        if from == expected_emitted_by
            && event.keys == @expected_keys
            && event.data == @expected_data {
            is_emitted = true;
            break;
        }

        i += 1;
    }
    return is_emitted;
}


pub fn assert_number_of_events(actual: u32, expected: u32, message: ByteArray) {
    assert_eq!(
        actual, expected, "{actual} events were emitted instead of {expected}. Context: {message}",
    );
}

pub fn panic_with_event_details(expected_emitted_by: @ContractAddress, details: ByteArray) {
    let start = format!("Could not match expected event from address {:?}", *expected_emitted_by);
    panic!("{}: {}", start, details);
}

