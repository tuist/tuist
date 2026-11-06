use std::fs::OpenOptions;
use std::io::Write;

pub fn record_test(name: &str) {
    if let Ok(path) = std::env::var("TUIST_E2E_EXECUTIONS") {
        let mut file = OpenOptions::new()
            .create(true)
            .append(true)
            .open(path)
            .unwrap();
        file.write_all(format!("{name}\n").as_bytes()).unwrap();
    }
    if let Ok(delay) = std::env::var("TUIST_E2E_TEST_DELAY_MS") {
        std::thread::sleep(std::time::Duration::from_millis(delay.parse().unwrap()));
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn unit_one() {
        super::record_test("unit_one");
    }
    #[test]
    fn unit_two() {
        super::record_test("unit_two");
    }
}
