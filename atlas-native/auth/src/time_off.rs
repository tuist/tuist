use crate::transport::{Body, Network, Transport};
use crate::{Result, Session, error, invalid, now, validate_registration};
use reqwest::Method;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Action {
    List {
        requests_page: u32,
        holidays_page: u32,
    },
    Create {
        starts_on: String,
        ends_on: String,
    },
    Update {
        id: String,
        starts_on: String,
        ends_on: String,
    },
    Cancel {
        id: String,
    },
}

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "lowercase")]
enum Status {
    Pending,
    Approved,
    Rejected,
    Cancelled,
}

#[derive(Deserialize, Serialize)]
struct Request {
    id: String,
    starts_on: String,
    ends_on: String,
    status: Status,
    working_days: Option<u32>,
    #[serde(default)]
    missing_years: Vec<u16>,
}

#[derive(Deserialize, Serialize)]
struct Holiday {
    id: String,
    name: String,
    date: String,
}

#[derive(Deserialize, Serialize)]
struct Page<T> {
    items: Vec<T>,
    page: u32,
    total_pages: u32,
    total_count: u32,
}

#[derive(Deserialize, Serialize)]
struct Overview {
    requests: Page<Request>,
    public_holidays: Page<Holiday>,
}

#[derive(Deserialize, Serialize)]
struct Mutation {
    request: Request,
}

pub(crate) fn execute(session: Session, action: Action) -> Result<Value> {
    execute_using(&Network, session, action)
}

pub(super) fn execute_using(
    network: &impl Transport,
    session: Session,
    action: Action,
) -> Result<Value> {
    let server = validate_registration(&session.registration)?;
    if session.expires_at <= now() || session.access_token.is_empty() {
        return Err(error("sign_in_required", "Sign in to Atlas again."));
    }
    let mut url = server.join("api/me/time-off").map_err(|_| invalid())?;
    let (method, payload) = match &action {
        Action::List {
            requests_page,
            holidays_page,
        } => {
            if *requests_page == 0 || *holidays_page == 0 {
                return Err(invalid());
            }
            url.query_pairs_mut()
                .append_pair("requests_page", &requests_page.to_string())
                .append_pair("holidays_page", &holidays_page.to_string());
            (Method::GET, None)
        }
        Action::Create { starts_on, ends_on } => {
            validate_range(starts_on, ends_on)?;
            (
                Method::POST,
                Some(json!({"starts_on": starts_on, "ends_on": ends_on})),
            )
        }
        Action::Update {
            id,
            starts_on,
            ends_on,
        } => {
            validate_id(id)?;
            validate_range(starts_on, ends_on)?;
            url.path_segments_mut().map_err(|_| invalid())?.push(id);
            (
                Method::PATCH,
                Some(json!({"starts_on": starts_on, "ends_on": ends_on})),
            )
        }
        Action::Cancel { id } => {
            validate_id(id)?;
            url.path_segments_mut().map_err(|_| invalid())?.push(id);
            (Method::DELETE, None)
        }
    };
    let body = Body::Api {
        method,
        token: &session.access_token,
        payload,
        failure: response_failure,
    };
    match action {
        Action::List { .. } => serde_json::to_value(network.request::<Overview>(&url, body)?),
        _ => serde_json::to_value(network.request::<Mutation>(&url, body)?),
    }
    .map_err(|_| invalid())
}

pub(super) fn validate_id(id: &str) -> Result<()> {
    if id.split('-').map(str::len).collect::<Vec<_>>() != [8, 4, 4, 4, 12]
        || !id
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() || byte == b'-')
    {
        return Err(invalid());
    }
    Ok(())
}

pub(super) fn valid_date(date: &str) -> bool {
    let bytes = date.as_bytes();
    if bytes.len() != 10
        || bytes[4] != b'-'
        || bytes[7] != b'-'
        || !bytes
            .iter()
            .enumerate()
            .all(|(index, byte)| index == 4 || index == 7 || byte.is_ascii_digit())
    {
        return false;
    }
    let year: u32 = date[..4].parse().unwrap_or(0);
    let month: usize = date[5..7].parse().unwrap_or(0);
    let day: u32 = date[8..].parse().unwrap_or(0);
    let leap = year.is_multiple_of(4) && (!year.is_multiple_of(100) || year.is_multiple_of(400));
    let days = [
        0,
        31,
        if leap { 29 } else { 28 },
        31,
        30,
        31,
        30,
        31,
        31,
        30,
        31,
        30,
        31,
    ];
    (2000..=2100).contains(&year) && (1..=12).contains(&month) && day > 0 && day <= days[month]
}

fn validate_range(first: &str, last: &str) -> Result<()> {
    if !valid_date(first) || !valid_date(last) || first > last {
        return Err(error(
            "invalid_dates",
            "Choose valid first and last days, in that order.",
        ));
    }
    Ok(())
}

fn response_failure(status: u16, _bytes: &[u8]) -> crate::AuthError {
    let (kind, message) = match status {
        401 => ("sign_in_required", "Sign in to Atlas again."),
        404 => (
            "unavailable",
            "This request is no longer available. Refresh your holidays.",
        ),
        422 => (
            "invalid_dates",
            "Choose dates within one year that do not overlap another active request.",
        ),
        429 => (
            "rate_limited",
            "Too many requests. Wait a moment and try again.",
        ),
        _ => (
            "server",
            "Atlas could not update your holidays. Try again later.",
        ),
    };
    error(kind, message)
}

#[cfg(test)]
#[path = "time_off_tests.rs"]
mod tests;
