pub mod Constants {
    pub const MAX_MANAGEMENT_FEE: u256 = 200_000_000_000_000_000;

    pub const MAX_PERFORMANCE_FEE: u256 = 200_000_000_000_000_000;

    pub const MAX_AUTOMATION_FEE: u256 = 200_000_000_000_000_000;

    pub const MAX_STRATEGY_CREATION_FEE: u256 = 500_000_000_000_000_000;

    pub const WAD: u256 = 1_000_000_000_000_000_000;

    pub const MIN_INITIAL_SHARES: u256 = 1_000;

    // 2**128
    pub const Q128: u256 = 0x100000000000000000000000000000000;

    // poseidon_hash_span(['IS_EXIT'])
    pub const IS_EXIT: felt252 = 0x1e44e5c7299993ad4d8d6d5374bc24c119b279ac65dbec6ae85266b200d73ef;

    // poseidon_hash_span(['IS_PARTIAL'])
    pub const IS_PARTIAL: felt252 =
        0x1ab32d9c340f0805cee09ef865b59c2c8de6313663965fdc6a4ec9ce85b2d8a;

    // poseidon_hash_span(['EXIT_STRATEGY'])
    pub const EXIT_STRATEGY: felt252 =
        0x10c0d45e7cb59c5753b0ca20dfcefa85b8f7baa0c165f2ea357e1c71e538706;

    // poseidon_hash_span(['REBASE_STRATEGY'])
    pub const REBASE_STRATEGY: felt252 =
        0x3746646932205cd891b35b4bab681234594df81ee9e940ce91c7dd822dec0f0;

    // poseidon_hash_span(['LIQUIDITY_DISTRIBUTION'])
    pub const LIQUIDITY_DISTRIBUTION: felt252 =
        0x3846754304bdd480d18d5c8026a6f446c7d60c7a6f2172330d16de40eaa40dd;

    // poseidon_hash_span(['ACTIVE_REBALANCE'])
    pub const ACTIVE_REBALANCE: felt252 =
        0x53d1a6e2b22dc86a7363231620b55af15efd72faa1e1b8d4ada0878a2a9a00e;

    // poseidon_hash_span(['EXIT_AND_HOLD'])
    pub const EXIT_AND_HOLD: felt252 =
        0x535c79f7c43a1fb2fcec9d27eb299c5dd639aa236d02c8baa8c9a86dc75cb24;

    // poseidon_hash_span(['EXIT_AND_SWAP'])
    pub const EXIT_AND_SWAP: felt252 =
        0x1a5b03930274acece9191f056a54777f99d0d2f62a7e96e088ffe076df359c8;

    // poseidon_hash_span(['EXIT_AND_REINVEST'])
    pub const EXIT_AND_REINVEST: felt252 =
        0x2afdbf89c357786f3dfb617271b588afb9d7d653f51e95f55dd8e335754bfad;
}

