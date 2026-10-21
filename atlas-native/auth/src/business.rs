use crate::transport::{Body, Network, Transport};
use crate::{Result, Session, error, invalid, now, validate_registration};
use reqwest::Method;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::collections::BTreeMap;

#[derive(Clone, Copy, Deserialize)]
#[serde(rename_all = "snake_case")]
pub(crate) enum Resource {
    Tasks,
    Accounts,
    Invoices,
    Profile,
}

impl Resource {
    fn path(self) -> &'static str {
        match self {
            Self::Tasks => "api/native/tasks",
            Self::Accounts => "api/native/accounts",
            Self::Invoices => "api/native/invoices",
            Self::Profile => "api/native/profile",
        }
    }

    fn editable(self) -> &'static [&'static str] {
        match self {
            Self::Tasks => &[
                "title",
                "description",
                "assignee_id",
                "account_id",
                "due_on",
                "remind_at",
            ],
            Self::Accounts => &[
                "name",
                "description",
                "primary_domain",
                "segment",
                "status",
                "deal_stage",
                "currency",
                "current_value",
                "next_renewal_date",
                "legal_name",
                "url",
                "hosting",
                "plan_tier",
            ],
            Self::Invoices => &[
                "vendor_name",
                "invoice_number",
                "invoice_date",
                "due_date",
                "total_amount_value",
                "total_amount_currency",
                "status",
            ],
            Self::Profile => &[],
        }
    }

    fn visible(self, field: &str) -> bool {
        self.editable().contains(&field)
            || matches!(self, Self::Tasks)
                && ["status", "assignee_name", "account_name", "reminder_group"].contains(&field)
    }

    fn valid_filter(self, key: &str, value: &str) -> bool {
        let values: &[&str] = match (self, key) {
            (Self::Tasks, "status") => &["open", "completed"],
            (Self::Tasks, "assignee_id") => {
                return value.is_empty() || crate::time_off::validate_id(value).is_ok();
            }
            (Self::Tasks, "reminder") => &["overdue", "upcoming", "none"],
            (Self::Tasks, "group_by") => &["reminder"],
            (Self::Accounts, "segment") => &["customer", "lead", "prospect"],
            (Self::Accounts, "status") => &["active", "churned", "paused", "trial"],
            (Self::Accounts, "deal_stage") => &[
                "discovery",
                "poc",
                "legal_review",
                "security_review",
                "negotiation",
                "closed_won",
                "closed_lost",
            ],
            (Self::Invoices, "status") => &["extracted", "needs_review", "failed"],
            _ => return false,
        };
        value.is_empty() || values.contains(&value)
    }
}

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Action {
    List {
        #[serde(default = "first_page")]
        page: u32,
        #[serde(default)]
        query: String,
        #[serde(default)]
        filters: BTreeMap<String, String>,
    },
    Show {
        id: String,
    },
    Create {
        fields: BTreeMap<String, Option<String>>,
    },
    Update {
        id: String,
        fields: BTreeMap<String, Option<String>>,
    },
    Delete {
        id: String,
    },
    Complete {
        id: String,
    },
}

fn first_page() -> u32 {
    1
}

#[derive(Deserialize, Serialize)]
struct Record {
    id: String,
    fields: BTreeMap<String, String>,
    can_edit: bool,
    can_delete: bool,
}

#[derive(Deserialize, Serialize)]
struct Choice {
    id: String,
    name: String,
}

#[derive(Default, Deserialize, Serialize)]
#[serde(default)]
struct Options {
    users: Vec<Choice>,
    accounts: Vec<Choice>,
    segments: Vec<String>,
    statuses: Vec<String>,
    deal_stages: Vec<String>,
}

#[derive(Deserialize, Serialize)]
struct Month {
    month: String,
    currency: String,
    amount: String,
}

#[derive(Deserialize, Serialize)]
struct Page {
    items: Vec<Record>,
    page: u32,
    total_pages: u32,
    total_count: u32,
    can_write: bool,
    #[serde(default)]
    options: Options,
    #[serde(default)]
    summary: Vec<Month>,
}

#[derive(Deserialize, Serialize)]
struct Mutation {
    item: Record,
}

#[derive(Deserialize, Serialize)]
struct Deleted {
    deleted: bool,
}

#[derive(Deserialize, Serialize)]
struct ProfileUser {
    name: String,
    email: String,
}

#[derive(Deserialize, Serialize)]
struct Profile {
    server_version: String,
    user: ProfileUser,
}

impl Record {
    fn filter(&mut self, resource: Resource) {
        self.fields.retain(|key, _| resource.visible(key));
    }
}

pub(crate) fn execute(session: Session, resource: Resource, action: Action) -> Result<Value> {
    execute_using(&Network, session, resource, action)
}

fn execute_using(
    network: &impl Transport,
    session: Session,
    resource: Resource,
    action: Action,
) -> Result<Value> {
    let server = validate_registration(&session.registration)?;
    if session.expires_at <= now() || session.access_token.is_empty() {
        return Err(error("sign_in_required", "Sign in to Atlas again."));
    }
    let mut url = server.join(resource.path()).map_err(|_| invalid())?;
    if let Action::List {
        page,
        query,
        filters,
    } = &action
        && (*page == 0
            || query.len() > 500
            || filters
                .iter()
                .any(|(key, value)| !resource.valid_filter(key, value)))
    {
        return Err(invalid());
    }
    if matches!(resource, Resource::Profile) {
        if !matches!(action, Action::List { .. }) {
            return Err(invalid());
        }
        let response: Profile = network.request(
            &url,
            Body::Api {
                method: Method::GET,
                token: &session.access_token,
                payload: None,
                failure: response_failure,
            },
        )?;
        return serde_json::to_value(response).map_err(|_| invalid());
    }
    let (method, payload) = match &action {
        Action::List {
            page,
            query,
            filters,
        } => {
            url.query_pairs_mut()
                .append_pair("page", &page.to_string())
                .append_pair("query", query);
            for (key, value) in filters {
                url.query_pairs_mut().append_pair(key, value);
            }
            (Method::GET, None)
        }
        Action::Create { fields } => (Method::POST, Some(payload(resource, fields)?)),
        Action::Show { id }
        | Action::Delete { id }
        | Action::Update { id, .. }
        | Action::Complete { id } => {
            crate::time_off::validate_id(id)?;
            url.path_segments_mut().map_err(|_| invalid())?.push(id);
            match &action {
                Action::Update { fields, .. } => (Method::PATCH, Some(payload(resource, fields)?)),
                Action::Complete { .. } => {
                    if !matches!(resource, Resource::Tasks) {
                        return Err(invalid());
                    }
                    url.path_segments_mut()
                        .map_err(|_| invalid())?
                        .push("complete");
                    (Method::POST, Some(json!({})))
                }
                Action::Delete { .. } => (Method::DELETE, None),
                _ => (Method::GET, None),
            }
        }
    };
    let body = Body::Api {
        method,
        token: &session.access_token,
        payload,
        failure: response_failure,
    };
    match action {
        Action::List { .. } => {
            let mut page: Page = network.request(&url, body)?;
            for item in &mut page.items {
                item.filter(resource);
            }
            serde_json::to_value(page)
        }
        Action::Delete { .. } => serde_json::to_value(network.request::<Deleted>(&url, body)?),
        _ => {
            let mut response: Mutation = network.request(&url, body)?;
            response.item.filter(resource);
            serde_json::to_value(response)
        }
    }
    .map_err(|_| invalid())
}

fn payload(resource: Resource, fields: &BTreeMap<String, Option<String>>) -> Result<Value> {
    for (key, value) in fields {
        if !resource.editable().contains(&key.as_str())
            || value.as_ref().is_some_and(|value| value.len() > 4000)
        {
            return Err(invalid());
        }
        if let Some(value) = value.as_deref().filter(|value| !value.is_empty()) {
            if key.ends_with("_id") {
                crate::time_off::validate_id(value)?;
            }
            if ["due_on", "next_renewal_date", "invoice_date", "due_date"].contains(&key.as_str())
                && !crate::time_off::valid_date(value)
            {
                return Err(invalid());
            }
        }
    }
    serde_json::to_value(fields).map_err(|_| invalid())
}

fn response_failure(status: u16, _bytes: &[u8]) -> crate::AuthError {
    let (kind, message) = match status {
        401 => ("sign_in_required", "Sign in to Atlas again."),
        403 => ("forbidden", "Your Atlas role does not allow this action."),
        404 => (
            "unavailable",
            "This item is no longer available. Refresh the list.",
        ),
        409 => (
            "conflict",
            "This item cannot be changed because it has related records or has already changed.",
        ),
        422 => (
            "validation",
            "Check the required fields, dates, and amounts, then try again.",
        ),
        429 => (
            "rate_limited",
            "Too many requests. Wait a moment and try again.",
        ),
        _ => (
            "server",
            "Atlas could not complete the request. Try again later.",
        ),
    };
    error(kind, message)
}

#[cfg(test)]
#[path = "business_tests.rs"]
mod tests;
