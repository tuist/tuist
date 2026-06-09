-- Kura extension hook for Tuist-managed deployments.
--
-- This file is *not* part of the Kura project — it's a Tuist consumer's
-- integration of Kura's extension API. Kura itself stays generic.
-- Other adopters write their own hooks.lua against the same API.
--
-- Three jobs:
--
--   1. authenticate — first try Tuist-issued Guardian JWTs locally.
--      New tokens carry `cache_grants`, so Kura can authorize the hot
--      path without a server roundtrip when the JWT already proves the
--      requested cache action. Legacy scope-less JWTs can still prove
--      project-scoped access from `claims.projects`.
--      If that misses, fall back to Tuist's OAuth introspection
--      endpoint. During rollout, project-scoped requests can still use
--      the legacy `/api/cache/access` endpoint if the introspection
--      client is not configured yet, but account-scoped requests
--      require introspection.
--
--   2. authorize — resolve the request target from `ctx.tenant_id` /
--      `ctx.namespace_id`, require the requested tenant to match
--      `ctx.server_tenant_id`, then check the target against first-
--      class account/project cache grants for the requested action.
--
--   3. response_headers — preserve the legacy Tuist cache API contract
--      by signing successful module downloads with x-tuist-signature.
--      Older CLIs validate this header before unpacking cache artifacts.
--
-- Required Kura extension config (set by the chart / rollout worker):
--   * KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL              → https://tuist.dev (or staging)
--   * KURA_EXTENSION_JWT_VERIFIER_TUIST_*                    → Guardian verifier for Tuist JWTs
--   * KURA_CONTROL_PLANE_CLIENT_ID                           → OAuth client ID used by Kura
--   * KURA_CONTROL_PLANE_CLIENT_SECRET                       → OAuth client secret used by Kura
--
-- Optional legacy module-cache signature config:
--   * KURA_EXTENSION_SIGNER_TUIST_LICENSE_ALGORITHM          → hmac-sha256
--   * KURA_EXTENSION_SIGNER_TUIST_LICENSE_SECRET             → base64 Tuist license signing key

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

local function env_value(key)
  if type(kura.env) ~= "function" then
    return nil
  end

  return kura.env(key)
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

local function append_unique(handles, value)
  for _, existing in ipairs(handles) do
    if existing == value then
      return
    end
  end
  table.insert(handles, value)
end

local function normalized_grant_bucket(bucket)
  return {
    read = normalized_handles(bucket and bucket.read or nil),
    write = normalized_handles(bucket and bucket.write or nil),
  }
end

local function cache_grants(body)
  local grants = body and body.cache_grants or nil

  return {
    account = normalized_grant_bucket(grants and grants.account or nil),
    project = normalized_grant_bucket(grants and grants.project or nil),
  }
end

local function grants_present(grants)
  return #grants.account.read > 0 or
    #grants.account.write > 0 or
    #grants.project.read > 0 or
    #grants.project.write > 0
end

local function flattened_handles(grants, scope)
  local flattened = {}
  local bucket = grants[scope]

  for _, handle in ipairs(bucket.read) do
    append_unique(flattened, handle)
  end

  for _, handle in ipairs(bucket.write) do
    append_unique(flattened, handle)
  end

  return flattened
end

local function principal_from_grants(id, kind, grants)
  return {
    id = id or "tuist",
    kind = kind or "subject",
    attributes = {
      cache_grants = grants,
      accounts = flattened_handles(grants, "account"),
      projects = flattened_handles(grants, "project"),
    },
  }
end

local function principal_from_legacy_handles(id, kind, accounts, projects)
  return {
    id = id or "tuist",
    kind = kind or "subject",
    attributes = {
      accounts = accounts,
      projects = projects,
    },
  }
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

  if requested_tenant == nil and ctx.transport ~= "grpc" then
    return nil, { status = 400, message = "Missing tenant_id/account_handle" }
  end

  if namespace == nil then
    return {
      scope = "account",
      account = tenant,
      namespace = nil,
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

local function request_action(ctx)
  local operation = string.lower(ctx.operation or "")

  if string.match(operation, "%.read$") or string.match(operation, "%.inspect$") then
    return "read"
  end

  if string.match(operation, "%.write$") or string.match(operation, "%.delete$") then
    return "write"
  end

  local method = string.upper(ctx.method or "")
  if method == "GET" or method == "HEAD" then
    return "read"
  end

  return "write"
end

local function grant_allows(grants, scope, action, identifier)
  local bucket = grants[scope]
  if bucket == nil then
    return false
  end

  for _, candidate in ipairs(bucket[action] or {}) do
    if candidate == identifier then
      return true
    end
  end

  if action == "read" then
    for _, candidate in ipairs(bucket.write or {}) do
      if candidate == identifier then
        return true
      end
    end
  end

  return false
end

local function introspection_client_configured()
  local client_id = env_value("KURA_CONTROL_PLANE_CLIENT_ID") or env_value("KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_ID")
  local client_secret = env_value("KURA_CONTROL_PLANE_CLIENT_SECRET") or env_value("KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_SECRET")

  return client_id ~= nil and client_id ~= "" and client_secret ~= nil and client_secret ~= ""
end

local function tuist_signature_configured()
  local secret = env_value("KURA_EXTENSION_SIGNER_TUIST_LICENSE_SECRET")

  return secret ~= nil and secret ~= ""
end

local function module_download_hash(ctx)
  if ctx.artifact_hash ~= nil and ctx.artifact_hash ~= "" then
    return ctx.artifact_hash
  end

  if ctx.query ~= nil and ctx.query.hash ~= nil and ctx.query.hash ~= "" then
    return ctx.query.hash
  end

  return nil
end

local authenticate_via_cache_access_endpoint

local function authenticate_via_introspection_endpoint(token, authorization, target)
  local client_id = env_value("KURA_CONTROL_PLANE_CLIENT_ID") or env_value("KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_ID")
  local client_secret = env_value("KURA_CONTROL_PLANE_CLIENT_SECRET") or env_value("KURA_EXTENSION_TUIST_INTROSPECT_CLIENT_SECRET")
  local response = kura.http_json("tuist", {
    method = "POST",
    path = "/oauth2/introspect",
    body = {
      client_id = client_id,
      client_secret = client_secret,
      token = token,
    },
  })

  if response.status == 200 and response.body then
    if response.body.active == true then
      return {
        principal = principal_from_grants(
          response.body.sub,
          response.body.principal_kind,
          cache_grants(response.body)
        ),
        ttl_seconds = 60,
      }
    end

    -- Legacy CLI compatibility: older clients can hold a token whose
    -- embedded grants predate a newly-created project. The server's
    -- /api/cache/access path still authorizes those project-scoped
    -- requests, so keep this fallback until those CLI versions are no
    -- longer supported.
    if target.scope == "project" then
      return authenticate_via_cache_access_endpoint(authorization)
    end

    return {
      deny = { status = 401, message = "Invalid or expired token" },
      ttl_seconds = 3,
    }
  end

  return {
    deny = { status = 503, message = "Authentication backend unavailable" },
    ttl_seconds = 3,
  }
end

authenticate_via_cache_access_endpoint = function(authorization)
  local response = kura.http_json("tuist", {
    method = "GET",
    path = "/api/cache/access",
    headers = {
      ["authorization"] = authorization,
    },
  })

  if response.status == 200 and response.body then
    return {
      principal = principal_from_legacy_handles(
        "tuist",
        "subject",
        {},
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

  if ok then
    local grants = cache_grants(claims)
    local action = request_action(ctx)

    if grants_present(grants) and grant_allows(grants, target.scope, action, target.identifier) then
      return {
        principal = principal_from_grants(claims.sub, claims.type, grants),
        ttl_seconds = 60,
      }
    end

    if claims.scopes == nil then
      local projects = normalized_handles(claims.projects)

      if target.scope == "project" then
        for _, candidate in ipairs(projects) do
          if candidate == target.identifier then
            return {
              principal = principal_from_legacy_handles(claims.sub, claims.type, {}, projects),
              ttl_seconds = 60,
            }
          end
        end
      end
    end
  end

  if introspection_client_configured() then
    return authenticate_via_introspection_endpoint(token, authorization, target)
  end

  if target.scope == "project" then
    return authenticate_via_cache_access_endpoint(authorization)
  end

  return {
    deny = { status = 503, message = "Authentication backend unavailable" },
    ttl_seconds = 3,
  }
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

  local action = request_action(ctx)
  local grants = principal.attributes and principal.attributes.cache_grants or nil

  if grants ~= nil and grant_allows(grants, target.scope, action, target.identifier) then
    return { allow = true, ttl_seconds = 60 }
  end

  if grants == nil then
    if target.scope == "project" then
      local projects = principal.attributes and principal.attributes.projects or {}
      for _, candidate in ipairs(projects) do
        if candidate == target.identifier then
          return { allow = true, ttl_seconds = 60 }
        end
      end
    end
  end

  return {
    deny = {
      status = 403,
      message = "Forbidden: " .. target.scope .. " '" .. target.identifier .. "' is not granted to this principal for " .. action,
    },
    ttl_seconds = 3,
  }
end

function response_headers(ctx, principal)
  if not tuist_signature_configured() then
    return {}
  end

  if ctx.route ~= "/api/cache/module/{id}" then
    return {}
  end

  local method = string.upper(ctx.method or "")
  if method ~= "GET" then
    return {}
  end

  if ctx.status_code == nil or ctx.status_code >= 400 then
    return {}
  end

  local hash = module_download_hash(ctx)
  if hash == nil then
    return {}
  end

  return {
    sign = {
      header = "x-tuist-signature",
      signer = "tuist_license",
      payload = hash,
    },
  }
end
