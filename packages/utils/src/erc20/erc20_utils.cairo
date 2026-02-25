use openzeppelin::interfaces::token::erc20::{IERC20Dispatcher, IERC20DispatcherTrait};
use starknet::{ContractAddress, get_contract_address};
use starkware_utils::erc20::erc20_errors::Erc20Error;
use starkware_utils::errors::ErrorDisplay;


pub fn strict_transfer(token_address: ContractAddress, recipient: ContractAddress, amount: u256) {
    let _token = IERC20Dispatcher { contract_address: token_address };
    let this = get_contract_address();

    let self_balance_before = _token.balance_of(this);
    let recipient_balance_before = _token.balance_of(recipient);

    _token.transfer(:recipient, :amount);

    let self_balance_after = _token.balance_of(this);
    let recipient_balance_after = _token.balance_of(recipient);

    assert!(
        self_balance_after == self_balance_before - amount,
        "{}",
        Erc20Error::STRICT_TRANSFER_FAILED,
    );
    assert!(
        recipient_balance_after == recipient_balance_before + amount,
        "{}",
        Erc20Error::STRICT_TRANSFER_FAILED,
    );
}

pub fn strict_transfer_from(
    token_address: ContractAddress,
    sender: ContractAddress,
    recipient: ContractAddress,
    amount: u256,
) {
    let _token = IERC20Dispatcher { contract_address: token_address };

    let sender_balance_before = _token.balance_of(sender);
    let recipient_balance_before = _token.balance_of(recipient);

    _token.transfer_from(:sender, :recipient, :amount);

    let sender_balance_after = _token.balance_of(sender);
    let recipient_balance_after = _token.balance_of(recipient);

    assert!(
        sender_balance_after == sender_balance_before - amount,
        "{}",
        Erc20Error::STRICT_TRANSFER_FROM_FAILED,
    );
    assert!(
        recipient_balance_after == recipient_balance_before + amount,
        "{}",
        Erc20Error::STRICT_TRANSFER_FROM_FAILED,
    );
}

/// This trait is deprecated (adding methods to existing dispatchers is not a good practice) and
/// will be removed in the future.
/// Use the checked_transfer_from and checked_transfer functions instead.
#[generate_trait]
pub impl CheckedIERC20DispatcherImpl of CheckedIERC20DispatcherTrait {
    fn checked_transfer_from(
        self: IERC20Dispatcher, sender: ContractAddress, recipient: ContractAddress, amount: u256,
    ) {
        checked_transfer_from(
            token_address: self.contract_address,
            sender: sender,
            recipient: recipient,
            amount: amount,
        );
    }

    fn checked_transfer(self: IERC20Dispatcher, recipient: ContractAddress, amount: u256) {
        checked_transfer(
            token_address: self.contract_address, recipient: recipient, amount: amount,
        );
    }
}

pub fn checked_transfer_from(
    token_address: ContractAddress,
    sender: ContractAddress,
    recipient: ContractAddress,
    amount: u256,
) {
    let token = IERC20Dispatcher { contract_address: token_address };
    assert!(amount <= token.balance_of(account: sender), "{}", Erc20Error::INSUFFICIENT_BALANCE);
    assert!(
        amount <= token.allowance(owner: sender, spender: get_contract_address()),
        "{}",
        Erc20Error::INSUFFICIENT_ALLOWANCE,
    );
    let success = token.transfer_from(:sender, :recipient, :amount);
    assert!(success, "{}", Erc20Error::TRANSFER_FAILED);
}

pub fn checked_transfer(token_address: ContractAddress, recipient: ContractAddress, amount: u256) {
    let token = IERC20Dispatcher { contract_address: token_address };
    assert!(
        amount <= token.balance_of(account: get_contract_address()),
        "{}",
        Erc20Error::INSUFFICIENT_BALANCE,
    );
    let success = token.transfer(:recipient, :amount);
    assert!(success, "{}", Erc20Error::TRANSFER_FAILED);
}
