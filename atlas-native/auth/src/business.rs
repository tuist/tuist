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
            || matches!(self, Self::Accounts)
                && [
                    "contract_value",
                    "contract_currency",
                    "contacts_count",
                    "poc_end_date",
                ]
                .contains(&field)
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
    UpdateProfile {
        description: String,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    details: Option<AccountDetails>,
}

#[derive(Deserialize, Serialize)]
struct RelatedRecord {
    id: String,
    fields: BTreeMap<String, String>,
}

#[derive(Default, Deserialize, Serialize)]
#[serde(default)]
struct AccountDetails {
    fields: BTreeMap<String, String>,
    address: BTreeMap<String, String>,
    billing: BTreeMap<String, String>,
    signatory: BTreeMap<String, String>,
    children: Vec<RelatedRecord>,
    contacts: Vec<RelatedRecord>,
    terms: Vec<RelatedRecord>,
    invoices: Vec<RelatedRecord>,
    documents: Vec<RelatedRecord>,
    events: Vec<RelatedRecord>,
    outcomes: Vec<RelatedRecord>,
    service_levels: Vec<RelatedRecord>,
}

impl AccountDetails {
    fn filter(&mut self) {
        self.fields.retain(|key, _| {
            [
                "overview_summary",
                "overview_summary_generated_at",
                "contract_id",
                "poc_end_date",
                "churned_date",
                "churn_reason",
                "stripe_customer_id",
                "latest_activity_at",
                "parent_account_name",
                "handles",
                "contract_value",
                "contract_currency",
            ]
            .contains(&key.as_str())
        });
        self.address
            .retain(|key, _| ["street", "city", "zip", "country"].contains(&key.as_str()));
        self.billing.retain(|key, _| {
            ["tax_id", "vat_id", "sold_to", "bill_to", "email", "phone"].contains(&key.as_str())
        });
        self.signatory
            .retain(|key, _| ["name", "title"].contains(&key.as_str()));
        for (records, fields) in [
            (&mut self.children, &["name", "primary_domain"][..]),
            (
                &mut self.contacts,
                &[
                    "full_name",
                    "email",
                    "title",
                    "notes",
                    "linkedin_url",
                    "is_primary",
                    "is_decision_maker",
                ][..],
            ),
            (
                &mut self.terms,
                &[
                    "payment",
                    "start_date",
                    "end_date",
                    "price_per_seat",
                    "seats",
                    "discount",
                    "total",
                    "currency",
                    "on_premise",
                    "renewal_notice_weeks",
                    "po_number",
                ][..],
            ),
            (
                &mut self.invoices,
                &[
                    "number",
                    "due_date",
                    "amount_value",
                    "amount_currency",
                    "status",
                ][..],
            ),
            (
                &mut self.documents,
                &["title", "document_date", "summary", "status"][..],
            ),
            (
                &mut self.events,
                &["title", "body", "kind", "occurred_at", "author_name"][..],
            ),
            (
                &mut self.outcomes,
                &[
                    "title",
                    "description",
                    "status",
                    "health",
                    "motion",
                    "success_measure",
                    "baseline",
                    "target",
                    "target_date",
                    "owner_name",
                ][..],
            ),
            (
                &mut self.service_levels,
                &[
                    "name",
                    "category",
                    "target",
                    "measurement_window",
                    "applies_from",
                    "applies_until",
                    "service_credit",
                    "exclusions",
                ][..],
            ),
        ] {
            for record in records {
                record
                    .fields
                    .retain(|key, _| fields.contains(&key.as_str()));
            }
        }
    }
}

#[derive(Deserialize, Serialize)]
struct FinanceMonth {
    month: String,
    income: String,
    expense: String,
}

#[derive(Deserialize, Serialize)]
struct FinanceOverview {
    currency: String,
    as_of: String,
    account_count: u32,
    available_cash: Option<String>,
    monthly_burn: Option<String>,
    runway_months: Option<String>,
    fx_published_on: Option<String>,
    excluded_currencies: Vec<String>,
    months: Vec<FinanceMonth>,
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
    #[serde(default, skip_serializing_if = "Option::is_none")]
    finance_overview: Option<FinanceOverview>,
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
    #[serde(default)]
    description: String,
}

#[derive(Deserialize, Serialize)]
struct Profile {
    server_version: String,
    user: ProfileUser,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    push_notifications: Option<PushCapabilities>,
}

#[derive(Deserialize, Serialize)]
struct PushCapabilities {
    ios: bool,
    android: bool,
}

impl Record {
    fn filter(&mut self, resource: Resource) {
        self.fields.retain(|key, _| resource.visible(key));
        if matches!(resource, Resource::Accounts) {
            if let Some(details) = &mut self.details {
                details.filter();
            }
        } else {
            self.details = None;
        }
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
        let (method, payload) = match &action {
            Action::List {
                page: 1,
                query,
                filters,
            } if query.is_empty() && filters.is_empty() => (Method::GET, None),
            Action::UpdateProfile { description } if valid_description(description) => {
                (Method::PATCH, Some(json!({"description": description})))
            }
            _ => return Err(invalid()),
        };
        let response: Profile = network.request(
            &url,
            Body::Api {
                method,
                token: &session.access_token,
                payload,
                failure: response_failure,
            },
        )?;
        if !valid_description(&response.user.description) {
            return Err(invalid());
        }
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
        Action::UpdateProfile { .. } => return Err(invalid()),
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
            if !matches!(resource, Resource::Invoices) {
                page.finance_overview = None;
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

fn valid_description(description: &str) -> bool {
    description.len() <= 16_000
        && description.chars().count() <= 4000
        && !description.contains('\0')
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
