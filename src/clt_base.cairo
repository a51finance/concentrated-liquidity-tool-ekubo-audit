#[starknet::contract]
pub mod CLTBase {
    use core::num::traits::Zero;
    use starknet::event::EventEmitter;
    use starknet::storage::{
        Map, StoragePointerWriteAccess, StoragePointerReadAccess, StoragePathEntry, StoragePath,
        Mutable,
    };
    use starknet::{ContractAddress, get_caller_address, get_contract_address};
    use ekubo::components::shared_locker::{call_core_with_callback, consume_callback_data};
    use ekubo::interfaces::core::{ICoreDispatcher, ICoreDispatcherTrait, ILocker};
    use ekubo::types::bounds::Bounds;
    use ekubo::types::keys::PoolKey;
    use openzeppelin::token::erc721::ERC721Component;
    use openzeppelin::introspection::src5::SRC5Component;
    use openzeppelin::access::ownable::OwnableComponent;
    use openzeppelin::security::pausable::PausableComponent;
    use openzeppelin::security::reentrancyguard::ReentrancyGuardComponent;


    use clt_ekubo::components::bytes_handler::BytesHandler;
    use clt_ekubo::components::constants::Constants;
    use clt_ekubo::components::core_actions::CoreActions;
    use clt_ekubo::components::vault_actions::VaultActions;
    use clt_ekubo::components::hashing::Hashing;
    use clt_ekubo::components::liquidity_shares::LiquidityShares;
    use clt_ekubo::components::math::Math;
    use clt_ekubo::components::position::Position;
    use clt_ekubo::components::strategy_fee_shares::StrategyFeeShares;
    use clt_ekubo::components::user_positions::{UserPositionsComponent, PositionData};
    use clt_ekubo::components::util::{
        serialize, deserialize, pay, transfer_fee, calculate_automation_fee,
    };
    use clt_ekubo::interfaces::clt_base::{
        ICLTBase, StrategyData, StrategyParams, StrategyKey, Account, DepositParams, Errors,
        UpdatePositionParams, WithdrawParams, ClaimFeeParams, ShiftLiquidityParams, SwapOrderParams,
        SwapOrderData,
    };
    use clt_ekubo::interfaces::clt_modules::{ICLTModulesDispatcher, ICLTModulesDispatcherTrait};
    use clt_ekubo::interfaces::governance_fee_handler::{
        IGovernanceFeeHandlerDispatcher, IGovernanceFeeHandlerDispatcherTrait,
    };
    use clt_ekubo::interfaces::erc_4626::{IERC4626Dispatcher, IERC4626DispatcherTrait};
    use clt_ekubo::types::base_init::BaseInitParams;
    use clt_ekubo::types::callback_method::CallbackMethod;
    use clt_ekubo::types::internal_params::InternalParams;
    use clt_ekubo::types::pool_id::{PoolId, PoolIdTrait};

    component!(path: ERC721Component, storage: erc721, event: Erc721Event);
    component!(path: SRC5Component, storage: src5, event: SRC5Event);
    component!(path: OwnableComponent, storage: ownable, event: OwnableEvent);
    component!(path: UserPositionsComponent, storage: user_positions, event: PositionEvent);
    component!(path: PausableComponent, storage: pausable, event: PausableEvent);
    component!(
        path: ReentrancyGuardComponent, storage: reentrancy_guard, event: ReentrancyGuardEvent,
    );

    #[abi(embed_v0)]
    impl Ownable = OwnableComponent::OwnableImpl<ContractState>;
    #[abi(embed_v0)]
    impl PausableImpl = PausableComponent::PausableImpl<ContractState>;
    #[abi(embed_v0)]
    impl Erc721 = ERC721Component::ERC721MixinImpl<ContractState>;
    #[abi(embed_v0)]
    impl UserPositions = UserPositionsComponent::UserPositionsImpl<ContractState>;

    impl OwnableInternal = OwnableComponent::InternalImpl<ContractState>;
    impl Erc721Internal = ERC721Component::InternalImpl<ContractState>;
    impl Erc721HooksImpl of ERC721Component::ERC721HooksTrait<ContractState>;
    impl UserPositionsInternal = UserPositionsComponent::InternalImpl<ContractState>;
    impl PausableInternalImpl = PausableComponent::InternalImpl<ContractState>;
    impl ReentrancyGuardImpl = ReentrancyGuardComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        core: ICoreDispatcher,
        clt_modules: ICLTModulesDispatcher,
        fee_handler: IGovernanceFeeHandlerDispatcher,
        eth: ContractAddress,
        shares_id: u256,
        strategies: Map<PoolId, StrategyData>,
        strategy_actions: Map<PoolId, BytesHandler::Bytes>,
        action_status: Map<(PoolId, felt252), BytesHandler::Bytes>,
        orders: Map<felt252, SwapOrderData>,
        order_module_status: Map<felt252, BytesHandler::Bytes>,
        #[substorage(v0)]
        erc721: ERC721Component::Storage,
        #[substorage(v0)]
        src5: SRC5Component::Storage,
        #[substorage(v0)]
        ownable: OwnableComponent::Storage,
        #[substorage(v0)]
        pausable: PausableComponent::Storage,
        #[substorage(v0)]
        reentrancy_guard: ReentrancyGuardComponent::Storage,
        #[substorage(v0)]
        user_positions: UserPositionsComponent::Storage,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Collect {
        pub token_id: u256,
        pub recipient: ContractAddress,
        pub amount0_collected: u256,
        pub amount1_collected: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Deposit {
        #[key]
        token_id: u256,
        #[key]
        recipient: ContractAddress,
        liquidity: u256,
        amount0: u256,
        amount1: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct Withdraw {
        #[key]
        token_id: u256,
        #[key]
        recipient: ContractAddress,
        liquidity: u256,
        amount0: u256,
        amount1: u256,
        fee0: u256,
        fee1: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct StrategyCreated {
        #[key]
        strategy_id: PoolId,
    }

    #[derive(Drop, starknet::Event)]
    pub struct StrategyUpdated {
        #[key]
        strategy_id: Span<felt252>,
    }

    #[derive(Drop, starknet::Event)]
    pub struct StrategyFee {
        #[key]
        strategy_id: PoolId,
        fee0: u256,
        fee1: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct PositionUpdated {
        #[key]
        token_id: u256,
        share: u256,
        amount0: u256,
        amount1: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct LiquidityShifted {
        #[key]
        strategy_id: PoolId,
        #[key]
        action_name: Span<felt252>,
        is_liquidity_minted: bool,
        zero_for_one: bool,
        swap_amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct FeeCompounded {
        #[key]
        strategy_id: PoolId,
        amount0: u256,
        amount1: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct StrategyPerformanceFee {
        #[key]
        strategy_id: PoolId,
        #[key]
        token_id: u256,
        #[key]
        strategy_owner: ContractAddress,
        fee0: u256,
        fee1: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct StrategyManagementFee {
        #[key]
        strategy_id: PoolId,
        #[key]
        token_id: u256,
        #[key]
        recipient: ContractAddress,
        fee0: u256,
        fee1: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct StrategyAutomationFee {
        #[key]
        strategy_id: PoolId,
        #[key]
        recipient: ContractAddress,
        fee0: u256,
        fee1: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct ModifyVaultLiquidity {
        #[key]
        strategy_id: PoolId,
        #[key]
        vault: ContractAddress,
        assets: u256,
        sign: bool,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OrderPlaced {
        #[key]
        strategy_id: PoolId,
        #[key]
        order_hash: felt252,
        pool_key: PoolKey,
        zero_for_one: bool,
        swap_amount: u256,
        min_amount: u256,
        deadline: u256,
    }

    #[derive(Drop, starknet::Event)]
    pub struct OrderFilled {
        #[key]
        strategy_id: PoolId,
        #[key]
        order_hash: felt252,
    }

    #[derive(starknet::Event, Drop)]
    #[event]
    pub enum Event {
        Collect: Collect,
        Deposit: Deposit,
        Withdraw: Withdraw,
        StrategyCreated: StrategyCreated,
        StrategyUpdated: StrategyUpdated,
        StrategyFee: StrategyFee,
        PositionUpdated: PositionUpdated,
        LiquidityShifted: LiquidityShifted,
        FeeCompounded: FeeCompounded,
        StrategyPerformanceFee: StrategyPerformanceFee,
        StrategyManagementFee: StrategyManagementFee,
        StrategyAutomationFee: StrategyAutomationFee,
        ModifyVaultLiquidity: ModifyVaultLiquidity,
        OrderPlaced: OrderPlaced,
        OrderFilled: OrderFilled,
        #[flat]
        Erc721Event: ERC721Component::Event,
        #[flat]
        SRC5Event: SRC5Component::Event,
        #[flat]
        OwnableEvent: OwnableComponent::Event,
        #[flat]
        PausableEvent: PausableComponent::Event,
        #[flat]
        ReentrancyGuardEvent: ReentrancyGuardComponent::Event,
        #[flat]
        PositionEvent: UserPositionsComponent::Event,
    }

    #[constructor]
    fn constructor(ref self: ContractState, params: BaseInitParams) {
        self.ownable.initializer(params.owner);
        self.erc721.initializer(params.name, params.symbol, "");

        self.clt_modules.write(params.clt_modules);
        self.fee_handler.write(params.fee_handler);
        self.core.write(params.core);
        self.eth.write(params.eth);
        self.shares_id.write(1);
    }

    #[abi(embed_v0)]
    impl CLTBaseImpl of ICLTBase<ContractState> {
        fn fee_handler(self: @ContractState) -> ContractAddress {
            self.fee_handler.read().contract_address
        }

        fn action_status(
            self: @ContractState, strategy_id: PoolId, action_name: felt252,
        ) -> Span<felt252> {
            BytesHandler::read(self.action_status.entry((strategy_id, action_name)))
        }

        fn orders(self: @ContractState, order_id: felt252) -> SwapOrderData {
            self.orders.entry(order_id).read()
        }

        fn order_module_status(self: @ContractState, order_id: felt252) -> Span<felt252> {
            BytesHandler::read(self.order_module_status.entry(order_id))
        }

        fn strategies(self: @ContractState, strategy_id: PoolId) -> (StrategyData, Span<felt252>) {
            let strategy = self.strategies.entry(strategy_id).read();
            let actions = BytesHandler::read(self.strategy_actions.entry(strategy_id));
            (strategy, actions)
        }

        fn positions(self: @ContractState, token_id: u256) -> PositionData {
            self.user_positions.get_position(token_id)
        }

        fn create_strategy(ref self: ContractState, params: StrategyParams) {
            let pool_id = params.pool_key.to_id();

            self._validate_modes(params.actions, params.management_fee, params.performance_fee);

            BytesHandler::write(self.strategy_actions.entry(pool_id), params.actions);

            self
                .strategies
                .entry(pool_id)
                .write(
                    StrategyData {
                        key: StrategyKey {
                            tick_lower: params.tick_lower, tick_upper: params.tick_upper,
                        },
                        pool_key: params.pool_key.into(),
                        owner: params.owner,
                        is_compound: params.is_compound,
                        is_private: params.is_private,
                        management_fee: params.management_fee,
                        performance_fee: params.performance_fee,
                        vault0: params.vault0,
                        vault1: params.vault1,
                        account: Account {
                            fee0: 0,
                            fee1: 0,
                            balance0: 0,
                            balance1: 0,
                            total_shares: 0,
                            ekubo_liquidity: 0,
                            fee_growth_inside_0_last_X128: 0,
                            fee_growth_inside_1_last_X128: 0,
                            automation_fee_owed0: 0,
                            automation_fee_owed1: 0,
                            last_saved_amount0: 0,
                            last_saved_amount1: 0,
                            is_holding_saved: false,
                        },
                    },
                );

            self.core.read().initialize_pool(params.pool_key, params.initial_tick);

            let (_, strategy_creation_fee_amount) = self._get_governance_fee(params.is_private);

            if strategy_creation_fee_amount > 0 {
                pay(
                    self.eth.read(),
                    get_caller_address(),
                    self.ownable.owner(),
                    strategy_creation_fee_amount,
                );
            }

            self.emit(StrategyCreated { strategy_id: pool_id });
        }

        fn deposit(ref self: ContractState, params: DepositParams) -> (u256, u256, u256, u256) {
            self.reentrancy_guard.start();
            self.pausable.assert_not_paused();

            self._authorization_of_strategy(params.strategy_id);

            let (
                share,
                amount0,
                amount1,
                fee_growth_inside_0_last_X128,
                fee_growth_inside_1_last_X128,
            ) =
                self
                ._deposit(
                    InternalParams {
                        strategy_id: params.strategy_id,
                        amount0_desired: params.amount0_desired,
                        amount1_desired: params.amount1_desired,
                        amount0_min: params.amount0_min,
                        amount1_min: params.amount1_min,
                    },
                );

            let token_id = self.shares_id.read();
            self.erc721.mint(params.recipient, token_id);
            self.shares_id.write(token_id + 1);

            self
                .user_positions
                ._set_position(
                    token_id,
                    PositionData {
                        strategy_id: params.strategy_id,
                        liquidity_share: share,
                        tokens_owed0: 0,
                        tokens_owed1: 0,
                        fee_growth_inside_0_last_X128,
                        fee_growth_inside_1_last_X128,
                    },
                );

            self
                .emit(
                    Deposit {
                        token_id, recipient: params.recipient, liquidity: share, amount0, amount1,
                    },
                );

            self.reentrancy_guard.end();
            (token_id, share, amount0, amount1)
        }

        fn update_position_liquidity(
            ref self: ContractState, params: UpdatePositionParams,
        ) -> (u256, u256, u256) {
            self.reentrancy_guard.start();
            self.pausable.assert_not_paused();

            let position = self.user_positions.get_position(params.token_id);

            self._authorization_of_strategy(position.strategy_id);

            let (
                share,
                amount0,
                amount1,
                fee_growth_inside_0_last_X128,
                fee_growth_inside_1_last_X128,
            ) =
                self
                ._deposit(
                    InternalParams {
                        strategy_id: position.strategy_id,
                        amount0_desired: params.amount0_desired,
                        amount1_desired: params.amount1_desired,
                        amount0_min: params.amount0_min,
                        amount1_min: params.amount1_min,
                    },
                );

            if !self.strategies.entry(position.strategy_id).read().is_compound {
                self
                    .user_positions
                    ._update_position(
                        params.token_id,
                        fee_growth_inside_0_last_X128,
                        fee_growth_inside_1_last_X128,
                    );
            }

            self.user_positions._update_liquidity(params.token_id, share);

            self.emit(PositionUpdated { token_id: params.token_id, share, amount0, amount1 });
            self.reentrancy_guard.end();
            (share, amount0, amount1)
        }

        fn withdraw(ref self: ContractState, params: WithdrawParams) -> (u256, u256) {
            self.reentrancy_guard.start();

            self._is_authorized_for_token(get_caller_address(), params.token_id);

            let mut position = self.user_positions.get_position(params.token_id);
            let strategy_storage = self.strategies.entry(position.strategy_id);
            self._update_globals(position.strategy_id, strategy_storage, true);
            let mut strategy = strategy_storage.read();

            assert(params.liquidity != 0, Errors::INVALID_SHARE);
            assert(position.liquidity_share != 0, Errors::NO_LIQUIDITY);
            assert(position.liquidity_share >= params.liquidity, Errors::INVALID_SHARE);

            let (mut amount0, mut amount1, mut fee0, mut fee1): (u256, u256, u256, u256) = (
                0, 0, 0, 0,
            );

            let (_amount0, _amount1, _, _) = if strategy.account.is_holding_saved
                && (strategy.account.last_saved_amount0 != 0
                    || strategy.account.last_saved_amount1 != 0) {
                self
                    ._core_load_and_remove(
                        strategy.pool_key.into(),
                        strategy.account.last_saved_amount0,
                        strategy.account.last_saved_amount1,
                    )
            } else {
                let removed_liquidity = Math::mul_div(
                    strategy.account.ekubo_liquidity.into(),
                    params.liquidity,
                    strategy.account.total_shares,
                );

                self
                    ._core_remove(
                        strategy.pool_key.into(),
                        strategy.key.into(),
                        removed_liquidity.try_into().unwrap(),
                    )
            };
            amount0 = _amount0.into();
            amount1 = _amount1.into();

            if !strategy.is_compound {
                let (_fee0, _fee1, _strategy, _position) = self
                    .user_positions
                    ._claim_fee_for_non_compounders(params.token_id, strategy_storage);
                fee0 = _fee0.into();
                fee1 = _fee1.into();
                strategy = _strategy;
                position = _position;
            } else {
                let (_fee0, _fee1, _strategy) = self
                    .user_positions
                    ._claim_fee_for_compounders(params.token_id, strategy_storage);
                fee0 = _fee0;
                fee1 = _fee1;
                strategy = _strategy;
            }

            let (perf_fee_deduction0, perf_fee_deduction1) = transfer_fee(
                strategy.pool_key, strategy.performance_fee, fee0, fee1, strategy.owner,
            );

            fee0 -= perf_fee_deduction0;
            fee1 -= perf_fee_deduction1;

            if perf_fee_deduction0 > 0 || perf_fee_deduction1 > 0 {
                self
                    .emit(
                        StrategyPerformanceFee {
                            strategy_id: position.strategy_id,
                            token_id: params.token_id,
                            strategy_owner: strategy.owner,
                            fee0: perf_fee_deduction0,
                            fee1: perf_fee_deduction1,
                        },
                    );
            }

            let mut user_share0: u256 = 0;
            let mut user_share1: u256 = 0;

            if strategy.account.total_shares > 0 {
                user_share0 =
                    Math::mul_div(
                        strategy.account.balance0, params.liquidity, strategy.account.total_shares,
                    );
                user_share1 =
                    Math::mul_div(
                        strategy.account.balance1, params.liquidity, strategy.account.total_shares,
                    );

                strategy.account.balance0 -= user_share0;
                strategy.account.balance1 -= user_share1;
            }

            amount0 += user_share0 + fee0;
            amount1 += user_share1 + fee1;

            let (mgmt_fee_deduction0, mgmt_fee_deduction1) = transfer_fee(
                strategy.pool_key, strategy.management_fee, amount0, amount1, strategy.owner,
            );

            amount0 -= mgmt_fee_deduction0;
            amount1 -= mgmt_fee_deduction1;

            if mgmt_fee_deduction0 > 0 || mgmt_fee_deduction1 > 0 {
                self
                    .emit(
                        StrategyManagementFee {
                            strategy_id: position.strategy_id,
                            token_id: params.token_id,
                            recipient: strategy.owner,
                            fee0: mgmt_fee_deduction0,
                            fee1: mgmt_fee_deduction1,
                        },
                    );
            }

            if !strategy.is_compound {
                position.tokens_owed0 = 0;
                position.tokens_owed1 = 0;
            }

            // Withdraw from vault0 if it exists and has balance
            if strategy.vault0 != Zero::zero() {
                let vault0 = IERC4626Dispatcher { contract_address: strategy.vault0 };
                let assets0 = Math::mul_div(
                    vault0.total_assets(), params.liquidity, strategy.account.total_shares,
                );

                if assets0 > 0 {
                    VaultActions::vault_withdraw(
                        vault0,
                        position.strategy_id,
                        strategy.pool_key.token0,
                        params.recipient,
                        assets0,
                    );
                    amount0 += assets0;

                    self
                        .emit(
                            ModifyVaultLiquidity {
                                strategy_id: position.strategy_id,
                                vault: vault0.contract_address,
                                assets: assets0,
                                sign: true,
                            },
                        );
                }
            }

            // Withdraw from vault1 if it exists and has balance
            if strategy.vault1 != Zero::zero() {
                let vault1 = IERC4626Dispatcher { contract_address: strategy.vault1 };
                let assets1 = Math::mul_div(
                    vault1.total_assets(), params.liquidity, strategy.account.total_shares,
                );

                if assets1 > 0 {
                    VaultActions::vault_withdraw(
                        vault1,
                        position.strategy_id,
                        strategy.pool_key.token1,
                        params.recipient,
                        assets1,
                    );
                    amount1 += assets1;

                    self
                        .emit(
                            ModifyVaultLiquidity {
                                strategy_id: position.strategy_id,
                                vault: vault1.contract_address,
                                assets: assets1,
                                sign: true,
                            },
                        );
                }
            }

            let mut automation_fee_share0: u256 = 0;
            let mut automation_fee_share1: u256 = 0;

            if strategy.account.automation_fee_owed0 > 0
                || strategy.account.automation_fee_owed1 > 0 {
                let total_shares_before_withdraw = strategy.account.total_shares;

                if total_shares_before_withdraw > 0 {
                    automation_fee_share0 =
                        Math::mul_div(
                            strategy.account.automation_fee_owed0,
                            params.liquidity,
                            total_shares_before_withdraw,
                        );

                    automation_fee_share1 =
                        Math::mul_div(
                            strategy.account.automation_fee_owed1,
                            params.liquidity,
                            total_shares_before_withdraw,
                        );

                    strategy.account.automation_fee_owed0 -= automation_fee_share0;
                    strategy.account.automation_fee_owed1 -= automation_fee_share1;

                    if automation_fee_share0 > 0 {
                        pay(
                            strategy.pool_key.token0,
                            get_contract_address(),
                            strategy.owner,
                            automation_fee_share0,
                        );
                    }

                    if automation_fee_share1 > 0 {
                        pay(
                            strategy.pool_key.token1,
                            get_contract_address(),
                            strategy.owner,
                            automation_fee_share1,
                        );
                    }

                    self
                        .emit(
                            StrategyAutomationFee {
                                strategy_id: position.strategy_id,
                                recipient: strategy.owner,
                                fee0: automation_fee_share0,
                                fee1: automation_fee_share1,
                            },
                        );
                }
            }

            assert(
                automation_fee_share0 < amount0 || automation_fee_share1 < amount1,
                Errors::INVALID_AUTOMATION_FEE,
            );

            amount0 = amount0 - automation_fee_share0;
            amount1 = amount1 - automation_fee_share1;

            assert(
                amount0 >= params.amount0_min && amount1 >= params.amount1_min,
                Errors::MINIMUM_AMOUNT_EXCEEDS,
            );

            if amount0 > 0 {
                pay(strategy.pool_key.token0, get_contract_address(), params.recipient, amount0);
            }

            if amount1 > 0 {
                pay(strategy.pool_key.token1, get_contract_address(), params.recipient, amount1);
            }

            position.liquidity_share -= params.liquidity;
            strategy.account.total_shares -= params.liquidity;

            let action_status_data = BytesHandler::read(
                (@self).action_status.entry((position.strategy_id, Constants::IS_EXIT)),
            );
            if !Position::get_hodl_status(action_status_data) {
                strategy.account.ekubo_liquidity -= params.liquidity.try_into().unwrap();
            }

            if strategy.account.is_holding_saved {
                strategy.account.last_saved_amount0 = 0;
                strategy.account.last_saved_amount1 = 0;
                strategy.account.is_holding_saved = false;
            }

            strategy_storage.write(strategy);
            self.user_positions._set_position(params.token_id, position);

            self
                .emit(
                    Withdraw {
                        token_id: params.token_id,
                        recipient: params.recipient,
                        liquidity: params.liquidity,
                        amount0: amount0,
                        amount1: amount1,
                        fee0,
                        fee1,
                    },
                );

            self.reentrancy_guard.end();
            (amount0, amount1)
        }

        fn claim_position_fee(ref self: ContractState, params: ClaimFeeParams) {
            self.reentrancy_guard.start();
            self.pausable.assert_not_paused();

            self._is_authorized_for_token(get_caller_address(), params.token_id);

            let mut position = self.user_positions.get_position(params.token_id);
            let strategy_storage = self.strategies.entry(position.strategy_id);
            self._update_globals(position.strategy_id, strategy_storage, true);
            let strategy = strategy_storage.read();

            assert(!strategy.is_compound, Errors::ONLY_NON_COMPOUNDERS);
            assert(position.liquidity_share != 0, Errors::NO_LIQUIDITY);

            let (tokens_owed0, tokens_owed1, _, _) = self
                .user_positions
                ._claim_fee_for_non_compounders(params.token_id, strategy_storage);

            let (fee0, fee1) = transfer_fee(
                strategy.pool_key,
                strategy.performance_fee,
                tokens_owed0.into(),
                tokens_owed1.into(),
                strategy.owner,
            );

            if fee0 > 0 || fee1 > 0 {
                self
                    .emit(
                        StrategyPerformanceFee {
                            strategy_id: position.strategy_id,
                            token_id: params.token_id,
                            strategy_owner: strategy.owner,
                            fee0,
                            fee1,
                        },
                    );
            }

            if tokens_owed0 > 0 {
                pay(
                    strategy.pool_key.token0,
                    get_contract_address(),
                    params.recipient,
                    tokens_owed0.into() - fee0,
                );
            }

            if tokens_owed1 > 0 {
                pay(
                    strategy.pool_key.token1,
                    get_contract_address(),
                    params.recipient,
                    tokens_owed1.into() - fee1,
                );
            }

            position.tokens_owed0 = 0;
            position.tokens_owed1 = 0;
            self.user_positions._set_position(params.token_id, position);

            self
                .emit(
                    Collect {
                        token_id: params.token_id,
                        recipient: params.recipient,
                        amount0_collected: tokens_owed0.into() - fee0,
                        amount1_collected: tokens_owed1.into() - fee1,
                    },
                );
            self.reentrancy_guard.end();
        }


        fn shift_liquidity(ref self: ContractState, params: ShiftLiquidityParams) {
            let strategy_id = params.order.pool_key.to_id();

            let strategy_storage = self.strategies.entry(strategy_id);
            let mut strategy = strategy_storage.read();

            let mut balance0 = 0;
            let mut balance1 = 0;
            let mut fee0 = 0;
            let mut fee1 = 0;
            let mut amount0_saved = 0;
            let mut amount1_saved = 0;

            if (!params.is_manager_locked) {
                self._update_globals(strategy_id, strategy_storage, false);

                let ekubo_liquidity = strategy.account.ekubo_liquidity;
                let (_amount0_saved, _amount1_saved, _, _) = self
                    ._core_remove_and_save(
                        strategy.pool_key.into(), strategy.key.into(), ekubo_liquidity,
                    );

                amount0_saved = _amount0_saved;
                amount1_saved = _amount1_saved;

                balance0 = amount0_saved.into();
                balance1 = amount1_saved.into();

                let (total_shares, _) = self._get_governance_fee(strategy.is_private);
                let (fee0, fee1) = calculate_automation_fee(total_shares, balance0, balance1);

                if fee0 > 0 || fee1 > 0 {
                    strategy.account.automation_fee_owed0 += fee0;
                    strategy.account.automation_fee_owed1 += fee1;
                }

                if strategy.is_compound {
                    balance0 += strategy.account.fee0;
                    balance1 += strategy.account.fee1;

                    self
                        .emit(
                            FeeCompounded {
                                strategy_id,
                                amount0: strategy.account.fee0,
                                amount1: strategy.account.fee1,
                            },
                        );
                }
            }

            balance0 += strategy.account.balance0;
            balance1 += strategy.account.balance1;

            if params.exchange_address != Zero::zero() {
                let order_hash = Hashing::hash_order(params.order);
                let mut stored_order: SwapOrderParams = self.orders.entry(order_hash).read().into();
                stored_order
                    .module_status =
                        BytesHandler::read((@self).order_module_status.entry(order_hash));

                if strategy.account.is_holding_saved == true {
                    let (_, _, _, _) = self
                        ._core_load_and_remove(
                            strategy.pool_key.into(),
                            strategy.account.last_saved_amount0,
                            strategy.account.last_saved_amount1,
                        );
                }

                let (amount_in, amount_out) = CoreActions::swap_token(
                    strategy, stored_order, params,
                );

                let (_balance0, _balance1) = CoreActions::amounts_direction(
                    params.order.zero_for_one, balance0, balance1, amount_in, amount_out,
                );

                balance0 = _balance0;
                balance1 = _balance1;

                self
                    .emit(
                        OrderFilled { strategy_id, order_hash: Hashing::hash_order(params.order) },
                    );
            }

            let action_status_data = BytesHandler::read(
                (@self).action_status.entry((strategy_id, Constants::IS_PARTIAL)),
            );

            if Position::get_partial_amount_status(action_status_data) {
                let (fee0, fee1, _strategy) = Position::update_partial_deposit_balance(
                    strategy_storage, action_status_data, balance0, balance1,
                );
                strategy = _strategy;

                if fee0 > 0 {
                    balance0 = Math::mul_div(balance0, fee0, Constants::WAD);
                }

                if fee1 > 0 {
                    balance1 = Math::mul_div(balance1, fee1, Constants::WAD);
                }
            }

            let (mut liquidity_delta, mut amount0_added, mut amount1_added): (u128, u256, u256) = (
                0, 0, 0,
            );

            if params.order.should_mint {
                let (_liquidity_delta, _amount0_added, _amount1_added) = self
                    ._core_add(strategy.pool_key.into(), strategy.key.into(), balance0, balance1);

                liquidity_delta = _liquidity_delta;
                amount0_added = _amount0_added;
                amount1_added = _amount1_added;

                // if order filled successfully un hodl the position again
                BytesHandler::write(
                    self.action_status.entry((strategy_id, Constants::IS_EXIT)),
                    serialize::<bool>(@false).span(),
                );
            }

            BytesHandler::write(
                self.action_status.entry((strategy_id, params.order.action_name)),
                params.order.module_status,
            );

            let is_hodl = Position::get_hodl_status(
                BytesHandler::read((@self).action_status.entry((strategy_id, Constants::IS_EXIT))),
            );

            Position::update_strategy(
                strategy_storage,
                strategy.key,
                liquidity_delta,
                balance0 - amount0_added,
                balance1 - amount1_added,
                strategy.account.automation_fee_owed0,
                strategy.account.automation_fee_owed1,
                amount0_saved,
                amount1_saved,
                fee1,
                fee0,
                is_hodl,
            );

            self
                .emit(
                    LiquidityShifted {
                        strategy_id,
                        action_name: params.order.module_status,
                        is_liquidity_minted: params.order.should_mint,
                        zero_for_one: params.order.zero_for_one,
                        swap_amount: params.order.swap_amount,
                    },
                );
        }

        fn place_swap_order(ref self: ContractState, params: SwapOrderParams) {
            assert(
                Position::get_hodl_status(
                    BytesHandler::read(
                        (@self).action_status.entry((params.pool_key.to_id(), Constants::IS_EXIT)),
                    ),
                ),
                '',
            );

            assert(
                params.swap_amount != 0 || params.min_amount != 0 || params.deadline != 0,
                'Invalid Values',
            );

            let order_hash = Hashing::hash_order(params);

            self.orders.entry(order_hash).write(params.into());

            BytesHandler::write(self.order_module_status.entry(order_hash), params.module_status);

            println!("Order placed {:?}", order_hash);

            self
                .emit(
                    OrderPlaced {
                        strategy_id: params.pool_key.to_id(),
                        order_hash,
                        pool_key: params.pool_key.into(),
                        zero_for_one: params.zero_for_one,
                        swap_amount: params.swap_amount,
                        min_amount: params.min_amount,
                        deadline: params.deadline,
                    },
                );
        }


        fn update_strategy_base(
            ref self: ContractState,
            strategy_id: PoolId,
            owner: ContractAddress,
            management_fee: u256,
            performance_fee: u256,
            actions: Span<felt252>,
        ) {
            let strategy_storage = self.strategies.entry(strategy_id);
            let mut strategy = strategy_storage.read();

            self._validate_modes(actions, management_fee, performance_fee);

            assert(strategy.owner == owner, Errors::INVALID_CALLER);
            assert(!owner.is_zero(), Errors::OWNER_CANNOT_BE_ZERO_ADDRESS);

            //update strategy state
            BytesHandler::write(self.strategy_actions.entry(strategy_id), actions);

            if strategy.owner != owner {
                strategy.owner = owner;
            }

            if strategy.management_fee != management_fee {
                strategy.management_fee = management_fee;
            }

            if strategy.performance_fee != performance_fee {
                strategy.performance_fee = performance_fee;
            }
        }

        fn get_strategy_reserves(
            ref self: ContractState, strategy_id: PoolId, is_manager_locked: bool,
        ) -> (u128, u256, u256) {
            let strategy_storage = self.strategies.entry(strategy_id);
            self._update_globals(strategy_id, strategy_storage, is_manager_locked);
            let strategy = strategy_storage.read();
            (strategy.account.ekubo_liquidity, strategy.account.fee0, strategy.account.fee1)
        }

        fn get_user_fees(ref self: ContractState, token_id: u256) -> (u256, u256) {
            let position = self.user_positions.get_position(token_id);
            let strategy_storage = self.strategies.entry(position.strategy_id);
            self._update_globals(position.strategy_id, strategy_storage, true);
            let (fee0, fee1, _, _) = self
                .user_positions
                ._claim_fee_for_non_compounders(token_id, strategy_storage);
            (fee0.into(), fee1.into())
        }

        fn pause(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.pausable.pause();
        }

        fn unpause(ref self: ContractState) {
            self.ownable.assert_only_owner();
            self.pausable.unpause();
        }
    }

    #[generate_trait]
    impl Internal of InternalTrait {
        fn _validate_modes(
            self: @ContractState,
            actions: Span<felt252>,
            management_fee: u256,
            performance_fee: u256,
        ) {
            self.clt_modules.read().validate_modes(actions, management_fee, performance_fee);
        }

        fn _get_governance_fee(self: @ContractState, is_private: bool) -> (u256, u256) {
            self.fee_handler.read().get_governance_fee(is_private)
        }

        fn _authorization_of_strategy(self: @ContractState, strategy_id: PoolId) {
            let strategy = self.strategies.entry(strategy_id).read();
            if strategy.is_private {
                assert(strategy.owner == get_caller_address(), Errors::NOT_AUTHORIZED);
            }
        }

        fn _deposit(
            ref self: ContractState, params: InternalParams,
        ) -> (u256, u256, u256, u256, u256) {
            let strategy_storage = self.strategies.entry(params.strategy_id);

            self._update_globals(params.strategy_id, strategy_storage, true);

            let (mut ekubo_liquidity, mut balance0, mut balance1) = (0, 0, 0);

            let is_exit = Position::get_hodl_status(
                BytesHandler::read(
                    (@self).action_status.entry((params.strategy_id, Constants::IS_EXIT)),
                ),
            );

            let mut strategy = strategy_storage.read();

            // need to fix this logic as it run unnecessary sometimes
            if strategy.is_compound && is_exit == false {
                let (_ekubo_liquidity, _balance0, _balance1) = self
                    ._core_add(
                        strategy.pool_key.into(),
                        strategy.key.into(),
                        strategy.account.balance0 + strategy.account.fee0,
                        strategy.account.balance1 + strategy.account.fee1,
                    );

                ekubo_liquidity = _ekubo_liquidity;
                balance0 = _balance0;
                balance1 = _balance1;

                if ekubo_liquidity > 0 {
                    strategy =
                        Position::update_for_compound(
                            strategy_storage, ekubo_liquidity, balance0, balance1,
                        );
                    self
                        .emit(
                            FeeCompounded {
                                strategy_id: params.strategy_id,
                                amount0: balance0,
                                amount1: balance1,
                            },
                        );
                }
            }

            let (share, mut amount0, mut amount1) = LiquidityShares::compute_liquidity_share(
                strategy, self.core.read(), params.amount0_desired, params.amount1_desired,
            );

            assert(share != 0, Errors::INVALID_SHARE);

            if strategy.account.total_shares == 0 {
                assert(share >= Constants::MIN_INITIAL_SHARES, Errors::INVALID_SHARE);
            }

            assert(
                amount0 >= params.amount0_min && amount1 >= params.amount1_min,
                Errors::MINIMUM_AMOUNT_EXCEEDS,
            );

            pay(strategy.pool_key.token0, get_caller_address(), get_contract_address(), amount0);
            pay(strategy.pool_key.token1, get_caller_address(), get_contract_address(), amount1);

            let action_status_data = BytesHandler::read(
                (@self).action_status.entry((params.strategy_id, Constants::IS_PARTIAL)),
            );

            if Position::get_partial_amount_status(action_status_data) {
                let (fee0, fee1, _strategy) = Position::update_partial_deposit_balance(
                    strategy_storage, action_status_data, amount0, amount1,
                );
                strategy = _strategy;

                if fee0 > 0 {
                    amount0 = Math::mul_div(amount0, fee0, Constants::WAD);
                }

                if fee1 > 0 {
                    amount1 = Math::mul_div(amount1, fee1, Constants::WAD);
                }
            }

            if !is_exit {
                let (_ekubo_liquidity, _balance0, _balance1) = self
                    ._core_add(strategy.pool_key.into(), strategy.key.into(), amount0, amount1);
                ekubo_liquidity = _ekubo_liquidity;
                balance0 = _balance0;
                balance1 = _balance1;
            }

            strategy =
                Position::update(
                    strategy_storage, ekubo_liquidity, share, amount0, amount1, balance0, balance1,
                );

            (
                share,
                amount0,
                amount1,
                strategy.account.fee_growth_inside_0_last_X128,
                strategy.account.fee_growth_inside_1_last_X128,
            )
        }

        fn _core_add(
            self: @ContractState, pool_key: PoolKey, bounds: Bounds, amount0: u256, amount1: u256,
        ) -> (u128, u256, u256) {
            let add_data = serialize::<
                (PoolKey, Bounds, u256, u256),
            >(@(pool_key, bounds, amount0, amount1))
                .span();
            call_core_with_callback::<
                (CallbackMethod, Span<felt252>), (u128, u256, u256),
            >(self.core.read(), @(CallbackMethod::Add, add_data))
        }

        fn _core_remove(
            self: @ContractState, pool_key: PoolKey, bounds: Bounds, liquidity: u128,
        ) -> (u128, u128, u256, u256) {
            let remove_data = serialize::<(PoolKey, Bounds, u128)>(@(pool_key, bounds, liquidity))
                .span();
            call_core_with_callback::<
                (CallbackMethod, Span<felt252>), (u128, u128, u256, u256),
            >(self.core.read(), @(CallbackMethod::Remove, remove_data))
        }

        fn _core_load_and_remove(
            self: @ContractState, pool_key: PoolKey, amount0: u128, amount1: u128,
        ) -> (u128, u128, u256, u256) {
            let remove_data = serialize::<(PoolKey, u128, u128)>(@(pool_key, amount0, amount1))
                .span();
            call_core_with_callback::<
                (CallbackMethod, Span<felt252>), (u128, u128, u256, u256),
            >(self.core.read(), @(CallbackMethod::Load_and_Remove, remove_data))
        }

        fn _core_remove_and_save(
            self: @ContractState, pool_key: PoolKey, bounds: Bounds, liquidity: u128,
        ) -> (u128, u128, u256, u256) {
            let remove_data = serialize::<(PoolKey, Bounds, u128)>(@(pool_key, bounds, liquidity))
                .span();
            call_core_with_callback::<
                (CallbackMethod, Span<felt252>), (u128, u128, u256, u256),
            >(self.core.read(), @(CallbackMethod::Remove_and_save, remove_data))
        }

        fn _update_globals(
            ref self: ContractState,
            strategy_id: PoolId,
            strategy_storage: StoragePath<Mutable<StrategyData>>,
            is_manager_locked: bool,
        ) {
            let strategy = strategy_storage.read();

            if strategy.account.ekubo_liquidity > 0 {
                let collect_data = serialize::<
                    (PoolKey, felt252, Bounds),
                >(@(strategy.pool_key.into(), strategy_id.into(), strategy.key.into()))
                    .span();

                let (fee0, fee1) = call_core_with_callback::<
                    (CallbackMethod, Span<felt252>), (u256, u256),
                >(self.core.read(), @(CallbackMethod::Collect, collect_data));

                StrategyFeeShares::update_strategy_fees(strategy_storage, fee0, fee1);
                self.emit(StrategyFee { strategy_id, fee0, fee1 });
            }
        }


        fn _unlock_add(
            self: @ContractState, core: ICoreDispatcher, data: Span<felt252>,
        ) -> Span<felt252> {
            let (pool_key, bounds, amount0_desired, amount1_desired) = deserialize::<
                (PoolKey, Bounds, u256, u256),
            >(data);
            let (liquidity, amount0, amount1) = CoreActions::mint_liquidity(
                core, pool_key, bounds, amount0_desired, amount1_desired,
            );
            serialize::<(u128, u256, u256)>(@(liquidity, amount0, amount1)).span()
        }

        fn _unlock_collect(
            self: @ContractState, core: ICoreDispatcher, data: Span<felt252>,
        ) -> Span<felt252> {
            let (pool_key, salt, bounds) = deserialize::<(PoolKey, felt252, Bounds)>(data);
            let (collect0, collect1) = CoreActions::collect_pending_fees(
                core, pool_key, salt, bounds,
            );
            serialize::<(u256, u256)>(@(collect0, collect1)).span()
        }

        fn _unlock_remove(
            self: @ContractState, core: ICoreDispatcher, data: Span<felt252>,
        ) -> Span<felt252> {
            let (pool_key, bounds, liquidity) = deserialize::<(PoolKey, Bounds, u128)>(data);
            let (amount0, amount1, fee0, fee1) = CoreActions::burn_liquidity(
                core, pool_key, bounds, liquidity,
            );
            serialize::<(u128, u128, u256, u256)>(@(amount0, amount1, fee0, fee1)).span()
        }

        fn _unlock_remove_and_save(
            self: @ContractState, core: ICoreDispatcher, data: Span<felt252>,
        ) -> Span<felt252> {
            let (pool_key, bounds, liquidity) = deserialize::<(PoolKey, Bounds, u128)>(data);
            let (amount0, amount1, fee0, fee1) = CoreActions::burn_liquidity_and_save(
                core, pool_key, bounds, liquidity,
            );
            serialize::<(u128, u128, u256, u256)>(@(amount0, amount1, fee0, fee1)).span()
        }

        fn _unlock_load_and_remove(
            self: @ContractState, core: ICoreDispatcher, data: Span<felt252>,
        ) -> Span<felt252> {
            let (pool_key, amount0, amount1) = deserialize::<(PoolKey, u128, u128)>(data);
            let (amount0, amount1, fee0, fee1) = CoreActions::load_and_withdraw_saved_liquidity(
                core, pool_key, amount0, amount1,
            );
            serialize::<(u128, u128, u256, u256)>(@(amount0, amount1, fee0, fee1)).span()
        }

        fn _is_authorized_for_token(
            self: @ContractState, spender: ContractAddress, token_id: u256,
        ) {
            let owner = self.erc721._owner_of(token_id);
            let is_approved_or_owner = owner == spender
                || self.erc721.get_approved(token_id) == spender
                || self.erc721.is_approved_for_all(owner, spender);
            assert(is_approved_or_owner, Errors::NOT_APPROVED);
        }
    }

    #[abi(embed_v0)]
    impl LockedImpl of ILocker<ContractState> {
        fn locked(ref self: ContractState, id: u32, data: Span<felt252>) -> Span<felt252> {
            let core = self.core.read();
            let (method, mut callback_data) = consume_callback_data::<
                (CallbackMethod, Span<felt252>),
            >(core, data);
            match method {
                CallbackMethod::Add => self._unlock_add(core, callback_data),
                CallbackMethod::Collect => self._unlock_collect(core, callback_data),
                CallbackMethod::Remove => self._unlock_remove(core, callback_data),
                CallbackMethod::Remove_and_save => self
                    ._unlock_remove_and_save(core, callback_data),
                CallbackMethod::Load_and_Remove => self
                    ._unlock_load_and_remove(core, callback_data),
            }
        }
    }
}
