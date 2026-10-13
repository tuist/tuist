mod command;

use std::io;
use std::process::ExitCode;

fn main() -> ExitCode {
    let arguments: Result<Vec<_>, _> = std::env::args_os()
        .skip(1)
        .map(|argument| argument.into_string())
        .collect();
    let Ok(arguments) = arguments else {
        eprintln!("atlas: arguments must be valid UTF-8");
        return ExitCode::from(2);
    };
    let arguments: Vec<_> = arguments.iter().map(String::as_str).collect();
    match command::run(&arguments, &mut io::stdout().lock()) {
        Ok(()) => ExitCode::SUCCESS,
        Err(command::Error::Io(error)) if error.kind() == io::ErrorKind::BrokenPipe => {
            ExitCode::SUCCESS
        }
        Err(command::Error::Io(error)) => {
            eprintln!("atlas: {error}");
            ExitCode::FAILURE
        }
        Err(command::Error::Usage(message)) => {
            eprintln!("atlas: {message}\nRun 'atlas --help' for usage.");
            ExitCode::from(2)
        }
    }
}
