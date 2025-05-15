use core::serde::Serde;
use core::keccak::compute_keccak_byte_array;
use starknet::{ContractAddress, get_contract_address};
use openzeppelin::token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};

use clt_ekubo::components::constants::Constants;
use clt_ekubo::components::math::Math;
use clt_ekubo::interfaces::clt_base::StoredPoolKey;

pub fn serialize<T, +Serde<T>>(t: @T) -> Array<felt252> {
    let mut result: Array<felt252> = ArrayTrait::new();
    Serde::serialize(t, ref result);
    result
}

pub fn deserialize<T, +Serde<T>>(mut data: Span<felt252>) -> T {
    Serde::deserialize(ref data).expect('DESERIALIZE_INPUT_FAILED')
}

pub fn pay(
    token_address: ContractAddress,
    payer: ContractAddress,
    recipient: ContractAddress,
    amount: u256,
) {
    let token = ERC20ABIDispatcher { contract_address: token_address };
    if payer == get_contract_address() {
        token.transfer(recipient, amount);
    } else {
        token.transferFrom(payer, recipient, amount);
    }
}

pub fn approve(token_address: ContractAddress, spender: ContractAddress, amount: u256) {
    ERC20ABIDispatcher { contract_address: token_address }.approve(spender, amount);
}

pub fn revoke_approval(token_address: ContractAddress, spender: ContractAddress) {
    let allowance = ERC20ABIDispatcher { contract_address: token_address }
        .allowance(get_contract_address(), spender);
    if allowance > 0 {
        approve(token_address, spender, 0);
    }
}

pub fn transfer_fee(
    pool_key: StoredPoolKey,
    percentage: u256,
    amount0: u256,
    amount1: u256,
    strategy_owner: ContractAddress,
) -> (u256, u256) {
    let (mut fee0, mut fee1): (u256, u256) = (0, 0);

    if percentage > 0 {
        if amount0 > 0 {
            fee0 = Math::mul_div(amount0, percentage, Constants::WAD);
            pay(pool_key.token0, get_contract_address(), strategy_owner, fee0);
        }

        if amount1 > 0 {
            fee1 = Math::mul_div(amount1, percentage, Constants::WAD);
            pay(pool_key.token1, get_contract_address(), strategy_owner, fee1);
        }
    }

    (fee0, fee1)
}


pub fn calculate_automation_fee(percentage: u256, amount0: u256, amount1: u256) -> (u256, u256) {
    let (mut fee0, mut fee1): (u256, u256) = (0, 0);

    if percentage > 0 {
        if amount0 > 0 {
            fee0 = Math::mul_div(amount0, percentage, Constants::WAD);
        }

        if amount1 > 0 {
            fee1 = Math::mul_div(amount1, percentage, Constants::WAD);
        }
    }

    (fee0, fee1)
}

pub fn keccak256(str: ByteArray) -> u256 {
    let k = compute_keccak_byte_array(@str);
    let k_inv = u256 {
        high: core::integer::u128_byte_reverse(k.low),
        low: core::integer::u128_byte_reverse(k.high),
    };
    k_inv
}

//sn_keccak for function selectors
//eg: keccak_hash("swap");
pub fn keccak_hash(str: ByteArray) -> felt252 {
    let mut k = keccak256(str);
    // Apply the bitmask for starknet keccak on felt252:
    k = k & 0x03FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
    k.try_into().unwrap()
}
