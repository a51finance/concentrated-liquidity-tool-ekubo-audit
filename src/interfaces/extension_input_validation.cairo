use clt_ekubo::interfaces::clt_modules::StrategyPayload;

//interface must be implemented by an intent for data validation
#[starknet::interface]
pub trait IExtensionInputValidation<TContractState> {
    //check the validity of intent data
    fn check_input_data(self: @TContractState, data: StrategyPayload) -> bool;
}
