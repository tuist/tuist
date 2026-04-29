-- Kura extension hook for Tuist-managed deployments.
--
-- This file is *not* part of the Kura project — it's a Tuist consumer's
-- integration of Kura's extension API. Kura itself stays generic.
-- Other adopters write their own hooks.lua against the same API.
--
-- Three jobs, mirroring what the Tuist server does for `/api/cache/*`:
--
--   1. authenticate — extract the bearer token from the Authorization
--      header and ask the Tuist server to resolve it to a principal
--      (HTTP callback). All four token shapes the server accepts
--      (Guardian JWTs, legacy user tokens, project tokens, account
--      tokens) work without Kura needing to know how any of them are
--      laid out. Kura's built-in allow/deny TTL caches absorb the
--      callback cost — a hot bearer token costs one roundtrip, then
--      hits cache.
--
--   2. authorize — the principal returned by the server includes the
--      list of account handles it has cache permission on. We allow
--      iff `ctx.tenant_id` (the Kura mesh's tenant, set to the account
--      handle at deploy time) is in that list.
--
--   3. response_headers — for module-cache GETs we sign `ctx.query.hash`
--      with the same license signing key the central Tuist server
--      uses, so the CLI's existing `x-tuist-signature` verification
--      works against Kura without any client change.
--
-- Required Kura extension config (set by the chart / rollout worker):
--   * KURA_EXTENSION_HTTP_CLIENT_TUIST_BASE_URL  → https://tuist.dev (or staging)
--   * KURA_EXTENSION_HTTP_CLIENT_TUIST_HEADERS_AUTHORIZATION
--       → "Bearer <internal shared secret>"  (gates the verify endpoint)
--   * KURA_EXTENSION_SIGNER_TUIST_ALGORITHM      → hmac-sha256
--   * KURA_EXTENSION_SIGNER_TUIST_SECRET         → license signing key (raw bytes, base64-encoded)

local function bearer(headers)
  local authorization = headers.authorization or headers.Authorization
  if authorization == nil or authorization == "" then
    return nil
  end
  return string.gsub(authorization, "^Bearer%s+", "")
end

function authenticate(ctx)
  local token = bearer(ctx.headers)
  if token == nil or token == "" then
    return {
      deny = { status = 401, message = "Missing Authorization header" },
      ttl_seconds = 3,
    }
  end

  local response = kura.http_json("tuist", {
    method = "POST",
    path = "/api/internal/auth/verify",
    headers = { ["content-type"] = "application/json" },
    body = { token = token },
  })

  if response.status == 200 and response.body and response.body.principal then
    local principal = response.body.principal
    return {
      principal = {
        id = principal.id,
        kind = principal.kind,
        attributes = principal,
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

function authorize(ctx, principal)
  if principal == nil then
    return {
      deny = { status = 401, message = "Unauthorized" },
      ttl_seconds = 3,
    }
  end

  -- Kura sets ctx.tenant_id to KURA_TENANT_ID, which the rollout worker
  -- sets to the account handle the mesh was provisioned for. The
  -- principal's account_handles list is what the Tuist server returns
  -- from /api/internal/auth/verify.
  local tenant = ctx.tenant_id
  if tenant == nil or tenant == "" then
    return {
      deny = { status = 403, message = "Tenant unavailable" },
      ttl_seconds = 3,
    }
  end

  local handles = principal.attributes and principal.attributes.account_handles or {}
  for _, handle in ipairs(handles) do
    if handle == tenant then
      return { allow = true, ttl_seconds = 60 }
    end
  end

  return {
    deny = { status = 403, message = "Forbidden" },
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
