//! Ephemeral, explicit workspace connections, isolated from production identity.
//! Platform hosts supply HTTP only. Neither the renderer nor snapshots get credentials.
use crate::Host;
use serde_json::{Value, json};
use url::Url;

type Result<T> = std::result::Result<T, &'static str>;
const INVALID: &str = "Invalid workspace response";
const DISCONNECTED: &str = "Workspace disconnected. Reconnect explicitly to continue.";

enum Connection {
    Preview(Url, String),
    Session,
}

#[derive(Default)]
pub struct Workspace {
    connection: Option<Connection>,
    manifest: Value,
    selected: Option<String>,
    items: Value,
    record: Value,
    pending: Option<Value>,
    warning: Option<&'static str>,
}

impl Workspace {
    /// Drop rendered state and authority, retaining only an unresolved submission.
    /// A session must obtain a fresh catalog before this can be replayed.
    pub(crate) fn suspend(&mut self) {
        let pending = self.pending.take();
        *self = Self::default();
        self.pending = pending;
    }

    /// Only the authenticated client calls this, with a catalog returned by the
    /// session's own server. No preview bearer or caller-selected origin exists.
    pub(crate) fn attach(&mut self, catalog: Value, module: &str) -> Result<()> {
        self.suspend();
        validate_manifest(&catalog)?;
        if !catalog["ui_modules"]
            .as_array()
            .unwrap()
            .iter()
            .any(|m| m["id"] == module)
        {
            return Err("Unknown workspace module");
        }
        self.manifest = catalog;
        self.selected = Some(module.into());
        self.connection = Some(Connection::Session);
        Ok(())
    }

    pub fn call(&mut self, request: &Value, host: &mut dyn Host) -> Value {
        let result = self.run(request, host);
        let mut response = json!({"view":self.snapshot(),"data":null});
        match result {
            Ok(data) => response["data"] = data,
            Err(error) => response["error"] = json!(error),
        }
        response
    }

    fn snapshot(&self) -> Value {
        json!({"preview":matches!(self.connection, Some(Connection::Preview(..))),"connected":self.connection.is_some(),
            "title":self.manifest["title"],"modules":self.manifest["ui_modules"],
            "selected":self.selected,"items":self.items,"record":self.record,
            "warning":self.warning,"can_retry":self.pending.is_some()})
    }

    fn run(&mut self, request: &Value, host: &mut dyn Host) -> Result<Value> {
        let args = &request["args"];
        if matches!(
            request["operation"].as_str(),
            Some("workspace_query" | "workspace_open" | "workspace_action" | "workspace_retry")
        ) {
            self.require_connection()?;
            if args["module"].as_str() != self.selected.as_deref() {
                return Err("Workspace module is no longer selected");
            }
        }
        match request["operation"].as_str().unwrap_or("") {
            "workspace_connect" => {
                *self = Self::default();
                let url = origin(args["url"].as_str().ok_or("Invalid workspace origin")?)?;
                let token = args["token"]
                    .as_str()
                    .filter(|s| {
                        !s.is_empty() && s.len() <= 4096 && s.bytes().all(|b| b.is_ascii_graphic())
                    })
                    .ok_or("Invalid workspace token")?;
                self.connection = Some(Connection::Preview(url, token.into()));
                let result = self.http(host, "workspace", None).and_then(|value| {
                    validate_manifest(&value)?;
                    self.selected = value["ui_modules"][0]["id"].as_str().map(str::to_owned);
                    self.manifest = value;
                    Ok(Value::Null)
                });
                if result.is_err() {
                    *self = Self::default();
                }
                result
            }
            "workspace_disconnect" => {
                *self = Self::default();
                Ok(Value::Null)
            }
            "workspace_snapshot" => Ok(Value::Null),
            "workspace_select" => {
                self.require_connection()?;
                let id = args["module"].as_str().ok_or("Unknown workspace module")?;
                if !self.manifest["ui_modules"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|m| m["id"] == id)
                {
                    return Err("Unknown workspace module");
                }
                self.selected = Some(id.into());
                self.items = Value::Null;
                self.record = Value::Null;
                self.pending = None;
                self.warning = None;
                Ok(Value::Null)
            }
            "workspace_open" => {
                let model = args["model"].as_str().ok_or("Invalid workspace model")?;
                if self.module()?["model"] != model {
                    return Err("Workspace reference does not belong to this module");
                }
                let query = self.module()?["capabilities"]["queries"]
                    .as_array()
                    .and_then(|queries| {
                        queries.iter().filter_map(Value::as_str).find(|name| {
                            self.manifest["queries"][*name]["operation"] == "get"
                                && self.manifest["queries"][*name]["model"] == model
                        })
                    })
                    .ok_or("Workspace record entry is not declared")?
                    .to_owned();
                // Never reuse a previous snapshot when opening a typed reference.
                self.record = Value::Null;
                self.query(&json!({"query":query,"input":{"id":args["id"]}}), host)
            }
            "workspace_query" => self.query(args, host),
            "workspace_action" => self.action(args, host),
            "workspace_retry" => {
                self.require_connection()?;
                let pending = self.pending.clone().ok_or("Nothing to retry")?;
                self.execute_action(pending, host)
            }
            _ => Err("Unknown workspace operation"),
        }
    }

    fn require_connection(&self) -> Result<()> {
        self.connection.as_ref().map(|_| ()).ok_or(DISCONNECTED)
    }

    fn module(&self) -> Result<&Value> {
        self.require_connection()?;
        self.manifest["ui_modules"]
            .as_array()
            .and_then(|modules| {
                modules
                    .iter()
                    .find(|m| m["id"].as_str() == self.selected.as_deref())
            })
            .ok_or("Unknown workspace module")
    }

    fn allowed(&self, kind: &str, name: &str) -> Result<()> {
        if self.module()?["capabilities"][kind]
            .as_array()
            .is_some_and(|names| names.iter().any(|n| n == name))
        {
            Ok(())
        } else {
            Err("Workspace capability denied")
        }
    }

    fn query(&mut self, args: &Value, host: &mut dyn Host) -> Result<Value> {
        self.warning = None;
        let name = args["query"].as_str().ok_or("Invalid workspace query")?;
        self.allowed("queries", name)?;
        let definition = &self.manifest["queries"][name];
        let model = definition["model"].as_str().ok_or(INVALID)?.to_owned();
        if definition["operation"] == "get" {
            let input = args["input"]
                .as_object()
                .ok_or("Invalid workspace query input")?;
            let id = input
                .get("id")
                .and_then(Value::as_str)
                .filter(|id| uuid(id))
                .ok_or("Invalid workspace record ID")?
                .to_ascii_lowercase();
            if input.len() != 1 {
                return Err("Invalid workspace query input");
            }
            let result = self.http(host, "query", Some(json!({"query":name,"input":{"id":id}})))?;
            validate_record(&result["record"], &self.manifest["models"][&model])?;
            if result["record"]["id"] != id {
                return Err(INVALID);
            }
            if self.module()?["model"] == model {
                self.record = result["record"].clone();
            }
            return Ok(result);
        }
        if args["input"] != json!({}) {
            return Err("Invalid workspace query input");
        }
        let result = self.http(host, "query", Some(json!({"query":name,"input":{}})))?;
        let rows = result["items"]
            .as_array()
            .filter(|rows| rows.len() <= 100)
            .ok_or(INVALID)?;
        let mut previous = "";
        for row in rows {
            validate_record(row, &self.manifest["models"][&model])?;
            let id = row["id"].as_str().ok_or(INVALID)?;
            if id <= previous {
                return Err(INVALID);
            }
            previous = id;
        }
        self.items = result["items"].clone();
        if let Some(record) = rows.iter().find(|row| row["id"] == self.record["id"]) {
            self.record = record.clone();
        }
        Ok(result)
    }

    fn action(&mut self, args: &Value, host: &mut dyn Host) -> Result<Value> {
        if self.pending.is_some() {
            return Err(
                "Resolve the previous submission with Retry submission before writing again.",
            );
        }
        self.warning = None;
        let name = args["action"].as_str().ok_or("Invalid workspace action")?;
        self.allowed("actions", name)?;
        let id = args["request_id"]
            .as_str()
            .filter(|id| uuid(id))
            .ok_or("A fresh request UUID is required")?;
        let definition = &self.manifest["actions"][name];
        let model = &self.manifest["models"][definition["model"].as_str().ok_or(INVALID)?];
        let input = &args["input"];
        let update = definition["operation"] == "update";
        if update
            && (!input["id"].as_str().is_some_and(uuid)
                || input["expected_revision"].as_u64().is_none_or(|n| n == 0))
        {
            return Err("Invalid update identity or revision");
        }
        validate_values(&input["values"], model, !update, true)
            .map_err(|_| "Check the record fields and values.")?;
        let body = json!({"action":name,"request_id":id,"input":input});
        self.pending = Some(body.clone());
        self.execute_action(body, host)
    }

    fn execute_action(&mut self, body: Value, host: &mut dyn Host) -> Result<Value> {
        self.allowed("actions", body["action"].as_str().ok_or(INVALID)?)?;
        let result = self.http(host, "action", Some(body.clone()))?;
        let model = self.manifest["actions"][body["action"].as_str().ok_or(INVALID)?]["model"]
            .as_str()
            .ok_or(INVALID)?;
        validate_record(&result, &self.manifest["models"][model])?;
        if body["input"].get("id").is_some()
            && (result["id"] != body["input"]["id"]
                || result["revision"].as_u64()
                    != body["input"]["expected_revision"]
                        .as_u64()
                        .and_then(|r| r.checked_add(1)))
        {
            return Err(INVALID);
        }
        self.pending = None;
        if self.record["id"] == result["id"] {
            self.record = result.clone();
        }
        if let Some(rows) = self.items.as_array_mut()
            && let Some(row) = rows.iter_mut().find(|row| row["id"] == result["id"])
        {
            *row = result.clone();
        }
        // Refresh the module's own authoritative list, not a cross-model getter.
        let module = self.module()?;
        let query = module["capabilities"]["queries"]
            .as_array()
            .and_then(|queries| {
                queries.iter().filter_map(Value::as_str).find(|name| {
                    self.manifest["queries"][*name]["operation"] == "list"
                        && self.manifest["queries"][*name]["model"] == module["model"]
                })
            })
            .map(str::to_owned);
        if let Some(query) = query
            && self
                .query(&json!({"query":query,"input":{}}), host)
                .is_err()
        {
            // The write is known to have committed. A failed read must not invite
            // a new submission (and potentially duplicate a successful create).
            self.warning = Some("Saved, but refresh failed. Refresh before making another change.");
        }
        Ok(result)
    }

    fn http(&mut self, host: &mut dyn Host, path: &str, body: Option<Value>) -> Result<Value> {
        let (action, token) = match self.connection.as_ref().ok_or(DISCONNECTED)? {
            Connection::Preview(origin, token) => (
                json!({"type":"http","method":if body.is_some() {"POST"} else {"GET"},
            "url":origin.join(path).map_err(|_| INVALID)?.as_str(),
            "headers":{"Accept":"application/json","Content-Type":"application/json","Authorization":format!("Bearer {token}")},
            "body":body.map(|b| b.to_string())}),
                Some(token.clone()),
            ),
            Connection::Session => (
                json!({"type":"record_request","path":path,"body":body}),
                None,
            ),
        };
        let mut response = host.perform(action.clone());
        // One safe transport retry, byte-for-byte identical request including UUID.
        // Never retry TLS/policy/oversize errors, or an HTTP refusal automatically.
        if response.as_ref().is_ok_and(|r| r["error"] == "offline") {
            response = host.perform(action);
        }
        let response = match response {
            Ok(response) if response["status"].as_u64().is_some() => response,
            _ => {
                // Session recovery retains only the submission identity, never
                // source/data/authority. Preview disconnect remains disposable.
                if matches!(self.connection, Some(Connection::Session)) {
                    self.suspend();
                } else {
                    *self = Self::default();
                }
                return Err(DISCONNECTED);
            }
        };
        if response["status"] == 401 || response["status"] == 403 {
            *self = Self::default();
            return Err(DISCONNECTED);
        }
        let text = response["body"]
            .as_str()
            .filter(|s| s.len() <= 1024 * 1024 && token.as_ref().is_none_or(|t| !s.contains(t)))
            .ok_or(INVALID)?;
        let value: Value = serde_json::from_str(text).map_err(|_| INVALID)?;
        // Check decoded strings too: JSON escapes must not bypass secret filtering.
        if token
            .as_ref()
            .is_some_and(|token| contains_secret(&value, token))
        {
            return Err(INVALID);
        }
        match response["status"].as_u64() {
            Some(200) => Ok(value),
            Some(400 | 404 | 409 | 422) => {
                if path == "action" {
                    self.pending = None;
                }
                match value["error"]["code"].as_str() {
                    Some("VALIDATION_FAILED") => Err("Check the record fields and values."),
                    Some("REVISION_CONFLICT") => {
                        Err("This record changed. Reload before editing again.")
                    }
                    Some("NOT_FOUND") => Err("Record not found. Reload the list."),
                    _ => Err("Workspace request rejected"),
                }
            }
            _ => Err("Workspace unavailable. Retry the request."),
        }
    }
}

fn contains_secret(value: &Value, secret: &str) -> bool {
    match value {
        Value::String(text) => text.contains(secret),
        Value::Array(values) => values.iter().any(|v| contains_secret(v, secret)),
        Value::Object(values) => values
            .iter()
            .any(|(key, v)| key.contains(secret) || contains_secret(v, secret)),
        _ => false,
    }
}

fn origin(text: &str) -> Result<Url> {
    let url = Url::parse(text).map_err(|_| "Invalid workspace origin")?;
    let loopback = matches!(url.host_str(), Some("localhost" | "127.0.0.1" | "[::1]"));
    if !(url.scheme() == "https" || url.scheme() == "http" && loopback)
        || url.host_str().is_none()
        || !url.username().is_empty()
        || url.password().is_some()
        || url.query().is_some()
        || url.fragment().is_some()
        || url.path() != "/"
    {
        return Err("Invalid workspace origin");
    }
    Ok(url)
}

fn uuid(id: &str) -> bool {
    id.len() == 36
        && id.bytes().enumerate().all(|(i, b)| {
            if [8, 13, 18, 23].contains(&i) {
                b == b'-'
            } else {
                b.is_ascii_hexdigit()
            }
        })
}

fn validate_values(values: &Value, model: &Value, required: bool, defaults: bool) -> Result<()> {
    let fields = model["fields"].as_object().ok_or(INVALID)?;
    let values = values
        .as_object()
        .filter(|v| !v.is_empty())
        .ok_or(INVALID)?;
    if values.keys().any(|name| !fields.contains_key(name)) {
        return Err(INVALID);
    }
    for (name, field) in fields {
        let Some(value) = values.get(name) else {
            if required
                && field["required"] == true
                && !(defaults && field.get("default").is_some())
            {
                return Err(INVALID);
            }
            continue;
        };
        if value.is_null() && field["required"] != true && field["nullable"] != false {
            continue;
        }
        let text = value.as_str().filter(|s| s.len() <= 4000).ok_or(INVALID)?;
        if field["type"] == "reference" && !uuid(text) {
            return Err(INVALID);
        }
        if field["required"] == true && text.trim().is_empty() {
            return Err(INVALID);
        }
        if field["type"] == "enum"
            && !field["values"]
                .as_array()
                .is_some_and(|v| v.iter().any(|v| v == text))
        {
            return Err(INVALID);
        }
    }
    Ok(())
}

fn validate_record(record: &Value, model: &Value) -> Result<()> {
    if !record["id"].as_str().is_some_and(uuid)
        || record["revision"].as_u64().is_none_or(|n| n == 0)
    {
        return Err(INVALID);
    }
    let mut values = record.as_object().ok_or(INVALID)?.clone();
    values.remove("id");
    values.remove("revision");
    validate_values(&Value::Object(values), model, true, false)
}

fn validate_manifest(value: &Value) -> Result<()> {
    if value["format"] != 1
        || value["title"]
            .as_str()
            .is_none_or(|s| s.is_empty() || s.len() > 200)
    {
        return Err(INVALID);
    }
    let models = value["models"].as_object().ok_or(INVALID)?;
    for model in models.values() {
        if model["version"].as_u64().is_none_or(|v| v == 0) {
            return Err(INVALID);
        }
        for field in model["fields"]
            .as_object()
            .filter(|f| !f.is_empty())
            .ok_or(INVALID)?
            .values()
        {
            if !matches!(
                field["type"].as_str(),
                Some("string" | "enum" | "reference")
            ) {
                return Err(INVALID);
            }
            if field["type"] == "reference"
                && !field["model"]
                    .as_str()
                    .is_some_and(|target| models.contains_key(target))
            {
                return Err(INVALID);
            }
            if field["type"] == "enum"
                && !field["values"]
                    .as_array()
                    .is_some_and(|v| !v.is_empty() && v.iter().all(Value::is_string))
            {
                return Err(INVALID);
            }
        }
    }
    let modules = value["ui_modules"]
        .as_array()
        .filter(|m| !m.is_empty() && m.len() <= 20)
        .ok_or(INVALID)?;
    let mut ids = std::collections::HashSet::new();
    for module in modules {
        let id = module["id"]
            .as_str()
            .filter(|s| !s.is_empty())
            .ok_or(INVALID)?;
        if !ids.insert(id)
            || !module["title"].is_string()
            || !module["group"].is_string()
            || !models.contains_key(module["model"].as_str().ok_or(INVALID)?)
        {
            return Err(INVALID);
        }
        if module["source"]
            .as_str()
            .is_none_or(|s| s.is_empty() || s.len() > 256 * 1024)
        {
            return Err(INVALID);
        }
        for (kind, operations) in [
            ("queries", &["list", "get"][..]),
            ("actions", &["create", "update"][..]),
        ] {
            for name in module["capabilities"][kind].as_array().ok_or(INVALID)? {
                let definition = &value[kind][name.as_str().ok_or(INVALID)?];
                let reference_read = kind == "queries"
                    && definition["operation"] == "get"
                    && models[module["model"].as_str().ok_or(INVALID)?]["fields"]
                        .as_object()
                        .ok_or(INVALID)?
                        .values()
                        .any(|field| {
                            field["type"] == "reference" && field["model"] == definition["model"]
                        });
                if (definition["model"] != module["model"] && !reference_read)
                    || !operations.contains(&definition["operation"].as_str().ok_or(INVALID)?)
                {
                    return Err(INVALID);
                }
            }
        }
    }
    Ok(())
}
