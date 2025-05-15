// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts for Cairo v0.20.0 (utils/math.cairo)

pub mod Math {
    use core::integer::u512_safe_div_rem_by_u256;
    use core::num::traits::WideMul;

    pub fn try_sub(x: u256, y: u256) -> u256 {
        if y > x {
            return 0;
        }
        x - y
    }

    /// Returns the quotient of floor (x * y / denominator)
    /// Uses `wide_mul` and `u512_safe_div_rem_by_u256` for precision.
    ///
    /// Requirements:
    ///
    /// - `denominator` must not be zero.
    /// - The quotient must not overflow u256.
    pub fn mul_div(x: u256, y: u256, denominator: u256) -> u256 {
        let (q, _) = _raw_u256_mul_div(x, y, denominator);
        q
    }

    /// Returns the quotient and remainder of x * y / denominator.
    /// Uses `wide_mul` and `u512_safe_div_rem_by_u256` for precision.
    ///
    /// Requirements:
    ///
    /// - `denominator` must not be zero.
    /// - The quotient must not overflow u256.
    fn _raw_u256_mul_div(x: u256, y: u256, denominator: u256) -> (u256, u256) {
        let denominator = denominator.try_into().expect('mul_div division by zero');
        let p = x.wide_mul(y);
        let (q, r) = u512_safe_div_rem_by_u256(p, denominator);
        let q = q.try_into().expect('mul_div quotient > u256');
        (q, r)
    }
}

