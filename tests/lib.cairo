pub mod clt_base {
    pub mod claim_fee;
    pub mod deposit;
    pub mod increase_liquidity;
    pub mod strategy;
    pub mod shift_liquidity;
    pub mod withdraw;
}

pub mod utils {
    pub mod deploy;
    pub mod ekubo;
    pub mod erc20;
    pub mod fixtures;
    pub mod helpers;
}

pub mod clt_modules_test;
pub mod exit_module_test;
pub mod governance_fee_handler_test;
pub mod multiextension_deployer_test;
pub mod rebase_module_test;
