use crate::transport::{Body, Network, Transport};
use crate::{Result, Session, error, invalid, now, validate_registration};
use reqwest::Method;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Action {
    List {
        session: Session,
    },
    Register {
        session: Session,
        id: String,
        #[serde(flatten)]
        configuration: Configuration,
    },
    Disable {
        session: Session,
        id: String,
    },
    Commands {
        session: Session,
        id: String,
    },
    Claim {
        session: Session,
        id: String,
        command_id: String,
        digest: String,
    },
    Progress {
        session: Session,
        id: String,
        command_id: String,
        claim_token: String,
        sequence: u64,
        output: String,
    },
    Complete {
        session: Session,
        id: String,
        command_id: String,
        claim_token: String,
        success: bool,
        output: String,
    },
    ThreadCommands {
        session: Session,
        thread_id: String,
    },
    CancelCommand {
        session: Session,
        thread_id: String,
        command_id: String,
        digest: String,
    },
    Selection {
        session: Session,
        thread_id: String,
    },
    Select {
        session: Session,
        thread_id: String,
        environment_id: Option<String>,
        project_id: Option<String>,
    },
    Open {
        session: Session,
        id: String,
    },
    Next {
        connection: String,
        after: u64,
    },
    Close {
        connection: String,
    },
}

#[derive(Deserialize, Serialize)]
pub(crate) struct Configuration {
    name: String,
    enabled: bool,
    terminal: bool,
    display: bool,
    projects: Vec<Project>,
}

#[derive(Deserialize, Serialize)]
struct Project {
    id: String,
    name: String,
}

#[derive(Deserialize, Serialize)]
struct Environment {
    id: String,
    #[serde(flatten)]
    configuration: Configuration,
    online: bool,
}

#[derive(Deserialize, Serialize)]
struct Overview {
    owner_id: String,
    environments: Vec<Environment>,
}

#[derive(Deserialize, Serialize)]
pub(super) struct Command {
    id: String,
    tool: Tool,
    arguments: Arguments,
    #[serde(default)]
    execution_timeout_seconds: u32,
    digest: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    claim_token: Option<String>,
}

#[derive(Deserialize, Serialize)]
enum Tool {
    #[serde(rename = "environment_read_file")]
    ReadFile,
    #[serde(rename = "environment_list_directory")]
    ListDirectory,
    #[serde(rename = "environment_terminal")]
    Terminal,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Arguments {
    project_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    command: Option<String>,
}

#[derive(Deserialize, Serialize)]
struct Commands {
    commands: Vec<Command>,
}

#[derive(Deserialize, Serialize)]
struct Claimed {
    command: Command,
}

#[derive(Deserialize, Serialize)]
struct Activity {
    commands: Vec<Job>,
}

#[derive(Deserialize, Serialize)]
struct Job {
    id: String,
    message_id: String,
    environment_id: String,
    environment_name: String,
    project_id: String,
    project_name: String,
    digest: String,
    command: String,
    status: JobStatus,
    output: String,
    success: Option<bool>,
    cancel_requested: bool,
    progress_sequence: u64,
    execution_timeout_seconds: u32,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
enum JobStatus {
    Queued,
    Claimed,
    Settled,
    Cancelled,
    Expired,
    Unknown,
}

#[derive(Deserialize, Serialize)]
struct Selection {
    thread: Selected,
}

#[derive(Deserialize, Serialize)]
struct Selected {
    id: String,
    environment_id: Option<String>,
    environment_name: Option<String>,
    project_id: Option<String>,
}

pub(crate) fn execute(action: Action) -> Result<Value> {
    execute_using(&Network, action)
}

pub(super) fn execute_using(network: &impl Transport, action: Action) -> Result<Value> {
    let (session, method, path, payload, shape) = match action {
        Action::Open { session, id } => {
            validate_id(&id)?;
            return crate::orbit_live::execute(crate::orbit_live::Action::OpenEnvironment {
                session,
                id,
            });
        }
        Action::Next { connection, after } => {
            return crate::orbit_live::execute(crate::orbit_live::Action::Next {
                connection,
                after,
            });
        }
        Action::Close { connection } => {
            return crate::orbit_live::execute(crate::orbit_live::Action::Close { connection });
        }
        Action::List { session } => (
            session,
            Method::GET,
            "api/me/environments".into(),
            None,
            "list",
        ),
        Action::Register {
            session,
            id,
            configuration,
        } => {
            validate_id(&id)?;
            validate_configuration(&configuration)?;
            (
                session,
                Method::PUT,
                format!("api/me/environments/{id}"),
                Some(json!(configuration)),
                "environment",
            )
        }
        Action::Disable { session, id } => {
            validate_id(&id)?;
            (
                session,
                Method::DELETE,
                format!("api/me/environments/{id}"),
                None,
                "disabled",
            )
        }
        Action::Commands { session, id } => {
            validate_id(&id)?;
            (
                session,
                Method::GET,
                format!("api/me/environments/{id}/commands"),
                None,
                "commands",
            )
        }
        Action::Claim {
            session,
            id,
            command_id,
            digest,
        } => {
            validate_id(&id)?;
            validate_id(&command_id)?;
            validate_digest(&digest)?;
            (
                session,
                Method::POST,
                format!("api/me/environments/{id}/commands/{command_id}/claim"),
                Some(json!({"digest":digest})),
                "claim",
            )
        }
        Action::Progress {
            session,
            id,
            command_id,
            claim_token,
            sequence,
            output,
        } => {
            validate_id(&id)?;
            validate_id(&command_id)?;
            validate_id(&claim_token)?;
            if sequence == 0 || sequence > i64::MAX as u64 || output.len() > 48 * 1024 {
                return Err(invalid());
            }
            (
                session,
                Method::POST,
                format!("api/me/environments/{id}/commands/{command_id}/progress"),
                Some(json!({"claim_token":claim_token,"sequence":sequence,"output":output})),
                "progress",
            )
        }
        Action::Complete {
            session,
            id,
            command_id,
            claim_token,
            success,
            output,
        } => {
            validate_id(&id)?;
            validate_id(&command_id)?;
            validate_id(&claim_token)?;
            if output.len() > 64 * 1024 {
                return Err(invalid());
            }
            (
                session,
                Method::POST,
                format!("api/me/environments/{id}/commands/{command_id}/result"),
                Some(json!({"claim_token":claim_token,"success":success,"output":output})),
                "completed",
            )
        }
        Action::ThreadCommands { session, thread_id } => {
            validate_id(&thread_id)?;
            (
                session,
                Method::GET,
                format!("api/native/orbit/threads/{thread_id}/environment-commands"),
                None,
                "activity",
            )
        }
        Action::CancelCommand {
            session,
            thread_id,
            command_id,
            digest,
        } => {
            validate_id(&thread_id)?;
            validate_id(&command_id)?;
            validate_digest(&digest)?;
            (
                session,
                Method::POST,
                format!(
                    "api/native/orbit/threads/{thread_id}/environment-commands/{command_id}/cancel"
                ),
                Some(json!({"digest":digest})),
                "received",
            )
        }
        Action::Selection { session, thread_id } => {
            validate_id(&thread_id)?;
            (
                session,
                Method::GET,
                format!("api/native/orbit/threads/{thread_id}/messages?page=1"),
                None,
                "selection",
            )
        }
        Action::Select {
            session,
            thread_id,
            environment_id,
            project_id,
        } => {
            validate_id(&thread_id)?;
            if environment_id.is_some() != project_id.is_some() {
                return Err(invalid());
            }
            if let Some(id) = &environment_id {
                validate_id(id)?;
            }
            if let Some(id) = &project_id {
                validate_id(id)?;
            }
            (
                session,
                Method::PATCH,
                format!("api/native/orbit/threads/{thread_id}/environment"),
                Some(json!({"environment_id":environment_id,"project_id":project_id})),
                "selection",
            )
        }
    };
    let server = validate_registration(&session.registration)?;
    if session.expires_at <= now() || session.access_token.is_empty() {
        return Err(error("sign_in_required", "Sign in to Atlas again."));
    }
    let url = server.join(&path).map_err(|_| invalid())?;
    let value: Value = network.request(
        &url,
        Body::Api {
            method,
            token: &session.access_token,
            payload,
            failure: response_failure,
        },
    )?;
    sanitize(value, shape)
}

fn sanitize(value: Value, shape: &str) -> Result<Value> {
    match shape {
        "list" => {
            let result: Overview = serde_json::from_value(value).map_err(|_| invalid())?;
            validate_id(&result.owner_id)?;
            if result.environments.len() > 32 {
                return Err(invalid());
            }
            for environment in &result.environments {
                validate_id(&environment.id)?;
                validate_configuration(&environment.configuration)?;
            }
            serde_json::to_value(result).map_err(|_| invalid())
        }
        "commands" => sanitize_commands(value),
        "claim" => {
            let result: Claimed = serde_json::from_value(value).map_err(|_| invalid())?;
            validate_command(&result.command)?;
            validate_id(result.command.claim_token.as_deref().ok_or_else(invalid)?)?;
            serde_json::to_value(result).map_err(|_| invalid())
        }
        "activity" => {
            let result: Activity = serde_json::from_value(value).map_err(|_| invalid())?;
            if result.commands.len() > 32 {
                return Err(invalid());
            }
            for (index, job) in result.commands.iter().enumerate() {
                for id in [
                    &job.id,
                    &job.message_id,
                    &job.environment_id,
                    &job.project_id,
                ] {
                    validate_id(id)?;
                }
                validate_digest(&job.digest)?;
                if !valid_name(&job.environment_name)
                    || !valid_name(&job.project_name)
                    || !valid_command_text(&job.command)
                    || job.output.len() > 48 * 1024
                    || job.progress_sequence > i64::MAX as u64
                    || job.execution_timeout_seconds != 1800
                    || matches!(job.status, JobStatus::Settled) != job.success.is_some()
                    || result.commands[..index]
                        .iter()
                        .any(|other| other.id == job.id)
                {
                    return Err(invalid());
                }
            }
            serde_json::to_value(result).map_err(|_| invalid())
        }
        "selection" => {
            let result: Selection = serde_json::from_value(value).map_err(|_| invalid())?;
            validate_id(&result.thread.id)?;
            if let Some(id) = &result.thread.environment_id {
                validate_id(id)?;
            }
            if let Some(id) = &result.thread.project_id {
                validate_id(id)?;
            }
            serde_json::to_value(result).map_err(|_| invalid())
        }
        "environment" => {
            let result: Environment =
                serde_json::from_value(value["environment"].clone()).map_err(|_| invalid())?;
            validate_id(&result.id)?;
            validate_configuration(&result.configuration)?;
            Ok(json!({"registered":true}))
        }
        "disabled" if value["disabled"] == true => Ok(json!({"disabled":true})),
        "completed" if value["received"] == true => Ok(json!({"completed":true})),
        "received" if value["received"] == true => Ok(json!({"received":true})),
        "progress" if value["received"] == true && value["cancel_requested"].is_boolean() => {
            Ok(json!({"received":true,"cancel_requested":value["cancel_requested"]}))
        }
        _ => Err(invalid()),
    }
}

pub(super) fn sanitize_commands(value: Value) -> Result<Value> {
    let result: Commands = serde_json::from_value(value).map_err(|_| invalid())?;
    if result.commands.len() > 16 {
        return Err(invalid());
    }
    for command in &result.commands {
        validate_command(command)?;
    }
    serde_json::to_value(result).map_err(|_| invalid())
}

fn validate_command(command: &Command) -> Result<()> {
    validate_id(&command.id)?;
    validate_id(&command.arguments.project_id)?;
    validate_digest(&command.digest)?;
    match command.tool {
        Tool::Terminal => {
            if command.execution_timeout_seconds != 1800
                || command.arguments.path.is_some()
                || command
                    .arguments
                    .command
                    .as_ref()
                    .is_none_or(|s| !valid_command_text(s))
            {
                return Err(invalid());
            }
        }
        _ => {
            if command.arguments.command.is_some()
                || command
                    .arguments
                    .path
                    .as_ref()
                    .is_none_or(|s| s.len() > 4096 || s.contains('\0'))
            {
                return Err(invalid());
            }
        }
    }
    Ok(())
}

fn valid_command_text(value: &str) -> bool {
    !value.trim().is_empty() && value.len() <= 8000 && !value.contains('\0')
}

fn validate_configuration(value: &Configuration) -> Result<()> {
    if !valid_name(&value.name) || value.projects.len() > 100 {
        return Err(invalid());
    }
    for (index, project) in value.projects.iter().enumerate() {
        validate_id(&project.id)?;
        if !valid_name(&project.name) || value.projects[..index].iter().any(|p| p.id == project.id)
        {
            return Err(invalid());
        }
    }
    Ok(())
}

fn valid_name(value: &str) -> bool {
    !value.trim().is_empty() && value.chars().count() <= 120 && !value.chars().any(char::is_control)
}

fn validate_digest(value: &str) -> Result<()> {
    if value.len() != 64
        || !value
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err(invalid());
    }
    Ok(())
}

fn validate_id(value: &str) -> Result<()> {
    crate::time_off::validate_id(value)?;
    if value.bytes().any(|b| b.is_ascii_uppercase()) {
        return Err(invalid());
    }
    Ok(())
}

fn response_failure(status: u16, _bytes: &[u8]) -> crate::AuthError {
    let (kind, message) = match status {
        401 => ("sign_in_required", "Sign in to Atlas again."),
        403 => (
            "forbidden",
            "This environment is not available to this Atlas installation.",
        ),
        404 | 501 => (
            "unavailable",
            "This Atlas server does not support personal environments yet.",
        ),
        409 => (
            "conflict",
            "This action is no longer available. Refresh and try again after the current run finishes.",
        ),
        400 | 422 => (
            "invalid_request",
            "Check the environment name, permissions and selected project.",
        ),
        429 => ("rate_limited", "Too many requests. Try again later."),
        _ => (
            "server",
            "Could not reach this environment. Try again later.",
        ),
    };
    error(kind, message)
}

#[cfg(test)]
#[path = "environments_tests.rs"]
mod tests;
