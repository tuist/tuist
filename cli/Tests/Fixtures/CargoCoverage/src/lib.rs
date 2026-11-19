pub mod shapes;

/// Adds.
/// ```
/// assert_eq!(cov_fixture::add(1, 2), 3);
/// ```
pub fn add(a: i32, b: i32) -> i32 {
    a + b
}

pub fn classify(n: i32) -> &'static str {
    if n < 0 {
        "negative"
    } else if n == 0 {
        "zero"
    } else {
        "positive"
    }
}

pub fn apply<T: Copy>(value: T, f: impl Fn(T) -> T) -> T {
    let doubled = f(value);
    f(doubled)
}

#[cfg(test)]
mod tests {
    #[test]
    fn adds() {
        assert_eq!(super::add(2, 2), 4);
    }

    #[test]
    fn classifies_negative() {
        assert_eq!(super::classify(-1), "negative");
    }

    #[test]
    fn fails_on_request() {
        assert!(std::env::var_os("TUIST_FIXTURE_FAIL").is_none());
    }
}
