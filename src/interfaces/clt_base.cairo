use core::traits::Into;
use starknet::ContractAddress;
use ekubo::types::bounds::Bounds;
use ekubo::types::i129::i129;
use ekubo::types::keys::PoolKey;

use clt_ekubo::components::user_positions::PositionData;
use clt_ekubo::types::pool_id::PoolId;

//struct to store pool key in contract storage. The default PoolKey type don't have starknet::Store
//that's why we need separate custom type to store PoolKey
#[derive(Copy, Drop, Serde, PartialEq, Hash, Debug, starknet::Store)]
pub struct StoredPoolKey {
    pub token0: ContractAddress,
    pub token1: ContractAddress,
    pub fee: u128,
    pub tick_spacing: u128,
    pub extension: ContractAddress,
}

//trait to convert PoolKey into StoredPoolKey
impl PoolKeyToStoredPoolKeyImpl of Into<PoolKey, StoredPoolKey> {
    fn into(self: PoolKey) -> StoredPoolKey {
        StoredPoolKey {
            token0: self.token0,
            token1: self.token1,
            fee: self.fee,
            tick_spacing: self.tick_spacing,
            extension: self.extension,
        }
    }
}

//trait to convert StoredPoolKey into PoolKey
impl StoredPooPoolKeyToPoolKeyImpl of Into<StoredPoolKey, PoolKey> {
    fn into(self: StoredPoolKey) -> PoolKey {
        PoolKey {
            token0: self.token0,
            token1: self.token1,
            fee: self.fee,
            tick_spacing: self.tick_spacing,
            extension: self.extension,
        }
    }
}

//a51 position key or bounds in term of ekubo
#[derive(Copy, Drop, Serde, PartialEq, Debug, starknet::Store)]
pub struct StrategyKey {
    pub tick_lower: i129,
    pub tick_upper: i129,
}

//trait to convert StrategyKey into Bounds
impl StrategyKeyToBoundsImpl of Into<StrategyKey, Bounds> {
    fn into(self: StrategyKey) -> Bounds {
        Bounds { lower: self.tick_lower, upper: self.tick_upper }
    }
}

//strategy account
#[derive(Copy, Drop, Serde, PartialEq, Debug, starknet::Store)]
pub struct Account {
    pub fee0: u256,
    pub fee1: u256,
    pub balance0: u256,
    pub balance1: u256,
    pub total_shares: u256,
    pub ekubo_liquidity: u128,
    pub fee_growth_inside_0_last_X128: u256,
    pub fee_growth_inside_1_last_X128: u256,
    pub automation_fee_owed0: u256,
    pub automation_fee_owed1: u256,
    pub last_saved_amount0: u128,
    pub last_saved_amount1: u128,
    pub is_holding_saved: bool // Flag to indicate saved state
}

//strategy data stored in contract storage
#[derive(Copy, Drop, Serde, PartialEq, Debug, starknet::Store)]
pub struct StrategyData {
    pub key: StrategyKey,
    pub pool_key: StoredPoolKey,
    pub owner: ContractAddress,
    pub is_compound: bool,
    pub is_private: bool,
    pub management_fee: u256,
    pub performance_fee: u256,
    pub account: Account,
    pub vault0: ContractAddress,
    pub vault1: ContractAddress,
}

//swap order data stored in contract
#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct SwapOrderData {
    pub key: StrategyKey,
    pub pool_key: StoredPoolKey,
    pub should_mint: bool,
    pub zero_for_one: bool,
    pub swap_amount: u256,
    pub min_amount: u256,
    pub deadline: u256,
    pub action_name: felt252,
}

//trait to convert SwapOrderParams into SwapOrderData
impl SwapOrderParamsToSwapOrderData of Into<SwapOrderParams, SwapOrderData> {
    fn into(self: SwapOrderParams) -> SwapOrderData {
        SwapOrderData {
            key: self.key,
            pool_key: self.pool_key.into(),
            should_mint: self.should_mint,
            zero_for_one: self.zero_for_one,
            swap_amount: self.swap_amount,
            min_amount: self.min_amount,
            deadline: self.deadline,
            action_name: self.action_name,
        }
    }
}

//trait to convert SwapOrderData into SwapOrderParams
impl SwapOrderDataToSwapOrderParams of Into<SwapOrderData, SwapOrderParams> {
    fn into(self: SwapOrderData) -> SwapOrderParams {
        SwapOrderParams {
            key: self.key,
            pool_key: self.pool_key.into(),
            should_mint: self.should_mint,
            zero_for_one: self.zero_for_one,
            swap_amount: self.swap_amount,
            min_amount: self.min_amount,
            deadline: self.deadline,
            action_name: self.action_name,
            module_status: array![].span() //set it explicitly
        }
    }
}

//create strategy params
#[derive(Copy, Drop, Serde)]
pub struct StrategyParams {
    pub pool_key: PoolKey,
    pub owner: ContractAddress,
    pub actions: Span<felt252>,
    pub tick_lower: i129,
    pub tick_upper: i129,
    pub initial_tick: i129,
    pub management_fee: u256,
    pub performance_fee: u256,
    pub is_compound: bool,
    pub is_private: bool,
    pub vault0: ContractAddress,
    pub vault1: ContractAddress,
}

//deposit into strategy params
#[derive(Copy, Drop, Serde)]
pub struct DepositParams {
    pub strategy_id: PoolId,
    pub amount0_desired: u256,
    pub amount1_desired: u256,
    pub amount0_min: u256,
    pub amount1_min: u256,
    pub recipient: ContractAddress,
}

//update strategy position params
#[derive(Copy, Drop, Serde)]
pub struct UpdatePositionParams {
    pub token_id: u256,
    pub amount0_desired: u256,
    pub amount1_desired: u256,
    pub amount0_min: u256,
    pub amount1_min: u256,
}

//withdraw from strategy position params
#[derive(Copy, Drop, Serde)]
pub struct WithdrawParams {
    pub token_id: u256,
    pub liquidity: u256,
    pub recipient: ContractAddress,
    pub amount0_min: u256,
    pub amount1_min: u256,
}

//claim fee from position params
#[derive(Copy, Drop, Serde)]
pub struct ClaimFeeParams {
    pub recipient: ContractAddress,
    pub token_id: u256,
}

//swap order params in shift liquidity
#[derive(Copy, Drop, Serde)]
pub struct SwapOrderParams {
    pub key: StrategyKey,
    pub pool_key: PoolKey,
    pub should_mint: bool,
    pub zero_for_one: bool,
    pub swap_amount: u256,
    pub min_amount: u256,
    pub deadline: u256,
    pub action_name: felt252,
    pub module_status: Span<felt252>,
}

//shift liquidity params
#[derive(Copy, Drop, Serde)]
pub struct ShiftLiquidityParams {
    pub is_manager_locked: bool,
    pub exchange_address: ContractAddress,
    pub order: SwapOrderParams,
    pub swap_data: Span<felt252>,
    pub swap_selector: felt252 //keccak256 hash of function selector
}

#[starknet::interface]
pub trait ICLTBase<TContractState> {
    //get governance fee handler address
    fn fee_handler(self: @TContractState) -> ContractAddress;
    //get strategy action status
    fn action_status(
        self: @TContractState, strategy_id: PoolId, action_name: felt252,
    ) -> Span<felt252>;
    //get strategy
    fn strategies(self: @TContractState, strategy_id: PoolId) -> (StrategyData, Span<felt252>);
    //get order
    fn orders(self: @TContractState, order_id: felt252) -> SwapOrderData;
    //get order module status
    fn order_module_status(self: @TContractState, order_id: felt252) -> Span<felt252>;
    //get user position data
    fn positions(self: @TContractState, token_id: u256) -> PositionData;
    //create new strategy
    fn create_strategy(ref self: TContractState, params: StrategyParams);
    //create new position in desired strategy
    fn deposit(ref self: TContractState, params: DepositParams) -> (u256, u256, u256, u256);
    //update liquidity of a specific position
    fn update_position_liquidity(
        ref self: TContractState, params: UpdatePositionParams,
    ) -> (u256, u256, u256);
    //withdraw liquidity from position
    fn withdraw(ref self: TContractState, params: WithdrawParams) -> (u256, u256);
    //claim fees accumulated on given position
    fn claim_position_fee(ref self: TContractState, params: ClaimFeeParams);
    //shift liquidity from one position to another
    fn shift_liquidity(ref self: TContractState, params: ShiftLiquidityParams);
    //store swap order which will be used in shift liquidity
    fn place_swap_order(ref self: TContractState, params: SwapOrderParams);

    //update strategy
    fn update_strategy_base(
        ref self: TContractState,
        strategy_id: PoolId,
        owner: ContractAddress,
        management_fee: u256,
        performance_fee: u256,
        actions: Span<felt252>,
    );
    //get strategy reserves
    fn get_strategy_reserves(
        ref self: TContractState, strategy_id: PoolId, is_manager_locked: bool,
    ) -> (u128, u256, u256);
    //get users accumulated fees
    fn get_user_fees(ref self: TContractState, token_id: u256) -> (u256, u256);
    //pause clt base
    fn pause(ref self: TContractState);
    //unpause cltbase
    fn unpause(ref self: TContractState);
}

//clt base errors
pub mod Errors {
    pub const NO_LIQUIDITY: felt252 = 'CLTBASE: no liquidity';
    pub const INVALID_INPUT: felt252 = 'CLTBASE: invalid input';
    pub const INVALID_SHARE: felt252 = 'CLTBASE: invalid share';
    pub const INVALID_CALLER: felt252 = 'CLTBASE: invalid caller';
    pub const ONLY_NON_COMPOUNDERS: felt252 = 'CLTBASE: only non compounders';
    pub const TRANSACTION_TOO_AGED: felt252 = 'CLTBASE: transaction too aged';
    pub const MINIMUM_AMOUNT_EXCEEDS: felt252 = 'CLTBASE: minimum amount exceeds';
    pub const OWNER_CANNOT_BE_ZERO_ADDRESS: felt252 = 'CLTBASE: owner cannot be zero';
    pub const NOT_APPROVED: felt252 = 'CLTBASE: not approved';
    pub const NOT_AUTHORIZED: felt252 = 'CLTBASE: not authorized';
    pub const EMPTY_STRATEGY: felt252 = 'CLTBASE: empty strategy';
    pub const INVALID_AUTOMATION_FEE: felt252 = 'CLTBASE: invalid automation fee';
}
