use clt_ekubo::types::pool_id::PoolId;

#[derive(Copy, Drop)]
pub struct InternalParams {
    pub strategy_id: PoolId,
    pub amount0_desired: u256,
    pub amount1_desired: u256,
    pub amount0_min: u256,
    pub amount1_min: u256,
}
