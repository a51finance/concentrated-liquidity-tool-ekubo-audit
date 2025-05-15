pub mod CoreActions {
    use core::num::traits::Zero;
    use starknet::{ContractAddress, SyscallResultTrait, get_block_timestamp, get_contract_address};
    use starknet::syscalls::call_contract_syscall;
    use openzeppelin::token::erc20::{ERC20ABIDispatcher, ERC20ABIDispatcherTrait};
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, UpdatePositionParameters};
    use ekubo::types::bounds::Bounds;
    use ekubo::types::delta::Delta;
    use ekubo::types::i129::i129;
    use ekubo::types::keys::{PoolKey, SavedBalanceKey};


    use clt_ekubo::components::hashing::Hashing;
    use clt_ekubo::components::liquidity_amounts::LiquidityAmounts;
    use clt_ekubo::components::util::revoke_approval;
    use clt_ekubo::interfaces::clt_base::{StrategyData, SwapOrderParams, ShiftLiquidityParams};
    use clt_ekubo::types::pool_id::PoolIdTrait;


    pub fn collect_pending_fees(
        core: ICoreDispatcher, pool_key: PoolKey, salt: felt252, bounds: Bounds,
    ) -> (u256, u256) {
        let delta = core.collect_fees(pool_key, salt, bounds);

        let (mut collect0, mut collect1): (u256, u256) = (0, 0);

        if delta.amount0.is_non_zero() && delta.amount0.sign {
            collect0 = delta.amount0.mag.into();
            core.withdraw(pool_key.token0, get_contract_address(), delta.amount0.mag);
        }

        if delta.amount1.is_non_zero() && delta.amount1.sign {
            collect1 = delta.amount1.mag.into();
            core.withdraw(pool_key.token1, get_contract_address(), delta.amount1.mag);
        }
        (collect0, collect1)
    }

    pub fn mint_liquidity(
        core: ICoreDispatcher,
        pool_key: PoolKey,
        bounds: Bounds,
        amount0_desired: u256,
        amount1_desired: u256,
    ) -> (u128, u256, u256) {
        let liquidity = LiquidityAmounts::get_liquidity_for_amounts(
            core.get_pool_price(pool_key).sqrt_ratio, bounds, amount0_desired, amount1_desired,
        );

        let (mut amount0, mut amount1): (u256, u256) = (0, 0);

        if liquidity > 0 {
            let delta = _update_position(
                core, pool_key, bounds, i129 { sign: false, mag: liquidity },
            );

            if delta.amount0.is_non_zero() && delta.amount0.sign == false {
                amount0 = delta.amount0.mag.into();
                _settle(core, pool_key.token0, delta.amount0.mag.into());
            }

            if delta.amount1.is_non_zero() && delta.amount1.sign == false {
                amount1 = delta.amount1.mag.into();
                _settle(core, pool_key.token1, delta.amount1.mag.into());
            }
        }

        (liquidity, amount0, amount1)
    }

    pub fn burn_liquidity(
        core: ICoreDispatcher, pool_key: PoolKey, bounds: Bounds, strategy_liquidity: u128,
    ) -> (u128, u128, u256, u256) {
        let (mut amount0, mut amount1, mut fee0, mut fee1): (u128, u128, u256, u256) = (0, 0, 0, 0);

        if strategy_liquidity > 0 {
            //in-order to remove complete liquidity the fees must be collected before
            let (_fee0, _fee1) = collect_pending_fees(core, pool_key, 0, bounds);
            fee0 = _fee0;
            fee1 = _fee1;

            let delta = _update_position(
                core, pool_key, bounds, i129 { sign: true, mag: strategy_liquidity },
            );

            if delta.amount0.is_non_zero() && delta.amount0.sign {
                amount0 = delta.amount0.mag.into();
                core.withdraw(pool_key.token0, get_contract_address(), delta.amount0.mag);
            }

            if delta.amount1.is_non_zero() && delta.amount1.sign {
                amount1 = delta.amount1.mag.into();
                core.withdraw(pool_key.token1, get_contract_address(), delta.amount1.mag);
            }
        }

        (amount0, amount1, fee0, fee1)
    }


    /// This is useful in contexts like `after_swap` where immediate withdrawal might conflict with
    /// swap accounting.
    /// Returns the saved amounts (u128) for token0, token1, and the collected fees (u256) for
    /// fee0,
    /// fee1.
    pub fn burn_liquidity_and_save(
        core: ICoreDispatcher, pool_key: PoolKey, bounds: Bounds, strategy_liquidity: u128,
    ) -> (u128, u128, u256, u256) { // Return type changed to u128 for saved amounts
        let (mut amount0_saved, mut amount1_saved): (u128, u128) = (0, 0);
        let (mut fee0, mut fee1): (u256, u256) = (0, 0);
        let salt: felt252 = pool_key.to_id().into();
        let self_address = get_contract_address();

        if strategy_liquidity > 0 {
            // Collect fees first. These are withdrawn immediately within collect_pending_fees.
            let (_fee0, _fee1) = collect_pending_fees(core, pool_key, salt, bounds);
            fee0 = _fee0;
            fee1 = _fee1;

            // Update the position to remove liquidity, generating positive deltas.
            let delta = _update_position(
                core, pool_key, bounds, i129 { sign: true, mag: strategy_liquidity },
            );

            // If there's a positive delta for token0, save it instead of withdrawing.
            if delta.amount0.is_non_zero() && delta.amount0.sign {
                amount0_saved = delta.amount0.mag; // Already u128
                let key0 = SavedBalanceKey { owner: self_address, token: pool_key.token0, salt };
                core.save(key0, amount0_saved);
            }

            // If there's a positive delta for token1, save it instead of withdrawing.
            if delta.amount1.is_non_zero() && delta.amount1.sign {
                amount1_saved = delta.amount1.mag; // Already u128
                let key1 = SavedBalanceKey { owner: self_address, token: pool_key.token1, salt };
                core.save(key1, amount1_saved);
            }
        }

        (amount0_saved, amount1_saved, fee0, fee1)
    }


    /// Loads previously saved token balances (deltas) and withdraws them.
    /// This should be called in a separate transaction after `burn_liquidity_and_save`.
    pub fn load_and_withdraw_saved_liquidity(
        core: ICoreDispatcher, pool_key: PoolKey, amount0_saved: u128, amount1_saved: u128,
    ) -> (u128, u128, u256, u256) {
        let salt: felt252 = pool_key.to_id().into();
        let self_address = get_contract_address();

        if amount0_saved > 0 {
            core.load(pool_key.token0, salt, amount0_saved);
            core.withdraw(pool_key.token0, self_address, amount0_saved);
        }

        if amount1_saved > 0 {
            core.load(pool_key.token1, salt, amount1_saved);
            core.withdraw(pool_key.token1, self_address, amount1_saved);
        }
        (0, 0, 0, 0)
    }


    pub fn swap_token(
        strategy: StrategyData, orders: SwapOrderParams, params: ShiftLiquidityParams,
    ) -> (u256, u256) {
        assert(get_block_timestamp().into() <= orders.deadline, 'Transaction too Aged');
        assert(params.order.zero_for_one == orders.zero_for_one, 'Direction mismatch');
        assert(params.order.should_mint == orders.should_mint, 'Mint flag mismatch');

        assert(
            Hashing::compare_bytes(params.order.module_status, orders.module_status),
            'Module status mismatch',
        );
        //Check it it should be &&

        assert(
            params.order.swap_amount == orders.swap_amount
                || params.order.min_amount == orders.min_amount,
            'Swap or min amount mismatch',
        );

        assert(params.order.pool_key.token0 == orders.pool_key.token0, 'Token0 mismatch');
        assert(params.order.pool_key.token1 == orders.pool_key.token1, 'Token1 mismatch');
        // Check it
        assert(
            params.order.key.tick_lower == orders.key.tick_lower
                && params.order.key.tick_upper == orders.key.tick_upper,
            'Tick range mismatch',
        );

        let (src_token, dst_token) = if params.order.zero_for_one {
            (
                ERC20ABIDispatcher { contract_address: params.order.pool_key.token0 },
                ERC20ABIDispatcher { contract_address: params.order.pool_key.token1 },
            )
        } else {
            (
                ERC20ABIDispatcher { contract_address: params.order.pool_key.token1 },
                ERC20ABIDispatcher { contract_address: params.order.pool_key.token0 },
            )
        };

        let token_in_bal_before = src_token.balance_of(get_contract_address());
        let token_out_bal_before = dst_token.balance_of(get_contract_address());
        let share_supply_before = strategy.account.total_shares;

        assert(share_supply_before == strategy.account.total_shares, 'Mismatch shares');

        src_token.approve(params.exchange_address, params.order.swap_amount);

        call_contract_syscall(params.exchange_address, params.swap_selector, params.swap_data)
            .unwrap_syscall();
        revoke_approval(src_token.contract_address, get_contract_address());

        let token_in_bal_after = src_token.balance_of(get_contract_address());
        let token_out_bal_after = dst_token.balance_of(get_contract_address());

        let amount_in = token_in_bal_before - token_in_bal_after;
        let amount_out = token_out_bal_after - token_out_bal_before;

        assert(amount_out >= params.order.min_amount, 'Insufficient output amount');

        (amount_in, amount_out)
    }

    pub fn amounts_direction(
        zero_for_one: bool,
        amount0_received: u256,
        amount1_received: u256,
        amount0: u256,
        amount1: u256,
    ) -> (u256, u256) {
        if zero_for_one {
            return (amount0_received - amount0, amount1_received + amount1);
        }
        (amount0_received + amount0, amount1_received - amount1)
    }

    fn _update_position(
        core: ICoreDispatcher, pool_key: PoolKey, bounds: Bounds, liquidity_delta: i129,
    ) -> Delta {
        core
            .update_position(
                pool_key,
                UpdatePositionParameters { salt: pool_key.to_id().into(), bounds, liquidity_delta },
            )
    }

    //transfer tokens to core
    fn _settle(core: ICoreDispatcher, token_address: ContractAddress, amount: u256) {
        let token = ERC20ABIDispatcher { contract_address: token_address };
        let allowance = token.allowance(get_contract_address(), core.contract_address);
        if allowance < amount {
            token.approve(core.contract_address, amount);
        }
        core.pay(token_address);
    }
}
