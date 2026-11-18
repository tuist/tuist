pub struct Square(pub f64);

impl Square {
    pub fn area(&self) -> f64 {
        self.0 * self.0
    }

    pub fn grow(&mut self, by: f64) {
        self.0 += by;
    }
}

#[cfg(test)]
mod tests {
    use super::Square;

    #[test]
    fn area() {
        assert_eq!(Square(2.0).area(), 4.0);
    }
}
