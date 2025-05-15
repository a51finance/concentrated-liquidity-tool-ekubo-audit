use starknet::storage::{StoragePointerReadAccess};

use clt_ekubo::components::constants::Constants;
use clt_ekubo::interfaces::governance_fee_handler::{IGovernanceFeeHandler, ProtocolFeeRegistry};
use clt_ekubo::governance_fee_handler::GovernanceFeeHandler;
use clt_ekubo::governance_fee_handler::GovernanceFeeHandler::_check_limit;


#[test]
fn test_set_public_fee_registry() {
    let mut state = GovernanceFeeHandler::contract_state_for_testing();
    let public_fee_registry = ProtocolFeeRegistry {
        lp_automation_fee: 1, strategy_creation_fee: 2,
    };
    state.set_public_fee_registry(public_fee_registry);

    let stored_public_fee_registry = state.public_strategy_fee_registry.read();
    assert_eq!(stored_public_fee_registry.lp_automation_fee, public_fee_registry.lp_automation_fee);
    assert_eq!(
        stored_public_fee_registry.strategy_creation_fee, public_fee_registry.strategy_creation_fee,
    );
}

#[test]
fn test_set_private_fee_registry() {
    let mut state = GovernanceFeeHandler::contract_state_for_testing();
    let private_fee_registry = ProtocolFeeRegistry {
        lp_automation_fee: 1, strategy_creation_fee: 2,
    };
    state.set_private_fee_registry(private_fee_registry);

    let stored_private_fee_registry = state.private_strategy_fee_registry.read();
    assert_eq!(
        stored_private_fee_registry.lp_automation_fee, private_fee_registry.lp_automation_fee,
    );
    assert_eq!(
        stored_private_fee_registry.strategy_creation_fee,
        private_fee_registry.strategy_creation_fee,
    );
}

#[test]
fn test_get_governance_fee() {
    let mut state = GovernanceFeeHandler::contract_state_for_testing();
    let private_fee_registry = ProtocolFeeRegistry {
        lp_automation_fee: 1, strategy_creation_fee: 2,
    };
    let public_fee_registry = ProtocolFeeRegistry {
        lp_automation_fee: 3, strategy_creation_fee: 4,
    };
    state.set_private_fee_registry(private_fee_registry);
    state.set_public_fee_registry(public_fee_registry);

    let (lp_automation_fee, strategy_creation_fee) = state.get_governance_fee(true);
    assert_eq!(lp_automation_fee, private_fee_registry.lp_automation_fee);
    assert_eq!(strategy_creation_fee, private_fee_registry.strategy_creation_fee);

    let (lp_automation_fee, strategy_creation_fee) = state.get_governance_fee(false);
    assert_eq!(lp_automation_fee, public_fee_registry.lp_automation_fee);
    assert_eq!(strategy_creation_fee, public_fee_registry.strategy_creation_fee);
}

#[test]
#[should_panic(expected: ('FH: lp automation fle',))]
fn test_check_limit_lp_automation() {
    _check_limit(
        ProtocolFeeRegistry {
            lp_automation_fee: Constants::MAX_AUTOMATION_FEE + 1, strategy_creation_fee: 0,
        },
    )
}

#[test]
#[should_panic(expected: ('FH: strategy fle',))]
fn test_check_limit_strategy_fee() {
    _check_limit(
        ProtocolFeeRegistry {
            lp_automation_fee: 0, strategy_creation_fee: Constants::MAX_STRATEGY_CREATION_FEE + 1,
        },
    )
}
