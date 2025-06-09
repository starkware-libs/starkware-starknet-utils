use starkware_utils::trace::mock::{IMockTrace, MockTrace};

fn CONTRACT_STATE() -> MockTrace::ContractState {
    MockTrace::contract_state_for_testing()
}

#[test]
fn test_insert() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, 1000);
    assert_eq!(mock_trace.latest(), (100, 1000));

    mock_trace.insert(200, 2000);
    assert_eq!(mock_trace.latest(), (200, 2000));
    assert_eq!(mock_trace.length(), 2);

    mock_trace.insert(200, 500);
    assert_eq!(mock_trace.latest(), (200, 500));
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
#[should_panic(expected: "Empty trace")]
fn test_latest_empty_trace() {
    let mut mock_trace = CONTRACT_STATE();

    let _ = mock_trace.latest();
}

#[test]
fn test_latest() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, 1000);
    mock_trace.insert(200, 2000);

    let (key, value) = mock_trace.latest();
    assert_eq!(key, 200);
    assert_eq!(value, 2000);
}

#[test]
fn test_penultimate() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, 1000);
    mock_trace.insert(200, 2000);

    let (key, value) = mock_trace.penultimate();
    assert_eq!(key, 100);
    assert_eq!(value, 1000);
}

#[test]
#[should_panic(expected: "Penultimate does not exist")]
fn test_penultimate_not_exist() {
    let mut mock_trace = CONTRACT_STATE();

    let _ = mock_trace.penultimate();
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
#[should_panic(expected: "Empty trace")]
fn test_latest_mutable_empty_trace() {
    let mut mock_trace = CONTRACT_STATE();

    let _ = mock_trace.latest();
}

#[test]
fn test_latest_mutable() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, 1000);
    mock_trace.insert(200, 2000);

    let (key, latest) = mock_trace.latest_mutable();
    assert_eq!(key, 200);
    assert_eq!(latest, 2000);
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
fn test_n_latest() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, 1000);
    mock_trace.insert(200, 2000);
    mock_trace.insert(300, 3000);
    mock_trace.insert(400, 4000);
    mock_trace.insert(500, 5000);

    let span = mock_trace.n_latest(1);
    let expected = [(500, 5000)];
    assert_eq!(span, expected.span());

    let span = mock_trace.n_latest(3);
    let expected = [(300, 3000), (400, 4000), (500, 5000)];
    assert_eq!(span, expected.span());

    let span = mock_trace.n_latest(5);
    let expected = [(100, 1000), (200, 2000), (300, 3000), (400, 4000), (500, 5000)];
    assert_eq!(span, expected.span());
}

#[test]
#[should_panic(expected: "N is zero")]
fn test_n_latest_zero() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.n_latest(0);
}

#[test]
#[should_panic(expected: "N is too large")]
fn test_n_latest_too_large() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, 1000);
    mock_trace.insert(200, 2000);
    mock_trace.insert(300, 3000);
    mock_trace.insert(400, 4000);
    mock_trace.insert(500, 5000);
    mock_trace.insert(600, 6000);
    mock_trace.insert(700, 7000);
    mock_trace.insert(800, 8000);
    mock_trace.insert(900, 9000);
    mock_trace.insert(1000, 10000);
    mock_trace.insert(1100, 11000);
    mock_trace.insert(1200, 12000);
    mock_trace.insert(1300, 13000);
    mock_trace.insert(1400, 14000);
    mock_trace.insert(1500, 15000);

    mock_trace.n_latest(11);
}

#[test]
#[should_panic(expected: "Index out of bounds")]
fn test_n_latest_out_of_bounds() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.insert(100, 1000);
    mock_trace.insert(200, 2000);
    mock_trace.insert(300, 3000);
    mock_trace.insert(400, 4000);
    mock_trace.insert(500, 5000);

    mock_trace.n_latest(6);
}

#[test]
#[should_panic(expected: "Index out of bounds")]
fn test_n_latest_out_of_bounds_empty() {
    let mut mock_trace = CONTRACT_STATE();

    mock_trace.n_latest(1);
}
