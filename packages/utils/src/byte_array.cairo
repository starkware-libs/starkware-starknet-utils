pub fn short_string_to_byte_array(felt: felt252) -> ByteArray {
    let mut ba = Default::default();
    let mut felt_num: u256 = felt.into();
    while (felt_num != 0) {
        let byte: u8 = (felt_num % 256_u256).try_into().unwrap();
        ba.append_byte(byte);
        felt_num = felt_num / 256_u256;
    }
    ba.rev()
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_short_string_to_byte_array() {
        let felt = 'This is a test of 31 characters';
        let ba = short_string_to_byte_array(felt);
        assert_eq!(ba, "This is a test of 31 characters");
    }
}
