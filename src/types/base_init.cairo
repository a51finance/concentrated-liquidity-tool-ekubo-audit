use starknet::ContractAddress;

use ekubo::interfaces::core::ICoreDispatcher;
use clt_ekubo::interfaces::clt_modules::ICLTModulesDispatcher;
use clt_ekubo::interfaces::governance_fee_handler::IGovernanceFeeHandlerDispatcher;


#[derive(Drop, Serde)]
pub struct BaseInitParams {
    pub owner: ContractAddress,
    pub name: ByteArray,
    pub symbol: ByteArray,
    pub core: ICoreDispatcher,
    pub clt_modules: ICLTModulesDispatcher,
    pub fee_handler: IGovernanceFeeHandlerDispatcher,
    pub eth: ContractAddress,
}
