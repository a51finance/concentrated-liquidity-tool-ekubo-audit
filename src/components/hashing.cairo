pub mod Hashing {
    use core::poseidon::poseidon_hash_span;

    use clt_ekubo::components::util::serialize;
    use clt_ekubo::interfaces::clt_base::SwapOrderParams;

    pub fn hash_order(params: SwapOrderParams) -> felt252 {
        poseidon_hash_span(serialize::<SwapOrderParams>(@params).span())
    }

    pub fn compare_bytes(a: Span<felt252>, b: Span<felt252>) -> bool {
        poseidon_hash_span(a) == poseidon_hash_span(b)
    }
}
