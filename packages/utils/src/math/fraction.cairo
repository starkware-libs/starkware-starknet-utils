use core::num::traits::{One, Zero};
use starkware_utils::errors::assert_with_byte_array;
use starkware_utils::math::abs::Abs;

#[derive(Copy, Drop, Hash, Serde)]
pub struct Fraction {
    numerator: i128,
    denominator: u128,
}

pub fn validate_fraction_ratio<N, D, +Into<N, i128>, +Drop<N>, +Into<D, u128>, +Drop<D>>(
    n1: i128, d1: u128, n2: i128, d2: u128, err: ByteArray,
) {
    let f1 = FractionTrait::new(numerator: n1, denominator: d1);
    let f2 = FractionTrait::new(numerator: n2, denominator: d2);
    assert_with_byte_array(f1 <= f2, err);
}

#[generate_trait]
pub impl FractionlImpl of FractionTrait {
    fn new(numerator: i128, denominator: u128) -> Fraction {
        /// TODO : consider  reducing a fraction to its simplest form.
        assert(denominator != 0, 'Denominator must be non-zero');
        Fraction { numerator, denominator }
    }

    fn numerator(self: @Fraction) -> i128 {
        *self.numerator
    }

    fn denominator(self: @Fraction) -> u128 {
        *self.denominator
    }
}

impl FractionNeg of Neg<Fraction> {
    fn neg(a: Fraction) -> Fraction {
        Fraction { numerator: -a.numerator, denominator: a.denominator }
    }
}

impl FractionZero of Zero<Fraction> {
    fn zero() -> Fraction {
        Fraction { numerator: 0, denominator: 1 }
    }

    fn is_zero(self: @Fraction) -> bool {
        *self.numerator == 0
    }

    fn is_non_zero(self: @Fraction) -> bool {
        !self.is_zero()
    }
}

impl FractionOne of One<Fraction> {
    fn one() -> Fraction {
        Fraction { numerator: 1, denominator: 1 }
    }

    fn is_one(self: @Fraction) -> bool {
        let numerator: i128 = *self.numerator;
        let denominator: u128 = *self.denominator;
        if numerator < 0 {
            return false;
        }
        numerator.abs() == denominator
    }
    /// Returns `false` if `self` is equal to the multiplicative identity.
    fn is_non_one(self: @Fraction) -> bool {
        !self.is_one()
    }
}

impl FractionPartialEq of PartialEq<Fraction> {
    fn eq(lhs: @Fraction, rhs: @Fraction) -> bool {
        (lhs <= rhs) && (lhs >= rhs)
    }
}

impl FractionPartialOrd of PartialOrd<Fraction> {
    fn lt(lhs: Fraction, rhs: Fraction) -> bool {
        /// denote lhs as a/b and rhs as c/d
        /// case a <= 0 and c > 0
        if lhs.numerator <= 0 && rhs.numerator > 0 {
            return true;
        }
        /// case a >= 0 and c <= 0
        if lhs.numerator >= 0 && rhs.numerator <= 0 {
            return false;
        }

        // case a < 0 and c = 0
        if lhs.numerator < 0 && rhs.numerator == 0 {
            return true;
        }

        /// from now c != 0 and a != 0, a and c have the same sign.
        /// left = |a| * d
        let mut left: u256 = lhs.numerator.abs().into();
        left = left * rhs.denominator.into();

        /// right = |c| * b
        let mut right: u256 = rhs.numerator.abs().into();
        right = right * lhs.denominator.into();

        /// case a > 0 and c > 0
        if lhs.numerator > 0 {
            return left < right;
        }
        /// The remaining case is a < 0 and c < 0
        left > right
    }
}


#[cfg(test)]
mod tests {
    use core::num::traits::{One, Zero};
    use super::*;


    #[test]
    fn fraction_neg_test() {
        let f1 = FractionTrait::new(numerator: 1, denominator: 2);
        let f2 = -f1;
        assert!(f2.numerator == -1 && f2.denominator == 2, "Fraction negation failed");
    }


    #[test]
    fn fraction_eq_test() {
        let f1 = FractionTrait::new(numerator: 1, denominator: 2);
        let f2 = FractionTrait::new(numerator: 6, denominator: 12);
        assert!(f1 == f2, "Fraction equality failed");
    }

    #[test]
    fn fraction_zero_test() {
        let f1 = Zero::<Fraction>::zero();
        assert!(f1.numerator == 0 && f1.denominator == 1, "Fraction zero failed");
        assert!(f1.is_zero(), "Fraction is_zero failed");
        let f2 = FractionTrait::new(numerator: 1, denominator: 2);
        assert!(f2.is_non_zero(), "Fraction is_non_zero failed");
    }

    #[test]
    fn fraction_one_test() {
        let f1 = One::<Fraction>::one();
        assert!(f1.numerator == 1 && f1.denominator == 1, "Fraction one failed");
        assert!(f1.is_one(), "Fraction is_one failed");
        let f2 = FractionTrait::new(numerator: 1, denominator: 2);
        assert!(f2.is_non_one(), "Fraction is_non_one failed");
        let f3 = FractionTrait::new(numerator: 30, denominator: 30);
        assert!(f3.is_one(), "Fraction is_one failed");
    }

    #[test]
    #[should_panic(expected: 'Denominator must be non-zero')]
    fn fraction_new_test_panic() {
        FractionTrait::new(numerator: 1, denominator: 0);
    }

    #[test]
    fn fraction_parial_ord_test() {
        let f1 = FractionTrait::new(numerator: 1, denominator: 2);
        let f2 = FractionTrait::new(numerator: 1, denominator: 3);
        assert!(f1 > f2, "Fraction partial ord failed");
        assert!(-f2 > -f1, "Fraction partial ord failed");
        assert!(f1 >= f2, "Fraction partial ord failed");
        assert!(-f2 >= -f1, "Fraction partial ord failed");
        assert!(f2 < f1, "Fraction partial ord failed");
        assert!(-f1 < -f2, "Fraction partial ord failed");
        assert!(f2 <= f1, "Fraction partial ord failed");
        assert!(-f1 <= -f2, "Fraction partial ord failed");
    }


    #[test]
    fn fraction_numerator_test() {
        let f: Fraction = FractionTrait::new(numerator: 1, denominator: 2);
        assert_eq!(f.numerator(), 1);
    }

    #[test]
    fn fraction_denominator_test() {
        let f: Fraction = FractionTrait::new(numerator: 1, denominator: 2);
        assert_eq!(f.denominator(), 2);
    }
}
