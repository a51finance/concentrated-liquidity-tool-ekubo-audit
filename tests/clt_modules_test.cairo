use clt_ekubo::clt_modules::CLTModules;
use clt_ekubo::clt_modules::CLTModules::InternalTrait;
use clt_ekubo::components::util::serialize;
use clt_ekubo::interfaces::clt_modules::{ICLTModules, StrategyPayload};
use starknet::storage::{StoragePathEntry, StoragePointerReadAccess};
use crate::utils::deploy::deploy_mock_extension;
use crate::utils::helpers::hash_intent;
use crate::utils::ekubo::{ekubo_core};


#[test]
#[should_panic(expected: ('CLTMOD: invalid intent',))]
fn test_intent_check() {
    let mut state = CLTModules::contract_state_for_testing();
    let intent_key: felt252 = hash_intent('MY INTENT');
    state._check_intent_key(intent_key);
}

#[test]
#[should_panic(expected: ('CLTMOD: invalid intent action',))]
fn test_check_mode_ids() {
    let mut state = CLTModules::contract_state_for_testing();
    let data = StrategyPayload {
        intent: hash_intent('MY INTENT'),
        action_name: hash_intent('MY ACTION'),
        data: serialize::<(u8, u8)>(@(5, 4)).span(),
    };
    state._check_mode_ids(data);
}

#[test]
fn test_set_intent() {
    let mut state = CLTModules::contract_state_for_testing();
    let intent_key: felt252 = hash_intent('MY INTENT');
    state.set_intent(intent_key);
    assert_eq!(state.intent.entry(intent_key).read(), true);
}

#[test]
#[fork("mainnet")]
fn test_set_intent_address() {
    let extension = deploy_mock_extension(1);

    let mut state = CLTModules::contract_state_for_testing();
    let intent_key: felt252 = hash_intent('MY INTENT');

    state.set_intent(intent_key);
    state.set_intent_address(intent_key, extension.contract_address);

    assert_eq!(state.intent_extension.entry(intent_key).read(), extension.contract_address);
}

#[test]
#[fork("mainnet")]
fn test_set_intent_action() {
    let mut state = CLTModules::contract_state_for_testing();
    let intent_key: felt252 = hash_intent('MY INTENT');
    let intent_action: felt252 = hash_intent('MY ACTION');
    state.set_intent(intent_key);
    state.set_intent_action(intent_key, intent_action);
    assert_eq!(state.intent_action.entry(intent_key).entry(intent_action).read(), true);
}

#[test]
#[fork("mainnet")]
fn test_validate_modes() {
    let mock_extension = deploy_mock_extension(1);
    let intent_key: felt252 = hash_intent('MY INTENT');
    let intent_action_name = hash_intent('ACTION ONE');

    let intent_one = StrategyPayload {
        intent: intent_key,
        action_name: intent_action_name,
        data: serialize::<(u8, u8)>(@(5, 4)).span(),
    };

    let action_data: (u256, Array<StrategyPayload>) = (1, array![intent_one]);
    let serialized_action_data: Span<felt252> = serialize::<
        (u256, Array<StrategyPayload>),
    >(@action_data)
        .span();

    let mut state = CLTModules::contract_state_for_testing();
    state.set_intent(intent_key);
    state.set_intent_address(intent_key, mock_extension.contract_address);
    state.set_intent_action(intent_key, intent_action_name);
    state.validate_modes(serialized_action_data, 0, 0);
}
