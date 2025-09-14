use starkware_utils::trace::mock::{IMockTrace, MockTrace};

fn CONTRACT_STATE() -> MockTrace::ContractState {
    MockTrace::contract_state_for_testing()
}

#[test]
fn test_insert() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, 1000);
    assert_eq!(mock_trace.last(), (100, 1000));

    mock_trace.insert(200, 2000);
    assert_eq!(mock_trace.last(), (200, 2000));
    assert_eq!(mock_trace.length(), 2);

    mock_trace.insert(200, 500);
    assert_eq!(mock_trace.last(), (200, 500));
    assert_eq!(mock_trace.length(), 2);
}

#[test]
#[should_panic(expected: "Unordered insertion")]
fn test_insert_unordered_insertion() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(200, 2000);
    mock_trace.insert(100, 1000); // This should panic
}

#[test]
#[should_panic(expected: "Index out of bounds")]
fn test_last_empty_trace() {
    let mut mock_trace = CONTRACT_STATE();

    let _ = mock_trace.last();
}

#[test]
fn test_last() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, 1000);
    mock_trace.insert(200, 2000);

    let (key, value) = mock_trace.last();
    assert_eq!(key, 200);
    assert_eq!(value, 2000);
}

#[test]
fn test_second_last() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, 1000);
    mock_trace.insert(200, 2000);

    let (key, value) = mock_trace.second_last();
    assert_eq!(key, 100);
    assert_eq!(value, 1000);
}

#[test]
#[should_panic(expected: "Index out of bounds")]
fn test_second_last_not_exist() {
    let mut mock_trace = CONTRACT_STATE();

    let _ = mock_trace.second_last();
}

#[test]
fn test_second_last_mutable() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, 1000);
    mock_trace.insert(200, 2000);

    let (key, value) = mock_trace.second_last_mutable();
    assert_eq!(key, 100);
    assert_eq!(value, 1000);
}

#[test]
#[should_panic(expected: "Index out of bounds")]
fn test_second_last_mutable_not_exist() {
    let mut mock_trace = CONTRACT_STATE();

    let _ = mock_trace.second_last_mutable();
}

#[test]
fn test_length() {
    let mut mock_trace = CONTRACT_STATE();

    assert_eq!(mock_trace.length(), 0);

    mock_trace.insert(100, 1000);
    assert_eq!(mock_trace.length(), 1);

    mock_trace.insert(200, 2000);
    assert_eq!(mock_trace.length(), 2);
}

#[test]
#[should_panic(expected: "Index out of bounds")]
fn test_last_mutable_empty_trace() {
    let mut mock_trace = CONTRACT_STATE();

    let _ = mock_trace.last();
}

#[test]
fn test_last_mutable() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, 1000);
    mock_trace.insert(200, 2000);

    let (key, last) = mock_trace.last_mutable();
    assert_eq!(key, 200);
    assert_eq!(last, 2000);
}

#[test]
fn test_length_mutable() {
    let mut mock_trace = CONTRACT_STATE();

    assert_eq!(mock_trace.length_mutable(), 0);

    mock_trace.insert(100, 1000);
    assert_eq!(mock_trace.length_mutable(), 1);

    mock_trace.insert(200, 2000);
    assert_eq!(mock_trace.length_mutable(), 2);
}

#[test]
fn test_is_empty() {
    let mut mock_trace = CONTRACT_STATE();

    assert!(mock_trace.is_empty());

    mock_trace.insert(100, 1000);

    assert!(!mock_trace.is_empty());
}

#[test]
fn test_at() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, 1000);
    mock_trace.insert(200, 2000);

    let (key, value) = mock_trace.at(0);
    assert_eq!(key, 100);
    assert_eq!(value, 1000);

    let (key, value) = mock_trace.at(1);
    assert_eq!(key, 200);
    assert_eq!(value, 2000);
}

#[test]
#[should_panic(expected: "Index out of bounds")]
fn test_at_out_of_bounds() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.at(0);
}

#[test]
fn test_at_mutable() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, 1000);
    mock_trace.insert(200, 2000);

    let (key, value) = mock_trace.at_mutable(0);
    assert_eq!(key, 100);
    assert_eq!(value, 1000);

    let (key, value) = mock_trace.at_mutable(1);
    assert_eq!(key, 200);
    assert_eq!(value, 2000);
}

#[test]
#[should_panic(expected: "Index out of bounds")]
fn test_at_mutable_out_of_bounds() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.at_mutable(0);
}

#[test]
fn test_third_last() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, 1000);
    mock_trace.insert(200, 2000);
    mock_trace.insert(300, 3000);

    let (key, value) = mock_trace.third_last();
    assert_eq!(key, 100);
    assert_eq!(value, 1000);
}

#[test]
#[should_panic(expected: "Index out of bounds")]
fn test_third_last_not_exist() {
    let mut mock_trace = CONTRACT_STATE();

    let _ = mock_trace.third_last();
}

#[test]
fn test_third_last_mutable() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, 1000);
    mock_trace.insert(200, 2000);
    mock_trace.insert(300, 3000);

    let (key, value) = mock_trace.third_last_mutable();
    assert_eq!(key, 100);
    assert_eq!(value, 1000);
}

#[test]
#[should_panic(expected: "Index out of bounds")]
fn test_third_last_mutable_not_exist() {
    let mut mock_trace = CONTRACT_STATE();

    let _ = mock_trace.third_last_mutable();
}
