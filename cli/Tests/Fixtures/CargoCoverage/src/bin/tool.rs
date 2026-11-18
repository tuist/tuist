fn main() {
    println!("{}", cov_fixture::add(1, 1));
}

#[test]
fn tool_runs() {
    assert_eq!(cov_fixture::classify(0), "zero");
}
