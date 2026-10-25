use atlas_core::SECTIONS;
use std::io::{self, Write};

const HELP: &str = "Atlas, your workspace from the terminal.

Usage:
  atlas sections       List workspace sections and their destinations
  atlas url <section>  Print a section's URL for use in scripts
  atlas --help         Show this help

Pages require Atlas sign-in in your browser. This command does not store
credentials, fetch customer data, or open a browser automatically.
";

#[derive(Debug)]
pub enum Error {
    Usage(String),
    Io(io::Error),
}

impl From<io::Error> for Error {
    fn from(error: io::Error) -> Self {
        Self::Io(error)
    }
}

pub fn run(arguments: &[&str], output: &mut impl Write) -> Result<(), Error> {
    match arguments {
        [] | ["--help" | "-h"] => output.write_all(HELP.as_bytes())?,
        ["sections"] => {
            for section in SECTIONS {
                write!(output, "{}\t", section.id)?;
                output.write_all(section.title.to_bytes())?;
                output.write_all(b"\t")?;
                output.write_all(section.url.to_bytes())?;
                output.write_all(b"\n")?;
            }
        }
        ["url", id] => {
            let section = SECTIONS
                .iter()
                .find(|section| section.id == *id)
                .ok_or_else(|| {
                    let valid = SECTIONS
                        .iter()
                        .map(|section| section.id)
                        .collect::<Vec<_>>()
                        .join(", ");
                    Error::Usage(format!("unknown section '{id}'; valid sections: {valid}"))
                })?;
            output.write_all(section.url.to_bytes())?;
            output.write_all(b"\n")?;
        }
        ["url"] => return Err(Error::Usage("'url' requires a section".into())),
        ["sections" | "url" | "--help" | "-h", ..] => {
            return Err(Error::Usage("unexpected arguments".into()));
        }
        [command, ..] => return Err(Error::Usage(format!("unknown command '{command}'"))),
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn output(arguments: &[&str]) -> String {
        let mut output = Vec::new();
        run(arguments, &mut output).unwrap();
        String::from_utf8(output).unwrap()
    }

    #[test]
    fn help_is_available_without_arguments_and_with_both_flags() {
        for arguments in [&[][..], &["--help"][..], &["-h"][..]] {
            assert_eq!(output(arguments), HELP);
        }
    }

    #[test]
    fn lists_every_shared_section_in_catalog_order() {
        let text = output(&["sections"]);
        let lines: Vec<_> = text.lines().collect();
        assert_eq!(lines.len(), SECTIONS.len());
        for (line, section) in lines.iter().zip(SECTIONS) {
            assert_eq!(
                *line,
                format!(
                    "{}\t{}\t{}",
                    section.id,
                    section.title.to_str().unwrap(),
                    section.url.to_str().unwrap()
                )
            );
        }
    }

    #[test]
    fn url_output_is_only_the_shared_destination_and_a_newline() {
        for section in SECTIONS {
            assert_eq!(
                output(&["url", section.id]),
                format!("{}\n", section.url.to_str().unwrap())
            );
        }
    }

    #[test]
    fn unknown_sections_return_available_ids_and_no_stdout() {
        let mut output = Vec::new();
        let Err(Error::Usage(message)) = run(&["url", "missing"], &mut output) else {
            panic!("expected a usage error");
        };
        assert!(message.contains("unknown section 'missing'"));
        for section in SECTIONS {
            assert!(message.contains(section.id));
        }
        assert!(output.is_empty());
    }

    #[test]
    fn invalid_commands_and_extra_arguments_are_rejected_without_stdout() {
        for arguments in [
            vec!["unknown"],
            vec!["url"],
            vec!["url", "tasks", "extra"],
            vec!["sections", "extra"],
            vec!["--help", "extra"],
            vec!["url", "TASKS"],
        ] {
            let mut output = Vec::new();
            assert!(matches!(run(&arguments, &mut output), Err(Error::Usage(_))));
            assert!(output.is_empty());
        }
    }

    #[test]
    fn output_failures_are_not_swallowed() {
        struct FailingWriter;
        impl Write for FailingWriter {
            fn write(&mut self, _buffer: &[u8]) -> io::Result<usize> {
                Err(io::Error::new(io::ErrorKind::BrokenPipe, "closed pipe"))
            }
            fn flush(&mut self) -> io::Result<()> {
                Ok(())
            }
        }
        assert!(
            matches!(run(&["sections"], &mut FailingWriter), Err(Error::Io(error)) if error.kind() == io::ErrorKind::BrokenPipe)
        );
    }
}
