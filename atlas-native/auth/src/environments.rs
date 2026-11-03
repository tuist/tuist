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
    Repositories {
        session: Session,
        installation_id: Option<String>,
    },
    UpdateRepositories {
        session: Session,
        installation_id: Option<String>,
        default_repository: Option<String>,
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
        repository: Option<String>,
    },
    StartProvider {
        session: Session,
        thread_id: String,
        provider: String,
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
    #[serde(skip_serializing_if = "Option::is_none")]
    coding: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    repository: Option<String>,
}

#[derive(Deserialize, Serialize)]
struct Environment {
    id: String,
    #[serde(flatten)]
    configuration: Configuration,
    online: bool,
    #[serde(default)]
    provider: Option<String>,
    #[serde(default)]
    provider_state: Option<String>,
}

#[derive(Deserialize, Serialize)]
struct Provider {
    id: String,
    name: String,
}

#[derive(Deserialize, Serialize)]
struct Overview {
    owner_id: String,
    environments: Vec<Environment>,
    #[serde(default)]
    providers: Vec<Provider>,
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

#[derive(Deserialize, Serialize, PartialEq, Eq)]
enum Tool {
    #[serde(rename = "environment_read_file")]
    ReadFile,
    #[serde(rename = "environment_list_directory")]
    ListDirectory,
    #[serde(rename = "environment_terminal")]
    Terminal,
    #[serde(rename = "read")]
    Read,
    #[serde(rename = "bash")]
    Bash,
    #[serde(rename = "edit")]
    Edit,
    #[serde(rename = "write")]
    Write,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Arguments {
    project_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    command: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    thread_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    title: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    offset: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    limit: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    timeout: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    content: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    edits: Option<Vec<Edit>>,
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Edit {
    old_text: String,
    new_text: String,
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
    repository: Option<String>,
}

#[derive(Deserialize, Serialize)]
struct RepositorySettings {
    installation_id: Option<String>,
    default_repository: Option<String>,
}

#[derive(Deserialize, Serialize)]
struct Installation {
    id: String,
    name: String,
}

#[derive(Deserialize, Serialize)]
struct Repository {
    full_name: String,
}

#[derive(Deserialize, Serialize)]
struct RepositoryCatalog {
    settings: RepositorySettings,
    installations: Vec<Installation>,
    repositories: Vec<Repository>,
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
        Action::Repositories {
            session,
            installation_id,
        } => {
            let path = match installation_id {
                Some(id) => {
                    validate_installation(&id)?;
                    format!("api/me/coding-repositories?installation_id={id}")
                }
                None => "api/me/coding-repositories".into(),
            };
            (session, Method::GET, path, None, "repositories")
        }
        Action::UpdateRepositories {
            session,
            installation_id,
            default_repository,
        } => {
            let settings = RepositorySettings {
                installation_id,
                default_repository,
            };
            validate_repository_settings(&settings)?;
            (
                session,
                Method::PUT,
                "api/me/coding-repositories/settings".into(),
                Some(json!(settings)),
                "repository_settings",
            )
        }
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
        Action::StartProvider {
            session,
            thread_id,
            provider,
        } => {
            validate_id(&thread_id)?;
            validate_provider(&provider)?;
            (
                session,
                Method::PATCH,
                format!("api/native/orbit/threads/{thread_id}/environment"),
                Some(json!({"provider":provider})),
                "selection",
            )
        }
        Action::Select {
            session,
            thread_id,
            environment_id,
            project_id,
            repository,
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
            if repository
                .as_deref()
                .is_some_and(|name| !valid_repository(name))
            {
                return Err(invalid());
            }
            let mut payload = json!({"environment_id":environment_id,"project_id":project_id});
            if let Some(repository) = repository {
                payload["repository"] = json!(repository);
            }
            (
                session,
                Method::PATCH,
                format!("api/native/orbit/threads/{thread_id}/environment"),
                Some(payload),
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
            failure: if matches!(shape, "repositories" | "repository_settings") {
                repository_failure
            } else {
                response_failure
            },
        },
    )?;
    sanitize(value, shape)
}

fn sanitize(value: Value, shape: &str) -> Result<Value> {
    match shape {
        "repositories" => {
            let result: RepositoryCatalog = serde_json::from_value(value).map_err(|_| invalid())?;
            validate_repository_settings(&result.settings)?;
            if result.installations.len() > 5_000 || result.repositories.len() > 5_000 {
                return Err(invalid());
            }
            for installation in &result.installations {
                validate_installation(&installation.id)?;
                if !valid_name(&installation.name) {
                    return Err(invalid());
                }
            }
            if result
                .repositories
                .iter()
                .any(|repo| !valid_repository(&repo.full_name))
            {
                return Err(invalid());
            }
            serde_json::to_value(result).map_err(|_| invalid())
        }
        "repository_settings" => {
            let result: RepositorySettings =
                serde_json::from_value(value).map_err(|_| invalid())?;
            validate_repository_settings(&result)?;
            serde_json::to_value(result).map_err(|_| invalid())
        }
        "list" => {
            let result: Overview = serde_json::from_value(value).map_err(|_| invalid())?;
            validate_id(&result.owner_id)?;
            if result.environments.len() > 32 || result.providers.len() > 20 {
                return Err(invalid());
            }
            for provider in &result.providers {
                validate_provider(&provider.id)?;
                if !valid_name(&provider.name) {
                    return Err(invalid());
                }
            }
            for environment in &result.environments {
                validate_id(&environment.id)?;
                validate_configuration(&environment.configuration)?;
                if let Some(provider) = &environment.provider {
                    validate_provider(provider)?;
                }
                if environment.provider_state.as_deref().is_some_and(|state| {
                    !["starting", "ready", "stopping", "paused", "error"].contains(&state)
                }) {
                    return Err(invalid());
                }
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
                    || ![600, 1800].contains(&job.execution_timeout_seconds)
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
            if result
                .thread
                .repository
                .as_deref()
                .is_some_and(|name| !valid_repository(name))
            {
                return Err(invalid());
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
    let args = &command.arguments;
    let coding = matches!(
        command.tool,
        Tool::Read | Tool::Bash | Tool::Edit | Tool::Write
    );
    if coding {
        validate_id(args.thread_id.as_deref().ok_or_else(invalid)?)?;
        if args
            .title
            .as_ref()
            .is_none_or(|s| !text(s, 1, 800) || s.chars().count() > 200)
        {
            return Err(invalid());
        }
    }
    let allowed = match command.tool {
        Tool::Bash => vec!["command", "timeout"],
        Tool::Terminal => vec!["command"],
        Tool::Read => vec!["path", "offset", "limit"],
        Tool::Edit => vec!["path", "edits"],
        Tool::Write => vec!["path", "content"],
        _ => vec!["path"],
    };
    let serialized = serde_json::to_value(args).map_err(|_| invalid())?;
    if serialized
        .as_object()
        .ok_or_else(invalid)?
        .keys()
        .any(|key| {
            key != "project_id"
                && !allowed.contains(&key.as_str())
                && !(coding && ["thread_id", "title"].contains(&key.as_str()))
        })
    {
        return Err(invalid());
    }
    match command.tool {
        Tool::Terminal | Tool::Bash => {
            if command.execution_timeout_seconds != 1800
                || args.command.as_ref().is_none_or(|s| !valid_command_text(s))
                || args.timeout.is_some_and(|v| !(1..=1800).contains(&v))
            {
                return Err(invalid());
            }
        }
        _ => {
            if args.path.as_ref().is_none_or(|s| !text(s, 1, 4096))
                || (coding && command.execution_timeout_seconds != 60)
                || args.offset.is_some_and(|v| !(1..=1_000_000).contains(&v))
                || args.limit.is_some_and(|v| !(1..=2000).contains(&v))
            {
                return Err(invalid());
            }
        }
    }
    if command.tool == Tool::Write && args.content.as_ref().is_none_or(|s| !text(s, 0, 65536)) {
        return Err(invalid());
    }
    if command.tool == Tool::Edit {
        let edits = args.edits.as_ref().ok_or_else(invalid)?;
        if !(1..=16).contains(&edits.len())
            || serde_json::to_vec(edits).map_err(|_| invalid())?.len() > 131_072
            || edits
                .iter()
                .any(|edit| !text(&edit.old_text, 1, 65536) || !text(&edit.new_text, 0, 65536))
        {
            return Err(invalid());
        }
    }
    Ok(())
}

fn text(value: &str, minimum: usize, maximum: usize) -> bool {
    (minimum..=maximum).contains(&value.len()) && !value.contains('\0')
}

fn valid_command_text(value: &str) -> bool {
    !value.trim().is_empty() && value.len() <= 8000 && !value.contains('\0')
}

fn validate_provider(value: &str) -> Result<()> {
    if value.is_empty()
        || value.len() > 100
        || !value
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'-')
    {
        return Err(invalid());
    }
    Ok(())
}

fn validate_configuration(value: &Configuration) -> Result<()> {
    if !valid_name(&value.name) || value.projects.len() > 100 {
        return Err(invalid());
    }
    for (index, project) in value.projects.iter().enumerate() {
        validate_id(&project.id)?;
        if !valid_name(&project.name)
            || value.projects[..index].iter().any(|p| p.id == project.id)
            || project
                .repository
                .as_ref()
                .is_some_and(|name| project.coding != Some(true) || !valid_repository(name))
        {
            return Err(invalid());
        }
    }
    Ok(())
}

fn valid_repository(value: &str) -> bool {
    let Some((owner, repository)) = value.split_once('/') else {
        return false;
    };
    (1..=39).contains(&owner.len())
        && owner.as_bytes()[0].is_ascii_alphanumeric()
        && owner
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'-')
        && (1..=100).contains(&repository.len())
        && repository
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || b"_.-".contains(&c))
}

fn validate_installation(value: &str) -> Result<()> {
    if !(1..=20).contains(&value.len())
        || value.starts_with('0')
        || !value.bytes().all(|c| c.is_ascii_digit())
    {
        return Err(invalid());
    }
    Ok(())
}

fn validate_repository_settings(value: &RepositorySettings) -> Result<()> {
    if let Some(id) = &value.installation_id {
        validate_installation(id)?;
    }
    if value
        .default_repository
        .as_deref()
        .is_some_and(|name| value.installation_id.is_none() || !valid_repository(name))
    {
        return Err(invalid());
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

fn repository_failure(status: u16, bytes: &[u8]) -> crate::AuthError {
    let reason = serde_json::from_slice::<Value>(bytes).ok();
    match (
        status,
        reason.as_ref().and_then(|value| value["error"].as_str()),
    ) {
        (409, Some("github_connection_required")) => error(
            "github_connection_required",
            "Connect GitHub in Profile → Connections, then try again.",
        ),
        (409, Some("installation_unavailable" | "repository_unavailable")) => error(
            "repository_unavailable",
            "This GitHub selection is no longer available. Refresh and choose again.",
        ),
        (404 | 501, _) => error(
            "unavailable",
            "Update the Atlas server to use repository settings.",
        ),
        (401, _) => error("sign_in_required", "Sign in to Atlas again."),
        _ => error(
            "repositories_unavailable",
            "Could not load or save GitHub repositories. Your selection is kept; try again.",
        ),
    }
}

#[cfg(test)]
#[path = "environments_tests.rs"]
mod tests;
