use core::poseidon::poseidon_hash_span;
use ekubo::types::keys::PoolKey;

use clt_ekubo::components::util::serialize;

pub type PoolId = felt252;

pub trait PoolIdTrait {
    fn to_id(self: PoolKey) -> PoolId;
}

impl ToIdImpl of PoolIdTrait {
    fn to_id(self: PoolKey) -> PoolId {
        poseidon_hash_span(serialize::<PoolKey>(@self).span())
    }
}
