use core::num::traits::Zero;
use snforge_std::{declare, DeclareResultTrait};
use starknet::get_contract_address;
use ekubo::interfaces::core::ICoreDispatcherTrait;
use ekubo::types::call_points::CallPoints;

use clt_ekubo::extensions::multiextension::interfaces::multiextension::PacketExtension;
use clt_ekubo::extensions::multiextension::interfaces::multiextension_deployer::IMultiextensionDeployerDispatcherTrait;

use crate::utils::deploy::deploy_multiextension_deployer;
use crate::utils::ekubo::{get_ekubo_pool_key, ekubo_core};
use crate::utils::fixtures::token2;

#[test]
#[fork("mainnet")]
fn test_multiextension_deploy() {
    let multiextension_class = *declare("Multiextension").unwrap().contract_class().class_hash;
    let deployer = deploy_multiextension_deployer(multiextension_class, get_contract_address());
    let multiextension = deployer
        .deploy_multiextension_and_init(
            array![PacketExtension { extension: Zero::zero(), extension_queue: 0 }].span(), 0,
        );

    let (token0, token1) = token2();
    let pool_key = get_ekubo_pool_key(
        token0.contract_address, token1.contract_address, multiextension, 0, 60,
    );
    assert_eq!(
        ekubo_core().get_call_points(pool_key.extension),
        CallPoints {
            before_initialize_pool: true,
            after_initialize_pool: true,
            before_swap: true,
            after_swap: true,
            before_update_position: true,
            after_update_position: true,
            before_collect_fees: true,
            after_collect_fees: true,
        },
    );
}
