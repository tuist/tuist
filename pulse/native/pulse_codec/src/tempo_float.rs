//! TraceQL's float spelling: Go FormatFloat('g', -1, 64), with
//! a decimal suffix for integral fixed-point values to retain float identity.
pub(crate) fn format(value: f64) -> Option<String> {
    // Tempo 2.9 Static.EncodeToString appends .0 whenever FormatFloat lacks
    // both e and '.', including these non-finite classes.
    if value.is_nan() {
        return Some("NaN.0".into());
    }
    if value == f64::INFINITY {
        return Some("+Inf.0".into());
    }
    if value == f64::NEG_INFINITY {
        return Some("-Inf.0".into());
    }
    let sign = if value.is_sign_negative() { "-" } else { "" };
    if value == 0.0 {
        return Some(format!("{sign}0.0"));
    }
    let mut buffer = ryu::Buffer::new();
    let raw = buffer.format_finite(value.abs());
    let (mantissa, exponent) = raw.split_once('e').unwrap_or((raw, "0"));
    let exponent: i32 = exponent.parse().ok()?;
    let point = mantissa.find('.').unwrap_or(mantissa.len()) as i32 + exponent;
    let all = mantissa.replace('.', "");
    let leading = all.len() - all.trim_start_matches('0').len();
    let digits = all.trim_start_matches('0').trim_end_matches('0');
    let exponent = point - leading as i32 - 1;
    let text = if !(-4..6).contains(&exponent) {
        let tail = if digits.len() > 1 {
            format!(".{}", &digits[1..])
        } else {
            String::new()
        };
        format!(
            "{}{tail}e{}{:02}",
            &digits[..1],
            if exponent < 0 { "-" } else { "+" },
            exponent.abs()
        )
    } else if exponent < 0 {
        format!("0.{}{}", "0".repeat((-exponent - 1) as usize), digits)
    } else {
        let point = (exponent + 1) as usize;
        if point >= digits.len() {
            format!("{}{}.0", digits, "0".repeat(point - digits.len()))
        } else {
            format!("{}.{}", &digits[..point], &digits[point..])
        }
    };
    Some(format!("{sign}{text}"))
}
#[cfg(test)]
mod tests {
    use super::format;
    #[test]
    fn traceql_float_identity_and_exponent_boundaries() {
        for (input, expected) in [
            (0.0, "0.0"),
            (-0.0, "-0.0"),
            (1.0, "1.0"),
            (100000.0, "100000.0"),
            (1e6, "1e+06"),
            (1e-4, "0.0001"),
            (1e-5, "1e-05"),
            (f64::from_bits(1), "5e-324"),
        ] {
            assert_eq!(format(input).as_deref(), Some(expected));
        }
        assert_eq!(format(f64::NAN).as_deref(), Some("NaN.0"));
        assert_eq!(format(f64::INFINITY).as_deref(), Some("+Inf.0"));
        assert_eq!(format(f64::NEG_INFINITY).as_deref(), Some("-Inf.0"));
    }
}
