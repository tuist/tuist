mod common;

#[test]
fn applies() {
    assert_eq!(common::helper(), 5);
}

#[test]
fn grows() {
    let mut s = cov_fixture::shapes::Square(1.0);
    s.grow(1.0);
    assert_eq!(s.area(), 4.0);
}
