-- Kura extension hook for Tuist-managed deployments.
--
-- This file is *not* part of the Kura project — it's a Tuist consumer's
-- integration of Kura's extension API. Kura itself stays generic.
-- Other adopters write their own hooks.lua against the same API.
--
-- Two jobs:
--
--   1. authenticate — first try the current cache service's JWT fast
--      path: verify Tuist-issued Guardian JWTs locally and see whether
--      `claims.accounts` or `claims.projects` already covers the
--      requested cache scope. If that misses (non-JWT token, invalid
--      JWT, or the claim set was trimmed and doesn't include this
--      account/project), fall back to Tuist's `/api/cache/access`
--      endpoint. That keeps all token shapes working without making the
--      hot path pay a server roundtrip when the JWT already proves
--      access.
--
--   2. authorize — the principal carries first-class account-scoped
--      and project-scoped cache access. We resolve the request target
--      from `ctx.tenant_id` / `ctx.namespace_id`. Tuist reserves one
--      explicit namespace (`~account`) for account-scoped binaries;
--      every other namespace remains project-scoped. We also require
--      the requested tenant to match `ctx.server_tenant_id` so one
--      account's Kura mesh cannot serve another account's namespace.
--
-- Required Kura extension config (set by the chart / rollout worker):
--   * KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL  → https://tuist.dev (or staging)
--   * KURA_EXTENSION_JWT_VERIFIER_TUIST_*        → Guardian verifier for Tuist JWTs

local ACCOUNT_SCOPE_NAMESPACE = "~account"

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

local function normalized_handles(handles)
  local normalized = {}

  if handles == nil then
    return normalized
  end

  for _, handle in ipairs(handles) do
    if handle ~= nil and handle ~= "" then
      table.insert(normalized, string.lower(handle))
    end
  end

  return normalized
end

local function account_handles(body)
  return normalized_handles(body and body.accounts or nil)
end

local function project_handles(body)
  local projects = {}

  if body == nil or body.projects == nil then
    return projects
  end

  for _, project in ipairs(body.projects) do
    local full_name = project
    if type(project) == "table" then
      full_name = project.full_name
    end
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

local function request_target(ctx)
  local tenant = server_tenant(ctx)
  local requested_tenant = request_tenant(ctx)
  local namespace = request_namespace(ctx)

  if tenant == nil then
    return nil, { status = 503, message = "Server tenant is unavailable" }
  end

  if requested_tenant ~= nil and requested_tenant ~= tenant then
    return nil, {
      status = 403,
      message = "Forbidden: tenant '" .. requested_tenant .. "' is routed to server for '" .. tenant .. "'",
    }
  end

  if namespace == nil then
    return nil, { status = 403, message = "Missing namespace_id/project_handle on request" }
  end

  if namespace == ACCOUNT_SCOPE_NAMESPACE then
    return {
      scope = "account",
      account = tenant,
      namespace = namespace,
      identifier = tenant,
    }, nil
  end

  return {
    scope = "project",
    account = tenant,
    namespace = namespace,
    identifier = tenant .. "/" .. namespace,
  }, nil
end

local function principal_from_cache_access(id, kind, accounts, projects)
  return {
    id = id or "tuist",
    kind = kind or "subject",
    attributes = {
      accounts = accounts,
      projects = projects,
    },
  }
end

local function authenticate_via_cache_access_endpoint(authorization)
  local response = kura.http_json("tuist", {
    method = "GET",
    path = "/api/cache/access",
    headers = {
      ["authorization"] = authorization,
    },
  })

  if response.status == 200 and response.body then
    return {
      principal = principal_from_cache_access(
        "tuist",
        "subject",
        account_handles(response.body),
        project_handles(response.body)
      ),
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
  local target, deny = request_target(ctx)
  if target == nil then
    return {
      deny = deny,
      ttl_seconds = 3,
    }
  end

  local ok, claims = pcall(function()
    return kura.jwt_verify("tuist", token)
  end)

  if ok and target ~= nil then
    local accounts = normalized_handles(claims.accounts)
    local projects = normalized_handles(claims.projects)

    if target.scope == "account" then
      for _, candidate in ipairs(accounts) do
        if candidate == target.identifier then
          return {
            principal = principal_from_cache_access(claims.sub, claims.type, accounts, projects),
            ttl_seconds = 60,
          }
        end
      end
    else
      for _, candidate in ipairs(projects) do
        if candidate == target.identifier then
          return {
            principal = principal_from_cache_access(claims.sub, claims.type, accounts, projects),
            ttl_seconds = 60,
          }
        end
      end
    end
  end

  return authenticate_via_cache_access_endpoint(authorization)
end

function authorize(ctx, principal)
  if principal == nil then
    return {
      deny = { status = 401, message = "Unauthorized" },
      ttl_seconds = 3,
    }
  end

  local target, deny = request_target(ctx)
  if target == nil then
    return {
      deny = deny,
      ttl_seconds = 3,
    }
  end

  if target.scope == "account" then
    local accounts = principal.attributes and principal.attributes.accounts or {}
    for _, candidate in ipairs(accounts) do
      if candidate == target.identifier then
        return { allow = true, ttl_seconds = 60 }
      end
    end

    return {
      deny = {
        status = 403,
        message = "Forbidden: account '" .. target.identifier .. "' is not granted to this principal",
      },
      ttl_seconds = 3,
    }
  end

  local projects = principal.attributes and principal.attributes.projects or {}
  for _, candidate in ipairs(projects) do
    if candidate == target.identifier then
      return { allow = true, ttl_seconds = 60 }
    end
  end

  return {
    deny = {
      status = 403,
      message = "Forbidden: project '" .. target.identifier .. "' is not granted to this principal",
    },
    ttl_seconds = 3,
  }
end
