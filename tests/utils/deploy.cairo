use snforge_std::{declare, ContractClassTrait, DeclareResultTrait};
use starknet::{ContractAddress, ClassHash};
use openzeppelin::token::erc20::ERC20ABIDispatcher;
use ekubo::interfaces::core::{ICoreDispatcher, IExtensionDispatcher};

use clt_ekubo::components::util::serialize;
use clt_ekubo::extensions::multiextension::interfaces::multiextension_deployer::IMultiextensionDeployerDispatcher;
use clt_ekubo::extensions::oracle::interfaces::oracle::IOracleDispatcher;
use clt_ekubo::interfaces::clt_base::ICLTBaseDispatcher;
use clt_ekubo::interfaces::clt_modules::ICLTModulesDispatcher;
use clt_ekubo::interfaces::clt_twap_quoter::ICLTTwapQuoterDispatcher;
use clt_ekubo::interfaces::governance_fee_handler::{
    IGovernanceFeeHandlerDispatcher, ProtocolFeeRegistry,
};
use clt_ekubo::interfaces::erc_4626::IERC4626Dispatcher;
use clt_ekubo::types::base_init::BaseInitParams;
use clt_ekubo::mock::extension::IMockExtensionDispatcher;
use crate::utils::ekubo::ekubo_core;

pub fn deploy_mock_token(
    name: ByteArray, symbol: ByteArray, recipient: ContractAddress,
) -> ERC20ABIDispatcher {
    let contract_class = declare("MockERC20").unwrap().contract_class();
    let init_params = serialize(@(name, symbol, recipient));
    let (contract_address, _) = contract_class
        .deploy(@init_params)
        .expect('Deploy mock erc20 failed');
    ERC20ABIDispatcher { contract_address }
}

pub fn deploy_mock_vault(
    asset: ContractAddress, name: ByteArray, symbol: ByteArray,
) -> IERC4626Dispatcher {
    let contract_class = declare("MockERC4626").unwrap().contract_class();
    let init_params = serialize(@(asset, name, symbol));
    let (contract_address, _) = contract_class
        .deploy(@init_params)
        .expect('Deploy mock erc4626 failed');
    IERC4626Dispatcher { contract_address }
}

pub fn deploy_mock_extension(order: u8) -> IMockExtensionDispatcher {
    let contract_class = declare("Mockextension").unwrap().contract_class();
    let init_params = serialize(@(ekubo_core(), order));
    let (contract_address, _) = contract_class
        .deploy(@init_params)
        .expect('Deploy mockextension failed');

    IMockExtensionDispatcher { contract_address }
}


pub fn deploy_clt_base(params: BaseInitParams) -> ICLTBaseDispatcher {
    let contract_class = declare("CLTBase").unwrap().contract_class();
    let init_params = serialize(@params);
    let (contract_address, _) = contract_class.deploy(@init_params).expect('Deploy CLTBase failed');
    ICLTBaseDispatcher { contract_address }
}

pub fn deploy_clt_modules(owner: ContractAddress) -> ICLTModulesDispatcher {
    let contract_class = declare("CLTModules").unwrap().contract_class();
    let init_params = serialize(@owner);
    let (contract_address, _) = contract_class
        .deploy(@init_params)
        .expect('Deploy CLTModules failed');
    ICLTModulesDispatcher { contract_address }
}

pub fn deploy_fee_handler(
    timelock: ContractAddress,
    public_strategy_fee_registry: ProtocolFeeRegistry,
    private_strategy_fee_registry: ProtocolFeeRegistry,
) -> IGovernanceFeeHandlerDispatcher {
    let contract_class = declare("GovernanceFeeHandler").unwrap().contract_class();
    let init_params = serialize(
        @(timelock, public_strategy_fee_registry, private_strategy_fee_registry),
    );
    let (contract_address, _) = contract_class
        .deploy(@init_params)
        .expect('Deploy FeeHandler failed');
    IGovernanceFeeHandlerDispatcher { contract_address }
}

pub fn deploy_multiextension_deployer(
    class_hash: ClassHash, owner: ContractAddress,
) -> IMultiextensionDeployerDispatcher {
    let contract_class = declare("MultiextensionDeployer").unwrap().contract_class();
    let init_params = serialize(@(ekubo_core(), class_hash, owner));
    let (contract_address, _) = contract_class
        .deploy(@init_params)
        .expect('Deploy Multiext deployer failed');
    IMultiextensionDeployerDispatcher { contract_address }
}

pub fn deploy_twap_quoter(
    core: ICoreDispatcher, oracle: IOracleDispatcher, owner: ContractAddress,
) -> ICLTTwapQuoterDispatcher {
    let contract_class = declare("CLTTwapQuoter").unwrap().contract_class();
    let init_params = serialize(@(core, oracle, owner));
    let (contract_address, _) = contract_class
        .deploy(@init_params)
        .expect('Deploy Twap Quoter failed');
    ICLTTwapQuoterDispatcher { contract_address }
}

pub fn deploy_oracle(
    owner: ContractAddress,
    core: ICoreDispatcher,
    oracle_token: ContractAddress,
    operator: ContractAddress,
) -> IOracleDispatcher {
    let contract_class = declare("Oracle").unwrap().contract_class();
    let init_params = serialize(@(owner, core, oracle_token, operator));
    let (contract_address, _) = contract_class.deploy(@init_params).expect('Deploy Oracle failed');
    IOracleDispatcher { contract_address }
}

pub fn deploy_exit_module(
    base: ICLTBaseDispatcher, core: ICoreDispatcher, twap_quoter: ICLTTwapQuoterDispatcher,
) -> IExtensionDispatcher {
    let contract_class = declare("ExitModule").unwrap().contract_class();
    let init_params = serialize(@(base, core, twap_quoter));
    let (contract_address, _) = contract_class.deploy(@init_params).expect('Deploy Exit failed');
    IExtensionDispatcher { contract_address }
}

pub fn deploy_rebase_module(
    base: ICLTBaseDispatcher, core: ICoreDispatcher, twap_quoter: ICLTTwapQuoterDispatcher,
) -> IExtensionDispatcher {
    let contract_class = declare("RebaseModule").unwrap().contract_class();
    let init_params = serialize(@(base, core, twap_quoter));
    let (contract_address, _) = contract_class.deploy(@init_params).expect('Deploy Rebase failed');
    IExtensionDispatcher { contract_address }
}
