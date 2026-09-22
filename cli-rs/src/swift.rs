//! Runs a Tuist command in the linked Swift code.
//!
//! From the terminal the command runs in this process, with the terminal attached, and
//! the Swift exit code becomes ours. The Swift CLI sets up process-wide state that can
//! only be set up once, so a long-lived tool server (`tuist --mcp`) runs every command
//! in a fresh child copy of this binary and returns what it printed.

use std::ffi::{CString, c_char, c_int};
use std::process::Stdio;
use std::sync::atomic::{AtomicBool, Ordering};

use incurs::command::{CommandContext, CommandHandler};
use incurs::output::CommandResult;
use serde_json::{Value, json};

unsafe extern "C" {
    fn tuist_run(argc: c_int, argv: *const *const c_char) -> c_int;
}

/// Whether commands may run in this process. False while serving tools.
static IN_PROCESS: AtomicBool = AtomicBool::new(true);

/// Makes every later command run in a child process.
pub fn run_commands_in_children() {
    IN_PROCESS.store(false, Ordering::SeqCst);
}

/// Handler shared by every command in the tree.
pub struct SwiftCommand;

#[async_trait::async_trait]
impl CommandHandler for SwiftCommand {
    async fn run(&self, ctx: CommandContext) -> CommandResult {
        let argv: Vec<String> = ctx.args["argv"]
            .as_array()
            .map(|tokens| {
                tokens
                    .iter()
                    .filter_map(|token| token.as_str().map(str::to_owned))
                    .collect()
            })
            .unwrap_or_default();

        if IN_PROCESS.swap(false, Ordering::SeqCst) {
            let code = tokio::task::spawn_blocking(move || run_in_process(&argv))
                .await
                .unwrap_or(1);
            return CommandResult::Ok {
                data: Value::Null,
                cta: None,
                exit_code: Some(code),
            };
        }
        run_in_child(&argv).await
    }
}

fn program_name() -> String {
    std::env::args().next().unwrap_or_else(|| "tuist".into())
}

fn run_in_process(argv: &[String]) -> i32 {
    let arguments: Vec<CString> = std::iter::once(program_name())
        .chain(argv.iter().cloned())
        .map(|argument| CString::new(argument).expect("argument contains a NUL byte"))
        .collect();
    let pointers: Vec<*const c_char> = arguments.iter().map(|argument| argument.as_ptr()).collect();
    unsafe { tuist_run(pointers.len() as c_int, pointers.as_ptr()) }
}

async fn run_in_child(argv: &[String]) -> CommandResult {
    let executable = match std::env::current_exe() {
        Ok(path) => path,
        Err(error) => return error_result(format!("Cannot locate the tuist executable: {error}")),
    };
    let output = tokio::process::Command::new(executable)
        .args(argv)
        .stdin(Stdio::null())
        .output()
        .await;
    let output = match output {
        Ok(output) => output,
        Err(error) => return error_result(format!("Cannot run tuist: {error}")),
    };
    let stdout = String::from_utf8_lossy(&output.stdout).into_owned();
    let stderr = String::from_utf8_lossy(&output.stderr).into_owned();
    if let Some(question) = unanswerable_prompt(&stderr) {
        return CommandResult::Error {
            code: "INPUT_REQUIRED".into(),
            message: format!(
                "This command asks \"{question}\" and a tool call cannot answer it. \
                 Pass the answer as a flag (see the command's usage) or run it in a terminal."
            ),
            retryable: false,
            exit_code: Some(1),
            cta: None,
        };
    }
    let exit_code = output.status.code().unwrap_or(1);
    let mut data = json!({
        "exitCode": exit_code,
        "stdout": stdout,
        "stderr": stderr,
    });
    if let Ok(parsed) = serde_json::from_str::<Value>(&stdout) {
        data["json"] = parsed;
    }
    CommandResult::Ok {
        data,
        cta: None,
        exit_code: Some(exit_code),
    }
}

/// Tuist's prompt library stops the process when it has no terminal to ask on, naming
/// the question it wanted to ask. Returns that question.
fn unanswerable_prompt(stderr: &str) -> Option<&str> {
    let line = stderr
        .lines()
        .find(|line| line.contains("can't be prompted in a non-interactive session"))?;
    let start = line.find('\'')? + 1;
    let end = start + line[start..].find('\'')?;
    Some(&line[start..end])
}

fn error_result(message: String) -> CommandResult {
    CommandResult::Error {
        code: "TUIST_UNAVAILABLE".into(),
        message,
        retryable: false,
        exit_code: Some(1),
        cta: None,
    }
}

#[cfg(test)]
mod tests {
    use super::{run_in_process, unanswerable_prompt};

    /// The Swift CLI sets up process-wide state once, so the linked library must refuse a
    /// second run in the same process instead of crashing or running on stale state.
    #[test]
    fn a_second_in_process_run_is_refused() {
        assert_eq!(run_in_process(&["version".to_string()]), 0);
        assert_eq!(run_in_process(&["version".to_string()]), 70);
    }

    #[test]
    fn finds_the_question_a_prompt_could_not_ask() {
        let stderr = "Noora/SingleChoicePrompt.swift:48: Fatal error: 'How would you like to start with Tuist?' can't be prompted in a non-interactive session.\n";
        assert_eq!(
            unanswerable_prompt(stderr),
            Some("How would you like to start with Tuist?")
        );
        assert_eq!(unanswerable_prompt("some other failure\n"), None);
    }
}
