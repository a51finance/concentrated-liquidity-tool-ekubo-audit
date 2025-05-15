pub mod components {
    pub mod active_ticks_calculation;
    pub mod bytes_handler;
    pub mod constants;
    pub mod core_actions;
    pub mod hashing;
    pub mod liquidity_amounts;
    pub mod liquidity_shares;
    pub mod math;
    pub mod modes_ticks_calculation;
    pub mod position;
    pub mod strategy_fee_shares;
    pub mod user_positions;
    pub mod vault_actions;
    pub mod util;
}

pub mod extensions {
    pub mod exit {
        pub mod exit_module;
    }
    pub mod multiextension {
        pub mod interfaces {
            pub mod multiextension;
            pub mod multiextension_deployer;
        }
        pub mod utils {
            pub mod activate_extension;
            pub mod bit_math;
        }
        pub mod multiextension_deployer;
        pub mod multiextension;
    }
    pub mod oracle {
        pub mod interfaces {
            pub mod oracle;
        }
        pub mod oracle;
        pub mod snapshot;
    }
    pub mod rebasing {
        pub mod interfaces {
            pub mod rebase_module;
        }
        pub mod rebase_module;
    }
}

pub mod interfaces {
    pub mod clt_base;
    pub mod clt_modules;
    pub mod clt_twap_quoter;
    pub mod erc_4626;
    pub mod extension_input_validation;
    pub mod governance_fee_handler;
    pub mod avnu;
}

pub mod mock {
    pub mod erc20;
    pub mod erc4626;
    pub mod extension;
    mod mock_exchange;
}

pub mod types {
    pub mod base_init;
    pub mod callback_method;
    pub mod internal_params;
    pub mod pool_id;
}

pub mod clt_base;
pub mod clt_modules;
pub mod clt_twap_quoter;
pub mod governance_fee_handler;
