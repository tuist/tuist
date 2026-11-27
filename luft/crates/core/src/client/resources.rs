//! Account-scoped declarative resources, separate from the explicit UI-code pilot.
use super::*;

const INVALID: &str = "Invalid resource response";
const CHANGED: &str = "The resource session changed. Open it again.";

#[derive(Default)]
pub(super) struct Resources {
    context: Option<Value>,
    descriptor: Value,
    release: Value,
    items: Vec<Value>,
    record: Value,
    pending: Option<Value>,
    has_more: bool,
    offset: u64,
    suspended: bool,
    historical: bool,
    query: Value,
}

impl MobileClient {
    pub(super) fn native_record_operation(
        &mut self,
        op: &str,
        args: &Value,
        host: &mut dyn Host,
    ) -> Result<Value> {
        self.collection_operation(op, args, host)
    }

    pub(super) fn collection_operation(
        &mut self,
        op: &str,
        args: &Value,
        host: &mut dyn Host,
    ) -> Result<Value> {
        let index = self.active()?;
        let generation = self.vault.generation;
        let owner = owner(&self.vault);
        if args["generation"].as_u64() != Some(generation) {
            return Err(CHANGED);
        }
        let account = self.account(index);
        if !segment(account) {
            return Err("Invalid account");
        }
        let base = endpoint(
            &server_url(&self.vault.profiles[index].server)?,
            &format!("api/accounts/{account}/"),
        );
        let mut state = std::mem::take(&mut self.resources);
        let result = self.resource_request(&mut state, index, &base, op, args, host);
        if generation != self.vault.generation {
            if owner.is_some() && owner == self::owner(&self.vault) {
                state.suspend();
                self.resources = state;
            } else {
                self.resources = Default::default();
            }
            return Err(CHANGED);
        }
        if result == Err(INVALID) {
            state.suspended = true;
        }
        let response = if op == "collections" || result == Err(CHANGED) {
            result
        } else {
            Ok(json!({"surface":state.snapshot(),"error":result.err()}))
        };
        self.resources = state;
        response
    }

    fn resource_request(
        &mut self,
        state: &mut Resources,
        index: usize,
        base: &Url,
        op: &str,
        args: &Value,
        host: &mut dyn Host,
    ) -> Result<Value> {
        if op == "collections" {
            return self.resource_catalog(state, index, base, host);
        }
        let surface = text(args, "surface")?;
        if !is_uuid(surface) {
            return Err("Invalid resource surface");
        }
        let message = op.starts_with("native_record_");
        let identity = if message {
            let thread = text(args, "thread")?;
            let message = text(args, "message")?;
            if !is_uuid(thread) || !is_uuid(message) {
                return Err("Invalid record reference");
            }
            json!({"thread":thread,"message":message})
        } else {
            let id = text(args, "collection")?;
            if !resource_id(id) {
                return Err("Invalid collection");
            }
            if let Some(record) = args["record"].as_str() {
                if !is_uuid(record) {
                    return Err("Invalid record ID");
                }
                json!({"collection":id,"record":record})
            } else {
                json!({"collection":id})
            }
        };
        let context = json!({"identity":identity,"surface":surface});
        let operation = op
            .strip_prefix(if message {
                "native_record_"
            } else {
                "collection_"
            })
            .ok_or("Unknown resource operation")?;
        if operation == "open" {
            if state.pending.is_some()
                && state
                    .context
                    .as_ref()
                    .is_some_and(|c| c["identity"] != identity)
            {
                return Err(CHANGED);
            }
            let pending = if state
                .context
                .as_ref()
                .is_some_and(|c| c["identity"] == identity)
            {
                state.pending.take()
            } else {
                None
            };
            let mut query = if state
                .context
                .as_ref()
                .is_some_and(|c| c["identity"] == identity)
                && state.query.is_object()
            {
                state.query.clone()
            } else {
                json!({})
            };
            // Reauthorize and restart paging without silently dropping the person's filters.
            query.as_object_mut().unwrap().remove("offset");
            *state = Resources {
                context: Some(context.clone()),
                suspended: true,
                pending,
                query,
                ..Default::default()
            };
            if message || identity["record"].is_string() {
                let path = if message {
                    format!(
                        "threads/{}/resources/{}",
                        identity["thread"].as_str().unwrap(),
                        identity["message"].as_str().unwrap()
                    )
                } else {
                    format!(
                        "collections/{}/records/{}",
                        identity["collection"].as_str().unwrap(),
                        identity["record"].as_str().unwrap()
                    )
                };
                let path = version_path(path, args)?;
                let entry = self.resource_http(state, index, base, &path, None, host)?;
                validate_descriptor(&entry["collection"]).map_err(|_| INVALID)?;
                validate_row(&entry["record"], &entry["collection"]).map_err(|_| INVALID)?;
                if !message
                    && (entry["record"]["id"] != identity["record"]
                        || entry["collection"]["id"] != identity["collection"])
                {
                    return Err(INVALID);
                }
                state.descriptor = entry["collection"].clone();
                state.record = entry["record"].clone();
                state.release = entry["release"].clone();
                state.historical = args.get("version").is_some() || entry["historical"] == true;
            } else {
                let catalog = self.resource_catalog(state, index, base, host)?;
                state.descriptor = catalog["collections"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .find(|c| c["id"] == identity["collection"])
                    .cloned()
                    .ok_or("Collection unavailable")?;
                state.release = catalog["release"].clone();
            }
            state.context = Some(context);
            state.suspended = false;
            if !message && identity["record"].is_null() {
                let query = state.query.clone();
                return self.resource_list(state, index, base, &query, host);
            }
            return Ok(Value::Null);
        }
        if state.context.as_ref() != Some(&context) {
            return Err(CHANGED);
        }
        if state.suspended {
            return Err("Open this resource again before continuing.");
        }
        let id = text(&state.descriptor, "id")?.to_owned();
        match operation {
            "close" => {
                state.suspended = true;
                state.items.clear();
                state.record = Value::Null;
                Ok(Value::Null)
            }
            "query" => self.resource_list(state, index, base, &args["input"], host),
            "refresh" => {
                let record = text(args, "id")?;
                if !is_uuid(record) {
                    return Err("Invalid record ID");
                }
                state.record = Value::Null;
                let path = version_path(format!("collections/{id}/records/{record}"), args)?;
                let entry = self.resource_http(state, index, base, &path, None, host)?;
                validate_descriptor(&entry["collection"]).map_err(|_| INVALID)?;
                if entry["collection"]["id"] != id || entry["record"]["id"] != record {
                    return Err(INVALID);
                }
                validate_row(&entry["record"], &entry["collection"]).map_err(|_| INVALID)?;
                state.descriptor = entry["collection"].clone();
                state.record = entry["record"].clone();
                state.release = entry["release"].clone();
                state.historical = args.get("version").is_some() || entry["historical"] == true;
                Ok(Value::Null)
            }
            "action" | "retry" => {
                if state.historical {
                    return Err("Historical records are read-only.");
                }
                if operation == "action" {
                    if state.pending.is_some() {
                        return Err("Retry the previous submission before saving again.");
                    }
                    let name = text(args, "action")?;
                    let method = state.descriptor["methods"]
                        .as_array()
                        .unwrap()
                        .iter()
                        .find(|m| m["id"] == name)
                        .ok_or("Method unavailable")?;
                    if method["operation"] == "close" && state.record["status"] != "open" {
                        return Err("Only an open record can be closed.");
                    }
                    let request = text(args, "request_id")?;
                    if !is_uuid(request) {
                        return Err("Invalid request ID");
                    }
                    let values = args["input"]["values"]
                        .as_object()
                        .ok_or("Invalid method input")?;
                    let mut input = serde_json::Map::new();
                    let fields = method_fields(method, &state.descriptor);
                    for (key, value) in values {
                        let field = fields
                            .iter()
                            .find(|f| f["id"] == key.as_str())
                            .ok_or("Unknown field")?;
                        let value = if field["type"] == "integer" {
                            json!(
                                value
                                    .as_str()
                                    .and_then(|s| s.parse::<i64>().ok())
                                    .ok_or("Enter a whole number.")?
                            )
                        } else if value == "" && field["nullable"] == true {
                            Value::Null
                        } else {
                            value.clone()
                        };
                        validate_field(&value, field)?;
                        input.insert(key.clone(), value);
                    }
                    if fields.iter().any(|f| {
                        f["required"] == true && !input.contains_key(f["id"].as_str().unwrap())
                    }) {
                        return Err("Complete the required fields.");
                    }
                    if method["operation"] != "create" {
                        if args["input"]["id"] != state.record["id"]
                            || args["input"]["expected_revision"] != state.record["revision"]
                            || state.record.is_null()
                        {
                            return Err("Reload this record before saving.");
                        }
                        input.insert("id".into(), state.record["id"].clone());
                        input.insert("expected_revision".into(), state.record["revision"].clone());
                    }
                    state.pending = Some(json!({"method":name,"request_id":request,"input":input}));
                }
                let pending = state.pending.clone().ok_or("Nothing to retry")?;
                let name = text(&pending, "method")?;
                if !state.descriptor["methods"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|m| m["id"] == name)
                {
                    return Err("Method unavailable");
                }
                let body = json!({"request_id":pending["request_id"],"input":pending["input"]});
                let row = self.resource_http(
                    state,
                    index,
                    base,
                    &format!("methods/{name}"),
                    Some(body),
                    host,
                )?;
                validate_row(&row, &state.descriptor).map_err(|_| INVALID)?;
                if pending["input"].get("id").is_some()
                    && (row["id"] != pending["input"]["id"]
                        || row["revision"].as_u64()
                            != pending["input"]["expected_revision"]
                                .as_u64()
                                .and_then(|r| r.checked_add(1)))
                {
                    return Err(INVALID);
                }
                state.pending = None;
                if let Some(item) = state.items.iter_mut().find(|r| r["id"] == row["id"]) {
                    *item = row.clone();
                } else {
                    state.items.insert(0, row.clone());
                }
                state.record = row;
                Ok(Value::Null)
            }
            _ => Err("Unknown resource operation"),
        }
    }

    fn resource_catalog(
        &mut self,
        state: &mut Resources,
        index: usize,
        base: &Url,
        host: &mut dyn Host,
    ) -> Result<Value> {
        let value = self.resource_http(state, index, base, "collections", None, host)?;
        let rows = value["collections"]
            .as_array()
            .filter(|r| r.len() <= 100)
            .ok_or(INVALID)?;
        let mut seen = HashSet::new();
        for row in rows {
            validate_descriptor(row).map_err(|_| INVALID)?;
            if !seen.insert(text(row, "id")?) {
                return Err(INVALID);
            }
        }
        Ok(value)
    }

    fn resource_list(
        &mut self,
        state: &mut Resources,
        index: usize,
        base: &Url,
        input: &Value,
        host: &mut dyn Host,
    ) -> Result<Value> {
        let input = input.as_object().ok_or("Invalid resource query")?;
        let next = input.get("next") == Some(&json!(true));
        let mut query = if next {
            if input.len() != 1 {
                return Err("Invalid resource query");
            }
            state.query.clone()
        } else {
            json!(input)
        };
        validate_query(&query, &state.descriptor)?;
        if next && (!state.has_more || state.offset >= 10_000) {
            return Err("No more records");
        }
        let offset = if next {
            state.offset
        } else {
            query["offset"].as_u64().unwrap_or(0)
        };
        query["offset"] = json!(offset);
        let limit = query["limit"].as_u64().unwrap_or(20);
        query["limit"] = json!(limit);
        let id = text(&state.descriptor, "id")?.to_owned();
        let response = self.resource_http(
            state,
            index,
            base,
            &format!("collections/{id}/query"),
            Some(query.clone()),
            host,
        )?;
        let rows = response["items"]
            .as_array()
            .filter(|r| r.len() <= limit as usize)
            .ok_or(INVALID)?;
        let mut seen = HashSet::new();
        for row in rows {
            validate_row(row, &state.descriptor).map_err(|_| INVALID)?;
            if !seen.insert(text(row, "id")?) {
                return Err(INVALID);
            }
        }
        if next {
            for row in rows {
                if let Some(existing) = state.items.iter_mut().find(|r| r["id"] == row["id"]) {
                    *existing = row.clone();
                } else {
                    state.items.push(row.clone());
                }
            }
        } else {
            state.items = rows.clone();
        }
        state.offset = offset + rows.len() as u64;
        state.has_more = response["has_more"].as_bool().ok_or(INVALID)?;
        if state.has_more && rows.is_empty() {
            return Err(INVALID);
        }
        state.query = query;
        Ok(Value::Null)
    }

    fn resource_http(
        &mut self,
        state: &mut Resources,
        index: usize,
        base: &Url,
        path: &str,
        body: Option<Value>,
        host: &mut dyn Host,
    ) -> Result<Value> {
        let (status, value) = self
            .send(
                index,
                if body.is_some() { "POST" } else { "GET" },
                base.join(path).map_err(|_| INVALID)?,
                body,
                host,
            )
            .inspect_err(|_| {
                state.suspended = true;
            })?;
        match status {
            200 => Ok(value),
            401 | 403 => {
                *state = Default::default();
                Err("Resource unavailable with this session.")
            }
            400 | 404 | 409 | 422 => {
                if path.starts_with("methods/") {
                    state.pending = None;
                }
                match status {
                    409 => Err("This record changed. Reload before editing again."),
                    404 => Err("Record not found."),
                    _ => Err("Check the method input and try again."),
                }
            }
            _ => Err("Resource unavailable. Retry the request."),
        }
    }
}

impl Resources {
    pub(super) fn suspend(&mut self) {
        let pending = self.pending.take();
        let context = self.context.take();
        let query = std::mem::take(&mut self.query);
        *self = Self {
            pending,
            context,
            query,
            suspended: true,
            ..Default::default()
        };
    }

    fn snapshot(&self) -> Value {
        if self.context.is_none() || self.suspended {
            return json!({"connected":false});
        }
        let fields: Vec<Value> = self.descriptor["fields"]
            .as_array()
            .unwrap()
            .iter()
            .map(|field| {
                let mut field = field.clone();
                field["title"] = field["label"].clone();
                field
            })
            .collect();
        let actions: Vec<Value> = self.descriptor["methods"].as_array().unwrap().iter().filter(|method| !self.historical && (method["operation"] != "close" || self.record["status"] == "open")).map(|method| {
            json!({"id":method["id"],"title":method["label"],"operation":method["operation"],"fields":method_fields(method,&self.descriptor)})
        }).collect();
        let items: Vec<Value> = self
            .items
            .iter()
            .map(|row| {
                let mut row = row.clone();
                row["_display_title"] = row
                    .get("title")
                    .or_else(|| row.get("name"))
                    .or_else(|| {
                        fields
                            .iter()
                            .filter(|field| field["type"] == "string")
                            .find_map(|field| row.get(field["id"].as_str()?))
                    })
                    .unwrap_or(&row["id"])
                    .clone();
                row
            })
            .collect();
        let query_fields = |key: &str| -> Vec<Value> {
            fields
                .iter()
                .filter(|field| {
                    self.descriptor[key]
                        .as_array()
                        .is_some_and(|names| names.contains(&field["id"]))
                })
                .cloned()
                .collect()
        };
        json!({"connected":true,"title":self.descriptor["title"],"model":self.descriptor["id"],"release":self.release,
            "fields":fields,"filter_fields":query_fields("filters"),"sort_fields":query_fields("sort"),"actions":actions,"items":items,"record":self.record,"list_query":"list","has_more":self.has_more,"can_retry":self.pending.is_some()})
    }
}

fn resource_id(id: &str) -> bool {
    segment(id) && id.len() <= 200
}

pub(super) fn owner(vault: &Vault) -> Option<(String, String, String)> {
    vault
        .profiles
        .iter()
        .find(|p| {
            Some(&p.id) == vault.active_profile_id.as_ref()
                && !p.rejected
                && !p.memberships_rejected
        })
        .map(|p| {
            (
                p.id.clone(),
                p.server.clone(),
                p.organization.as_ref().unwrap_or(&p.handle).clone(),
            )
        })
}

fn validate_query(query: &Value, descriptor: &Value) -> Result<()> {
    let object = query.as_object().ok_or("Invalid resource query")?;
    if object.keys().any(|k| {
        !matches!(
            k.as_str(),
            "search" | "filters" | "sort" | "direction" | "offset" | "limit"
        )
    }) {
        return Err("Invalid resource query");
    }
    if object
        .get("search")
        .is_some_and(|s| s.as_str().is_none_or(|s| s.len() > 200))
        || object
            .get("direction")
            .is_some_and(|d| !matches!(d.as_str(), Some("asc" | "desc")))
        || object
            .get("offset")
            .is_some_and(|n| n.as_u64().is_none_or(|n| n > 10_000))
        || object
            .get("limit")
            .is_some_and(|n| n.as_u64().is_none_or(|n| !(1..=50).contains(&n)))
    {
        return Err("Invalid resource query");
    }
    let fields = descriptor["fields"].as_array().ok_or(INVALID)?;
    if let Some(sort) = object.get("sort")
        && sort != "id"
        && !fields.iter().any(|f| f["id"] == *sort)
    {
        return Err("Unknown sort field");
    }
    if let Some(filters) = object.get("filters") {
        for (key, value) in filters
            .as_object()
            .filter(|f| f.len() <= 20)
            .ok_or("Invalid filters")?
        {
            let field = fields
                .iter()
                .find(|f| f["id"] == key.as_str())
                .ok_or("Unknown filter field")?;
            if !value.is_string() {
                return Err("Invalid filter value");
            }
            validate_field(value, field)?;
        }
    }
    Ok(())
}

fn version_path(path: String, args: &Value) -> Result<String> {
    match args.get("version") {
        None => Ok(path),
        Some(version) => Ok(format!(
            "{path}?version={}",
            version
                .as_u64()
                .filter(|n| *n > 0)
                .ok_or("Invalid record version")?
        )),
    }
}

fn method_fields(method: &Value, descriptor: &Value) -> Vec<Value> {
    if let Some(properties) = method["input"]["properties"].as_object() {
        properties
            .iter()
            .filter(|(key, _)| !matches!(key.as_str(), "id" | "expected_revision"))
            .map(|(key, schema)| {
                let mut field = schema.clone();
                field["id"] = json!(key);
                field["title"] = descriptor["fields"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .find(|f| f["id"] == key.as_str())
                    .map(|f| f["label"].clone())
                    .unwrap_or(json!(key));
                field["nullable"] = json!(
                    schema["type"]
                        .as_array()
                        .is_some_and(|types| types.contains(&json!("null")))
                );
                field["type"] = if schema["enum"].is_array() {
                    json!("enum")
                } else if schema["type"] == "integer" {
                    json!("integer")
                } else {
                    json!("string")
                };
                field["values"] = schema["enum"].clone();
                field["required"] = json!(
                    method["input"]["required"]
                        .as_array()
                        .is_some_and(|required| required.contains(&json!(key)))
                );
                field
            })
            .collect()
    } else if matches!(method["operation"].as_str(), Some("create" | "update")) {
        descriptor["fields"]
            .as_array()
            .unwrap()
            .iter()
            .map(|field| {
                let mut field = field.clone();
                field["title"] = field["label"].clone();
                field
            })
            .collect()
    } else {
        vec![]
    }
}

fn validate_descriptor(value: &Value) -> Result<()> {
    if !resource_id(text(value, "id")?) || text(value, "title")?.len() > 200 {
        return Err(INVALID);
    }
    let fields = value["fields"]
        .as_array()
        .filter(|f| f.len() <= 20)
        .ok_or(INVALID)?;
    let mut ids = HashSet::new();
    for field in fields {
        if !resource_id(text(field, "id")?)
            || !ids.insert(text(field, "id")?)
            || text(field, "label")?.len() > 200
            || !matches!(
                field["type"].as_str(),
                Some("string" | "enum" | "reference")
            )
        {
            return Err(INVALID);
        }
        if field["type"] == "reference" && !field["target"].as_str().is_some_and(resource_id) {
            return Err(INVALID);
        }
        if field["type"] == "enum"
            && !field["values"].as_array().is_some_and(|v| {
                v.len() <= 20 && v.iter().all(|v| v.as_str().is_some_and(|s| s.len() <= 100))
            })
        {
            return Err(INVALID);
        }
    }
    let methods = value["methods"]
        .as_array()
        .filter(|m| m.len() <= 20)
        .ok_or(INVALID)?;
    ids.clear();
    for method in methods {
        if !resource_id(text(method, "id")?)
            || !ids.insert(text(method, "id")?)
            || text(method, "label")?.len() > 200
            || !matches!(
                method["operation"].as_str(),
                Some("create" | "update" | "close" | "delete")
            )
        {
            return Err(INVALID);
        }
        if let Some(schema) = method.get("input") {
            let properties = schema["properties"]
                .as_object()
                .filter(|p| p.len() <= 20)
                .ok_or(INVALID)?;
            let required = schema["required"]
                .as_array()
                .filter(|r| r.len() <= 20)
                .ok_or(INVALID)?;
            if schema["type"] != "object"
                || schema["additionalProperties"] != false
                || required
                    .iter()
                    .any(|r| r.as_str().is_none_or(|r| !properties.contains_key(r)))
            {
                return Err(INVALID);
            }
            for (name, field) in properties {
                if !resource_id(name)
                    || !field.is_object()
                    || !(matches!(field["type"].as_str(), Some("string" | "integer"))
                        || field["type"] == json!(["string", "null"]))
                {
                    return Err(INVALID);
                }
                if let Some(values) = field.get("enum")
                    && !values.as_array().is_some_and(|v| {
                        v.len() <= 20
                            && v.iter().all(|v| v.as_str().is_some_and(|v| v.len() <= 100))
                    })
                {
                    return Err(INVALID);
                }
            }
        }
    }
    Ok(())
}

fn validate_field(value: &Value, field: &Value) -> Result<()> {
    if value.is_null() {
        return if field["nullable"] == false {
            Err("A value is required.")
        } else {
            Ok(())
        };
    }
    if field["type"] == "integer" {
        let n = value
            .as_i64()
            .filter(|n| n.abs_diff(0) <= 9_007_199_254_740_991)
            .ok_or("Invalid integer")?;
        if field["minimum"].as_i64().is_some_and(|min| n < min)
            || field["maximum"].as_i64().is_some_and(|max| n > max)
        {
            return Err("Number is outside the allowed range.");
        }
        return Ok(());
    }
    let value = value
        .as_str()
        .filter(|s| s.len() <= 4000)
        .ok_or("Invalid field value")?;
    let length = value.chars().count() as u64;
    if field["minLength"].as_u64().is_some_and(|min| length < min)
        || field["maxLength"].as_u64().is_some_and(|max| length > max)
    {
        return Err("Check the field length.");
    }
    if field["type"] == "reference" && !is_uuid(value)
        || field["type"] == "enum"
            && !field["values"]
                .as_array()
                .is_some_and(|values| values.iter().any(|v| v == value))
    {
        return Err("Invalid field value");
    }
    Ok(())
}

fn validate_row(row: &Value, descriptor: &Value) -> Result<()> {
    if !is_uuid(text(row, "id")?) || row["revision"].as_u64().is_none_or(|n| n == 0) {
        return Err(INVALID);
    }
    let fields = descriptor["fields"].as_array().ok_or(INVALID)?;
    let object = row.as_object().ok_or(INVALID)?;
    if object.keys().any(|key| {
        key != "id" && key != "revision" && !fields.iter().any(|f| f["id"] == key.as_str())
    }) {
        return Err(INVALID);
    }
    for field in fields {
        validate_field(row.get(text(field, "id")?).ok_or(INVALID)?, field).map_err(|_| INVALID)?;
    }
    Ok(())
}
