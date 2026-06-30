use snforge_std::cheatcodes::events::Event;
use starknet::ContractAddress;

/// Returns the index of the nth event whose first key equals the given selector.
pub fn find_event_index_by_selector(
    events: Span<(ContractAddress, Event)>, selector: felt252, n: usize,
) -> Option<usize> {
    let mut i = 0_usize;
    let mut seen = 0_usize;
    for (_, ev) in events {
        if ev.keys.len() > 0 && *ev.keys.at(0) == selector {
            if seen == n {
                return Option::Some(i);
            }
            seen += 1;
        }
        i += 1;
    }
    None
}

/// Returns a cloned copy of the first event emitted with the given selector (if any).
pub fn get_event_by_selector(
    events: Span<(ContractAddress, Event)>, selector: felt252,
) -> Option<@(ContractAddress, Event)> {
    match find_event_index_by_selector(:events, :selector, n: 0) {
        Option::Some(i) => {
            let (from, ev) = events.at(i);
            Option::Some(@(*from, ev.clone()))
        },
        None => None,
    }
}

/// Returns a cloned copy of the nth event emitted with the given selector (if any).
pub fn get_event_by_selector_n(
    events: Span<(ContractAddress, Event)>, selector: felt252, n: usize,
) -> Option<@(ContractAddress, Event)> {
    match find_event_index_by_selector(:events, :selector, :n) {
        Option::Some(i) => {
            let (from, ev) = events.at(i);
            Option::Some(@(*from, ev.clone()))
        },
        None => None,
    }
}
