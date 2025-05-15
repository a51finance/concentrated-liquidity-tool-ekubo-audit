use clt_ekubo::types::pool_id::PoolId;

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct PositionData {
    pub strategy_id: PoolId,
    pub liquidity_share: u256,
    pub tokens_owed0: u128,
    pub tokens_owed1: u128,
    pub fee_growth_inside_0_last_X128: u256,
    pub fee_growth_inside_1_last_X128: u256,
}

#[starknet::interface]
pub trait IUserPositions<TContractState> {
    fn get_position(self: @TContractState, token_id: u256) -> PositionData;
}

#[starknet::component]
pub mod UserPositionsComponent {
    use starknet::storage::{
        Map, StoragePointerWriteAccess, StoragePointerReadAccess, StoragePathEntry, StoragePath,
        Mutable,
    };
    use clt_ekubo::components::constants::Constants::Q128;
    use clt_ekubo::components::math::Math;
    use clt_ekubo::interfaces::clt_base::StrategyData;
    use super::{IUserPositions, PositionData};

    #[storage]
    pub struct Storage {
        positions: Map<u256, PositionData>,
    }

    #[embeddable_as(UserPositionsImpl)]
    pub impl UserPositions<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of IUserPositions<ComponentState<TContractState>> {
        fn get_position(self: @ComponentState<TContractState>, token_id: u256) -> PositionData {
            self.positions.entry(token_id).read()
        }
    }

    #[generate_trait]
    pub impl InternalImpl<
        TContractState, +HasComponent<TContractState>, +Drop<TContractState>,
    > of InternalTrait<TContractState> {
        fn _set_position(
            ref self: ComponentState<TContractState>, token_id: u256, position: PositionData,
        ) {
            self.positions.entry(token_id).write(position);
        }

        fn _update_liquidity(
            ref self: ComponentState<TContractState>, token_id: u256, share: u256,
        ) {
            let mut position = self.get_position(token_id);
            position.liquidity_share += share;
            self._set_position(token_id, position);
        }

        fn _update_position(
            ref self: ComponentState<TContractState>,
            token_id: u256,
            fee_growth_inside_0_last_X128: u256,
            fee_growth_inside_1_last_X128: u256,
        ) {
            let mut position = self.get_position(token_id);
            position
                .tokens_owed0 +=
                    Math::mul_div(
                        fee_growth_inside_0_last_X128 - position.fee_growth_inside_0_last_X128,
                        position.liquidity_share,
                        Q128,
                    )
                .try_into()
                .unwrap();
            position
                .tokens_owed1 +=
                    Math::mul_div(
                        fee_growth_inside_1_last_X128 - position.fee_growth_inside_1_last_X128,
                        position.liquidity_share,
                        Q128,
                    )
                .try_into()
                .unwrap();
            position.fee_growth_inside_0_last_X128 = fee_growth_inside_0_last_X128;
            position.fee_growth_inside_1_last_X128 = fee_growth_inside_1_last_X128;
            self._set_position(token_id, position);
        }

        fn _claim_fee_for_non_compounders(
            ref self: ComponentState<TContractState>,
            token_id: u256,
            strategy_storage: StoragePath<Mutable<StrategyData>>,
        ) -> (u128, u128, StrategyData, PositionData) {
            let mut strategy = strategy_storage.read();
            let mut position = self.get_position(token_id);

            let (fee_growth_inside_0_last_X128, fee_growth_inside_1_last_X128) = (
                strategy.account.fee_growth_inside_0_last_X128,
                strategy.account.fee_growth_inside_1_last_X128,
            );

            let total0 = position.tokens_owed0
                + Math::mul_div(
                    fee_growth_inside_0_last_X128 - position.fee_growth_inside_0_last_X128,
                    position.liquidity_share,
                    Q128,
                )
                    .try_into()
                    .unwrap();
            let total1 = position.tokens_owed1
                + Math::mul_div(
                    fee_growth_inside_1_last_X128 - position.fee_growth_inside_1_last_X128,
                    position.liquidity_share,
                    Q128,
                )
                    .try_into()
                    .unwrap();

            position.fee_growth_inside_0_last_X128 = fee_growth_inside_0_last_X128;
            position.fee_growth_inside_1_last_X128 = fee_growth_inside_1_last_X128;
            position.tokens_owed0 = total0;
            position.tokens_owed1 = total1;

            self._set_position(token_id, position);

            strategy.account.fee0 = Math::try_sub(strategy.account.fee0, total0.into());
            strategy.account.fee1 = Math::try_sub(strategy.account.fee1, total1.into());

            strategy_storage.write(strategy);

            (total0, total1, strategy, position)
        }

        fn _claim_fee_for_compounders(
            ref self: ComponentState<TContractState>,
            token_id: u256,
            strategy_storage: StoragePath<Mutable<StrategyData>>,
        ) -> (u256, u256, StrategyData) {
            let mut strategy = strategy_storage.read();
            let position = self.get_position(token_id);

            let fee0 = Math::mul_div(
                strategy.account.fee0, position.liquidity_share, strategy.account.total_shares,
            );
            let fee1 = Math::mul_div(
                strategy.account.fee1, position.liquidity_share, strategy.account.total_shares,
            );

            strategy.account.fee0 = Math::try_sub(strategy.account.fee0, fee0);
            strategy.account.fee1 = Math::try_sub(strategy.account.fee1, fee1);

            strategy_storage.write(strategy);

            (fee0, fee1, strategy)
        }
    }
}
