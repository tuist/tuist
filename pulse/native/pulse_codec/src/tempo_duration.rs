//! Positive time.Duration.String spelling, without floating-point conversion.
//! Callers prove nonnegative signed-int64 nanoseconds before subtraction.
pub(crate) fn format(ns: u64) -> String {
    if ns == 0 {
        return "0s".into();
    }
    if ns < 1000 {
        return format!("{ns}ns");
    }
    if ns < 1_000_000 {
        return format!("{}µs", decimal(ns, 1000, 3));
    }
    if ns < 1_000_000_000 {
        return format!("{}ms", decimal(ns, 1_000_000, 6));
    }
    let hours = ns / 3_600_000_000_000;
    let minutes = ns / 60_000_000_000 % 60;
    let seconds = ns % 60_000_000_000;
    let mut out = String::new();
    if hours > 0 {
        out.push_str(&format!("{hours}h"));
    }
    if hours > 0 || minutes > 0 {
        out.push_str(&format!("{minutes}m"));
    }
    out.push_str(&format!("{}s", decimal(seconds, 1_000_000_000, 9)));
    out
}
fn decimal(ns: u64, base: u64, precision: usize) -> String {
    let whole = ns / base;
    let remainder = ns % base;
    if remainder == 0 {
        return whole.to_string();
    }
    let fraction = format!("{remainder:0precision$}");
    format!("{whole}.{}", fraction.trim_end_matches('0'))
}
#[cfg(test)]
mod tests {
    #[test]
    fn public_go_duration_spellings() {
        use crate::json_read::Parser;
        use crate::trace_search::string;
        let cases = Parser::new(include_bytes!(
            "../../../test/fixtures/traces/tempo-trace-duration-format-oracle.json"
        ))
        .raw_array()
        .unwrap();
        assert!(cases.len() >= 1024);
        for row in cases {
            let pair = Parser::new(row).raw_array().unwrap();
            let ns = string(pair[0]).unwrap();
            let expected = string(pair[1]).unwrap();
            assert_eq!(super::format(ns.parse().unwrap()), expected, "{ns}");
        }
    }
}
