//! Organization-owned saved prompts, persisted by Luft. A composer invokes
//! one by sending `/name` followed by optional text as an ordinary message.
use serde_json::{Value, json};
use tuist_oauth::endpoint;
use url::Url;

use crate::client::{Result, segment, successful, text};
use crate::threads::Transport;

fn valid_name(name: &str) -> bool {
    name.len() <= 64
        && name.starts_with(|c: char| c.is_ascii_lowercase())
        && name
            .bytes()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'-')
}

/// Picking a prompt only edits the draft. Preserve additional instructions,
/// replacing a leading command when the person changes their selection.
pub fn draft(args: &Value) -> Result<Value> {
    let name = text(args, "name")?;
    if !valid_name(name) {
        return Err("Invalid prompt name");
    }
    let content = args
        .get("content")
        .and_then(Value::as_str)
        .ok_or("Missing required argument")?;
    let remainder = content
        .strip_prefix('/')
        .and_then(|command| {
            let end = command.find(char::is_whitespace).unwrap_or(command.len());
            (end == 0 || valid_name(&command[..end])).then(|| command[end..].trim_start())
        })
        .unwrap_or(content);
    Ok(json!({"content": format!("/{name} {remainder}")}))
}

/// Lists, reads, saves or deletes an organization's prompts. Deleting a
/// standard prompt resets it; deleting a custom prompt removes it.
pub fn call(
    server: &Url,
    operation: &str,
    args: &Value,
    transport: &mut dyn Transport,
) -> Result<Value> {
    let handle = text(args, "account_handle")?;
    if !segment(handle) {
        return Err("Invalid account");
    }
    let mut path = format!("api/accounts/{handle}/prompts");
    if operation != "prompts" {
        let name = text(args, "name")?;
        if !valid_name(name) {
            return Err("Invalid prompt name");
        }
        path.push('/');
        path.push_str(name);
    }
    let (method, body) = match operation {
        "prompts" | "prompt" => ("GET", None),
        "save_prompt" => {
            let title = text(args, "title")?.trim();
            let body = text(args, "body")?.trim();
            if title.is_empty()
                || title.chars().count() > 80
                || body.is_empty()
                || body.len() > 12_000
            {
                return Err("Enter a title up to 80 characters and prompt text up to 12000 bytes.");
            }
            ("PUT", Some(json!({"title": title, "body": body})))
        }
        "delete_prompt" => ("DELETE", None),
        _ => return Err("Unknown operation"),
    };
    match transport.send(method, endpoint(server, &path), body)? {
        (204, _) => Ok(Value::Null),
        (403, _) => Err("Only organization admins can change prompts."),
        (404, _) => Err("Prompt not found in this organization."),
        (422, _) => Err("Enter a valid prompt name, title and body."),
        answer => successful(answer),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn picking_only_changes_the_command_and_preserves_additional_instructions() {
        for (content, expected) in [
            ("", "/ship "),
            ("/", "/ship "),
            ("/re", "/ship "),
            ("Check Linux first", "/ship Check Linux first"),
            ("/review\nCheck Linux first", "/ship Check Linux first"),
            ("/review", "/ship "),
            ("Notes /review", "/ship Notes /review"),
            ("/tmp/file", "/ship /tmp/file"),
        ] {
            assert_eq!(
                draft(&json!({"name":"ship", "content":content})).unwrap()["content"],
                expected
            );
        }
        assert!(draft(&json!({"name":"../ship", "content":"keep"})).is_err());
    }

    struct Recording {
        calls: Vec<(String, Url, Option<Value>)>,
        status: u64,
    }

    impl Transport for Recording {
        fn send(&mut self, method: &str, url: Url, body: Option<Value>) -> Result<(u64, Value)> {
            self.calls.push((method.into(), url, body));
            Ok((self.status, json!({"prompts": [], "can_edit": false})))
        }
    }

    #[test]
    fn requests_stay_on_luft_and_are_scoped_to_the_selected_organization() {
        let server = Url::parse("https://luft.example/base/").unwrap();
        let mut transport = Recording {
            calls: vec![],
            status: 200,
        };
        let args = json!({"account_handle": "team", "name": "ship", "title": " Ship ", "body": " Run checks. "});
        call(&server, "save_prompt", &args, &mut transport).unwrap();
        assert_eq!(
            transport.calls[0],
            (
                "PUT".into(),
                Url::parse("https://luft.example/base/api/accounts/team/prompts/ship").unwrap(),
                Some(json!({"title": "Ship", "body": "Run checks."}))
            )
        );
        let listed = call(&server, "prompts", &args, &mut transport).unwrap();
        assert_eq!(listed["can_edit"], false);
        assert_eq!(transport.calls[1].0, "GET");
        assert_eq!(
            transport.calls[1].1.path(),
            "/base/api/accounts/team/prompts"
        );
        transport.status = 403;
        assert_eq!(
            call(&server, "delete_prompt", &args, &mut transport),
            Err("Only organization admins can change prompts.")
        );
        transport.status = 204;
        assert_eq!(
            call(&server, "delete_prompt", &args, &mut transport),
            Ok(Value::Null)
        );
    }

    #[test]
    fn invalid_names_and_multibyte_size_limits_are_checked_before_networking() {
        let server = Url::parse("https://luft.example").unwrap();
        let mut transport = Recording {
            calls: vec![],
            status: 200,
        };
        for name in ["", "../ship", "Ship", "has space", "9ship"] {
            assert!(
                call(
                    &server,
                    "prompt",
                    &json!({"account_handle":"team", "name":name}),
                    &mut transport
                )
                .is_err()
            );
        }
        let mut args = json!({"account_handle":"team", "name":"check-linux", "title":"Check", "body":"é".repeat(6001)});
        assert!(call(&server, "save_prompt", &args, &mut transport).is_err());
        assert!(transport.calls.is_empty());
        args["body"] = json!("é".repeat(6000));
        assert!(call(&server, "save_prompt", &args, &mut transport).is_ok());
    }
}
