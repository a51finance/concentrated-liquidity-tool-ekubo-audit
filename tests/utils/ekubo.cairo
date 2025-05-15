use starknet::{ContractAddress, contract_address_const};
use ekubo::interfaces::mathlib::{dispatcher as ekubo_math, IMathLibDispatcherTrait};
use ekubo::components::clear::{IClearDispatcher, IClearDispatcherTrait};
use ekubo::interfaces::core::ICoreDispatcher;
use ekubo::interfaces::erc20::IERC20Dispatcher;
use ekubo::interfaces::router::{IRouterDispatcher, IRouterDispatcherTrait, RouteNode, TokenAmount};
use ekubo::types::keys::PoolKey;
use ekubo::types::i129::i129;
use ekubo::types::delta::Delta;

use clt_ekubo::components::math::Math;
use clt_ekubo::components::constants::Constants;
use crate::utils::erc20::{transfer};

pub const MIN_TICK: i129 = i129 { mag: 88368108, sign: true };
pub const MAX_TICK: i129 = i129 { mag: 88368108, sign: false };

pub fn ekubo_core() -> ICoreDispatcher {
    ICoreDispatcher {
        contract_address: contract_address_const::<
            0x00000005dd3D2F4429AF886cD1a3b08289DBcEa99A294197E9eB43b0e0325b4b,
        >(),
    }
}

pub fn router() -> IRouterDispatcher {
    IRouterDispatcher {
        contract_address: contract_address_const::<
            0x0199741822c2dc722f6f605204f35e56dbc23bceed54818168c4c49e4fb8737e,
        >(),
    }
}

pub fn get_ekubo_pool_key(
    tokenA: ContractAddress,
    tokenB: ContractAddress,
    extension: ContractAddress,
    fee: u8,
    tick_spacing: u128,
) -> PoolKey {
    let (token0, token1) = if tokenA < tokenB {
        (tokenA, tokenB)
    } else {
        (tokenB, tokenA)
    };

    let pool_key = PoolKey {
        token0: token0,
        token1: token1,
        //1% = (1 * 2**128) / 100
        fee: Math::mul_div(fee.into(), Constants::Q128, 100).try_into().unwrap(),
        tick_spacing,
        extension,
    };

    pool_key
}


pub fn swap(pool_key: PoolKey, amount: u256, zero_for_one: bool) -> Delta {
    let (token_in, token_out, sqrt_ratio_limit) = if zero_for_one {
        (pool_key.token0, pool_key.token1, ekubo_math().tick_to_sqrt_ratio(MIN_TICK))
    } else {
        (pool_key.token1, pool_key.token0, ekubo_math().tick_to_sqrt_ratio(MAX_TICK))
    };

    //transfer the input token amount to router
    transfer(token_in, router().contract_address, amount);

    //swap token
    let delta = router()
        .swap(
            RouteNode { pool_key, sqrt_ratio_limit, skip_ahead: 0 },
            TokenAmount {
                token: token_in, amount: i129 { sign: false, mag: amount.try_into().unwrap() },
            },
        );

    //clear and get the output token amount from router
    IClearDispatcher { contract_address: router().contract_address }
        .clear(IERC20Dispatcher { contract_address: token_out });
    delta
}
