-- Kura extension hook for Tuist-managed deployments.
--
-- This file is *not* part of the Kura project — it's a Tuist consumer's
-- integration of Kura's extension API. Kura itself stays generic.
-- Other adopters write their own hooks.lua against the same API.
--
-- Three jobs, mirroring what the Tuist server does for `/api/cache/*`:
--
--   1. authenticate — first try the current cache service's JWT fast
--      path: verify Tuist-issued Guardian JWTs locally and see whether
--      `claims.projects` already contains the requested full handle.
--      If that misses (non-JWT token, invalid JWT, or the claim set was
--      trimmed and doesn't include this project), fall back to the
--      Tuist server's `/api/projects` endpoint. That keeps all token
--      shapes working without making the hot path pay a server
--      roundtrip when the JWT already proves access.
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
--   * KURA_EXTENSION_JWT_VERIFIER_TUIST_*        → Guardian verifier for Tuist JWTs
--   * KURA_EXTENSION_SIGNER_TUIST_ALGORITHM      → hmac-sha256
--   * KURA_EXTENSION_SIGNER_TUIST_SECRET         → license signing key (raw bytes, base64-encoded)

local function authorization_header(headers)
  local authorization = headers.authorization or headers.Authorization
  if authorization == nil or authorization == "" then
    return nil
  end
  return authorization
end

local function bearer_token(headers)
  local authorization = authorization_header(headers)
  if authorization == nil then
    return nil
  end
  return string.gsub(authorization, "^Bearer%s+", "")
end

local function normalized_projects(projects)
  local normalized = {}

  if projects == nil then
    return normalized
  end

  for _, project in ipairs(projects) do
    if project ~= nil and project ~= "" then
      table.insert(normalized, string.lower(project))
    end
  end

  return normalized
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

local function server_tenant(ctx)
  local tenant = ctx.server_tenant_id

  if tenant ~= nil and tenant ~= "" then
    return string.lower(tenant)
  end

  return nil
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
  local tenant = server_tenant(ctx)
  local requested_tenant = request_tenant(ctx)
  local namespace = request_namespace(ctx)

  if tenant == nil then
    return nil, nil, nil, 503, "Server tenant is unavailable"
  end

  if requested_tenant ~= nil and requested_tenant ~= tenant then
    return tenant, namespace, nil, 403, "Forbidden: tenant '" .. requested_tenant .. "' is routed to server for '" .. tenant .. "'"
  end

  if namespace ~= nil then
    return tenant, namespace, tenant .. "/" .. namespace, nil, nil
  end

  return tenant, namespace, nil, 403, "Missing namespace_id/project_handle on request"
end

local function principal_from_projects(id, kind, projects)
  return {
    id = id or "tuist",
    kind = kind or "subject",
    attributes = {
      projects = projects,
    },
  }
end

local function authenticate_via_projects_endpoint(authorization)
  local response = kura.http_json("tuist", {
    method = "GET",
    path = "/api/projects",
    headers = {
      ["authorization"] = authorization,
    },
  })

  if response.status == 200 and response.body and response.body.projects then
    return {
      principal = principal_from_projects("tuist", "subject", project_handles(response.body)),
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

function authenticate(ctx)
  local authorization = authorization_header(ctx.headers)
  if authorization == nil then
    return {
      deny = { status = 401, message = "Missing Authorization header" },
      ttl_seconds = 3,
    }
  end

  local token = bearer_token(ctx.headers)
  local _, _, project = request_project(ctx)
  local ok, claims = pcall(function()
    return kura.jwt_verify("tuist", token)
  end)

  if ok and project ~= nil then
    local projects = normalized_projects(claims.projects)

    for _, candidate in ipairs(projects) do
      if candidate == project then
        return {
          principal = principal_from_projects(claims.sub, claims.type, projects),
          ttl_seconds = 60,
        }
      end
    end
  end

  return authenticate_via_projects_endpoint(authorization)
end

function authorize(ctx, principal)
  if principal == nil then
    return {
      deny = { status = 401, message = "Unauthorized" },
      ttl_seconds = 3,
    }
  end

  local _, _, project, status, message = request_project(ctx)
  if project == nil then
    return {
      deny = { status = status, message = message },
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
