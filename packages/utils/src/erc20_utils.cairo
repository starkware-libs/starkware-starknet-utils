use openzeppelin::token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use starknet::{ContractAddress, get_contract_address};


pub fn strict_transfer(token_address: ContractAddress, recipient: ContractAddress, amount: u256) {
    let _token = IERC20Dispatcher { contract_address: token_address };
    let this = get_contract_address();

    let self_balance_before = _token.balance_of(this);
    let recipient_balance_before = _token.balance_of(recipient);

    _token.transfer(:recipient, :amount);

    let self_balance_after = _token.balance_of(this);
    let recipient_balance_after = _token.balance_of(recipient);

    assert(self_balance_after == self_balance_before - amount, 'STRICT_TRANSFER_FAILED');
    assert(recipient_balance_after == recipient_balance_before + amount, 'STRICT_TRANSFER_FAILED');
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

    assert(sender_balance_after == sender_balance_before - amount, 'STRICT_TRANSFER_FROM_FAILED');
    assert(
        recipient_balance_after == recipient_balance_before + amount, 'STRICT_TRANSFER_FROM_FAILED',
    );
}
