-- Kura extension hook for Tuist-managed deployments.
--
-- This file is *not* part of the Kura project — it's a Tuist consumer's
-- integration of Kura's extension API. Kura itself stays generic.
-- Other adopters write their own hooks.lua against the same API.
--
-- Three jobs, mirroring what the Tuist server does for `/api/cache/*`:
--
--   1. authenticate — forward the caller's Authorization header to
--      the Tuist server's `/api/projects` endpoint. All four token
--      shapes the server accepts (Guardian JWTs, legacy user tokens,
--      project tokens, account tokens) work without Kura needing to
--      know how any of them are laid out. Kura's built-in allow/deny
--      TTL caches absorb the callback cost — a hot bearer token costs
--      one roundtrip, then hits cache.
--
--   2. authorize — the principal carries the list of project handles
--      it can access. We resolve the request's target project from (in
--      order) `ctx.tenant_id` + `ctx.namespace_id`,
--      `ctx.query.account_handle` + `ctx.query.project_handle`, or
--      `ctx.query.tenant_id` + `ctx.query.namespace_id`, and require
--      the requested tenant to match `ctx.server_tenant_id` so one
--      account's Kura mesh cannot serve another account's namespace.
--
--   3. response_headers — for module-cache GETs we sign `ctx.query.hash`
--      with the same license signing key the central Tuist server
--      uses, so the CLI's existing `x-tuist-signature` verification
--      works against Kura without any client change.
--
-- Required Kura extension config (set by the chart / rollout worker):
--   * KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL  → https://tuist.dev (or staging)
--   * KURA_EXTENSION_SIGNER_TUIST_ALGORITHM      → hmac-sha256
--   * KURA_EXTENSION_SIGNER_TUIST_SECRET         → license signing key (raw bytes, base64-encoded)

local function authorization_header(headers)
  local authorization = headers.authorization or headers.Authorization
  if authorization == nil or authorization == "" then
    return nil
  end
  return authorization
end

local function project_handles(body)
  local projects = {}

  if body == nil or body.projects == nil then
    return projects
  end

  for _, project in ipairs(body.projects) do
    local full_name = project.full_name
    if full_name ~= nil and full_name ~= "" then
      table.insert(projects, string.lower(full_name))
    end
  end

  return projects
end

function authenticate(ctx)
  local authorization = authorization_header(ctx.headers)
  if authorization == nil then
    return {
      deny = { status = 401, message = "Missing Authorization header" },
      ttl_seconds = 3,
    }
  end

  local response = kura.http_json("tuist", {
    method = "GET",
    path = "/api/projects",
    headers = {
      ["authorization"] = authorization,
    },
  })

  if response.status == 200 and response.body and response.body.projects then
    return {
      principal = {
        id = "tuist",
        kind = "subject",
        attributes = {
          projects = project_handles(response.body),
        },
      },
      ttl_seconds = 60,
    }
  end

  if response.status == 401 then
    return {
      deny = { status = 401, message = "Invalid or expired token" },
      ttl_seconds = 3,
    }
  end

  -- Treat anything else (5xx, network errors that surfaced as a non-2xx)
  -- as transient: deny with a short TTL so we retry quickly when the
  -- server recovers. KURA_EXTENSION_FAIL_CLOSED_AUTHENTICATE controls
  -- what happens if Kura can't even invoke this hook.
  return {
    deny = { status = 503, message = "Authentication backend unavailable" },
    ttl_seconds = 3,
  }
end

local function request_tenant(ctx)
  local tenant = ctx.tenant_id

  if ctx.query ~= nil then
    if (tenant == nil or tenant == "") and ctx.query.account_handle ~= nil and ctx.query.account_handle ~= "" then
      tenant = ctx.query.account_handle
    end
    if (tenant == nil or tenant == "") and ctx.query.tenant_id ~= nil and ctx.query.tenant_id ~= "" then
      tenant = ctx.query.tenant_id
    end

  end

  if tenant ~= nil and tenant ~= "" then
    return string.lower(tenant)
  end

  return nil
end

local function request_namespace(ctx)
  local namespace = ctx.namespace_id

  if ctx.query ~= nil then
    if (namespace == nil or namespace == "") and ctx.query.project_handle ~= nil and ctx.query.project_handle ~= "" then
      namespace = ctx.query.project_handle
    end
    if (namespace == nil or namespace == "") and ctx.query.namespace_id ~= nil and ctx.query.namespace_id ~= "" then
      namespace = ctx.query.namespace_id
    end
  end

  if namespace ~= nil and namespace ~= "" then
    return string.lower(namespace)
  end

  return nil
end

local function request_project(ctx)
  local tenant = request_tenant(ctx)
  local namespace = request_namespace(ctx)

  if tenant ~= nil and namespace ~= nil then
    return tenant, namespace, tenant .. "/" .. namespace
  end

  return tenant, namespace, nil
end

function authorize(ctx, principal)
  if principal == nil then
    return {
      deny = { status = 401, message = "Unauthorized" },
      ttl_seconds = 3,
    }
  end

  local tenant, _, project = request_project(ctx)
  if project == nil then
    return {
      deny = { status = 403, message = "Missing tenant_id/account_handle or namespace_id/project_handle on request" },
      ttl_seconds = 3,
    }
  end

  local server_tenant = ctx.server_tenant_id
  if server_tenant == nil or server_tenant == "" then
    return {
      deny = { status = 503, message = "Server tenant is unavailable" },
      ttl_seconds = 3,
    }
  end

  server_tenant = string.lower(server_tenant)
  if tenant ~= server_tenant then
    return {
      deny = {
        status = 403,
        message = "Forbidden: tenant '" .. tenant .. "' is routed to server for '" .. server_tenant .. "'",
      },
      ttl_seconds = 3,
    }
  end

  local projects = principal.attributes and principal.attributes.projects or {}
  for _, candidate in ipairs(projects) do
    if candidate == project then
      return { allow = true, ttl_seconds = 60 }
    end
  end

  return {
    deny = {
      status = 403,
      message = "Forbidden: project '" .. project .. "' is not granted to this principal",
    },
    ttl_seconds = 3,
  }
end

function response_headers(ctx, _principal)
  -- Mirror the central server: only the module-cache GET path carries a
  -- signature, and it signs the `hash` query parameter. Other routes
  -- get no extra headers from this hook.
  if ctx.method == "GET"
    and ctx.route == "/api/cache/module/{id}"
    and ctx.status_code ~= nil
    and ctx.status_code < 400
    and ctx.query
    and ctx.query.hash ~= nil
  then
    return {
      sign = {
        header = "x-tuist-signature",
        signer = "tuist",
        payload = ctx.query.hash,
      },
    }
  end

  return {}
end
