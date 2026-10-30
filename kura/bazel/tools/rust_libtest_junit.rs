//! Converts libtest JSON events to per-case JUnit without an interpreter.
use std::io::{self, BufRead, Write};

fn escape(value: &str) -> String {
    value
        .chars()
        .filter(|ch| matches!(ch, '\t' | '\n' | '\r') || *ch >= ' ')
        .flat_map(|ch| match ch {
            '&' => "&amp;".chars().collect::<Vec<_>>(),
            '<' => "&lt;".chars().collect(),
            '>' => "&gt;".chars().collect(),
            '"' => "&quot;".chars().collect(),
            '\'' => "&apos;".chars().collect(),
            _ => vec![ch],
        })
        .collect()
}

fn report(suite: &str, input: impl BufRead, mut output: impl Write) -> io::Result<()> {
    let mut cases = Vec::new();
    let mut failures = 0;
    let mut skipped = 0;
    for line in input.split(b'\n') {
        let line = line?;
        let Ok(event) = serde_json::from_slice::<serde_json::Value>(&line) else {
            continue;
        };
        if event["type"] != "test" {
            continue;
        }
        let verdict = event["event"].as_str().unwrap_or_default();
        if !matches!(verdict, "ok" | "failed" | "ignored") {
            continue;
        }
        let name = escape(event["name"].as_str().unwrap_or_default());
        let duration = event["exec_time"].as_f64().unwrap_or(0.0);
        let body = match verdict {
            "failed" => {
                failures += 1;
                let message = event["stdout"].as_str().unwrap_or_default().trim();
                format!(
                    "<failure message=\"test failed\">{}</failure>",
                    escape(if message.is_empty() {
                        "test failed"
                    } else {
                        message
                    })
                )
            }
            "ignored" => {
                skipped += 1;
                "<skipped/>".into()
            }
            _ => String::new(),
        };
        cases.push(format!("    <testcase name=\"{name}\" classname=\"{}\" time=\"{duration:.6}\">{body}</testcase>", escape(suite)));
    }
    writeln!(
        output,
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<testsuites>"
    )?;
    writeln!(
        output,
        "  <testsuite name=\"{}\" tests=\"{}\" failures=\"{failures}\" skipped=\"{skipped}\">",
        escape(suite),
        cases.len()
    )?;
    for case in cases {
        writeln!(output, "{case}")?;
    }
    writeln!(output, "  </testsuite>\n</testsuites>")
}

fn main() -> io::Result<()> {
    let args = std::env::args().collect::<Vec<_>>();
    if args.len() != 4 {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "expected suite, raw log and XML path",
        ));
    }
    let input = io::BufReader::new(std::fs::File::open(&args[2])?);
    let mut output = io::BufWriter::new(std::fs::File::create(&args[3])?);
    report(&args[1], input, &mut output)?;
    output.flush()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn reports_terminal_cases_and_preserves_suite_identity() {
        let input = br#"foreign output
{invalid json
{"type":"suite","event":"started"}
{"type":"test","name":"case&\"<>","event":"started"}
{"type":"test","name":"case&\"<>","event":"ok","exec_time":0.125}
{"type":"test","name":"failed","event":"failed","stdout":" <bad>&\"\u0001 ","exec_time":null}
{"type":"test","name":"ignored","event":"ignored"}
{"type":"test","name":"empty failure","event":"failed"}
"#;
        let mut output = Vec::new();
        report("public&\"suite", input.as_slice(), &mut output).unwrap();
        let output = String::from_utf8(output).unwrap();
        assert!(output.contains("tests=\"4\" failures=\"2\" skipped=\"1\""));
        assert!(output.contains("name=\"case&amp;&quot;&lt;&gt;\""));
        assert!(output.contains("classname=\"public&amp;&quot;suite\" time=\"0.125000\""));
        assert!(output.contains("&lt;bad&gt;&amp;&quot;"));
        assert!(output.contains("<skipped/>"));
        assert!(output.contains(">test failed</failure>"));
        assert!(!output.contains('\u{1}'));
    }
    #[test]
    fn empty_or_invalid_utf8_output_still_produces_a_report() {
        for input in [b"".as_slice(), b"\xff\xfe\n".as_slice()] {
            let mut output = Vec::new();
            report("suite", input, &mut output).unwrap();
            assert!(
                String::from_utf8(output)
                    .unwrap()
                    .contains("tests=\"0\" failures=\"0\" skipped=\"0\"")
            );
        }
    }
    #[test]
    fn input_and_output_failures_are_not_success() {
        let input = io::BufReader::new(std::fs::File::open("/").unwrap());
        assert!(report("suite", input, Vec::new()).is_err());
        struct Broken;
        impl Write for Broken {
            fn write(&mut self, _: &[u8]) -> io::Result<usize> {
                Err(io::Error::other("fixture write failed"))
            }
            fn flush(&mut self) -> io::Result<()> {
                Ok(())
            }
        }
        assert!(report("suite", b"".as_slice(), Broken).is_err());
    }
}
