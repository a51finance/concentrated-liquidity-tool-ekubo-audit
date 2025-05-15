use core::poseidon::poseidon_hash_span;

pub fn hash_intent(intent: felt252) -> felt252 {
    poseidon_hash_span(array![intent].span())
}

pub fn ether(amount: u256) -> u256 {
    amount * 1_000_000_000_000_000_000
}

//sqrt(1/1) * 2**128
pub const SQRT_RATIO_1_1: u256 = 340282366920938463463374607431768211456;
