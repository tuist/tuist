local function bearer(headers)
  local authorization = headers.authorization
  if authorization == nil then
    return nil
  end

  return string.gsub(authorization, "^Bearer%s+", "")
end

function authenticate(ctx)
  local token = bearer(ctx.headers)
  if token == nil or token == "" then
    return {
      deny = {
        status = 401,
        message = "Missing Authorization header",
      },
      ttl_seconds = 3,
    }
  end

  local claims = kura.jwt_verify("primary", token)
  return {
    principal = {
      id = claims.sub,
      kind = "user",
      attributes = claims,
    },
    ttl_seconds = 60,
  }
end

function authorize(ctx, principal)
  if principal == nil then
    return {
      deny = {
        status = 401,
        message = "Unauthorized",
      },
      ttl_seconds = 3,
    }
  end

  if ctx.namespace_id == nil or ctx.namespace_id == "" then
    return {
      allow = true,
      ttl_seconds = 60,
    }
  end

  if principal.attributes.namespace_id == ctx.namespace_id then
    return {
      allow = true,
      ttl_seconds = 60,
    }
  end

  return {
    deny = {
      status = 403,
      message = "Forbidden",
    },
    ttl_seconds = 3,
  }
end

function response_headers(ctx, principal)
  if ctx.route == "/api/cache/module/{id}"
    and ctx.method == "GET"
    and ctx.status_code ~= nil
    and ctx.status_code < 400
    and ctx.query.hash ~= nil
  then
    return {
      sign = {
        header = "x-cache-signature",
        signer = "cache_primary",
        payload = ctx.query.hash,
      }
    }
  end

  return {}
end
