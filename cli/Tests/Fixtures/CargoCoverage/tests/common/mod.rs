pub fn helper() -> i32 {
    cov_fixture::apply(3, |x| x + 1)
}
