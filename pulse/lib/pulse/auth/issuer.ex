defmodule Pulse.Auth.Issuer do
  @moduledoc """
  Offline verification of credentials minted by one trusted issuer (Tuist in
  the hosted product).

  Unlike `Pulse.Auth.WorkloadIdentity`, whose bindings live in Pulse's
  configuration, these credentials carry their own authority: the `tenant`
  and `scope` claims decide what a request may do, so new tenants need no
  Pulse configuration change.

  Two credential forms are accepted, both signed JWTs verified against the
  issuer's JWKS (RS256, ES256 or EdDSA/Ed25519):

    * Access tokens (`typ: at+jwt`), short-lived, any scope.
    * Ingest keys (`pulse_ik_<jwt>`, `typ: pulse-ik+jwt`), long-lived,
      `ingest` scope only, revocable by `jti` through the status list.

  The signed status list (`typ: pulse-status+jwt`) carries revocations,
  suspended tenants, Sentry projects and ingest quotas. Keys and the status
  list are cached node-locally by `Pulse.Auth.IssuerCache`; verification never
  calls the issuer on the request path.

  Expired but otherwise valid tokens fail as `:auth_unavailable` (retryable)
  for ingestion within a grace period, so collector retry queues survive an
  issuer outage instead of dropping data on a permanent 401.
  """

  alias Pulse.Auth.IssuerCache
  alias Pulse.Runtime

  require Logger

  @skew_seconds 60
  @max_token_bytes 8192
  @ingest_key_prefix "pulse_ik_"
  @claims_cache_entries 10_000
  @claims_cache_seconds 3600
  @id_pattern ~r/\A[A-Za-z0-9_.-]{1,128}\z/
  @principal_types ~w(human agent service)
  @config_keys ~w(issuer audience jwks_url status_url ca_file refresh_interval_seconds key_retention_seconds
                  expired_grace_seconds max_access_ttl_seconds max_ingest_key_ttl_seconds mirror)

  @type principal :: %{
          tenant: String.t(),
          subject: String.t(),
          type: String.t(),
          act: String.t() | nil,
          scopes: [String.t()],
          kind: :access | :ingest_key,
          jti: String.t() | nil,
          iat: integer()
        }

  @doc "The validated configuration, or nil when no issuer is trusted."
  def config, do: Runtime.get_env(:pulse, __MODULE__)

  @doc "Children to start: the key/status cache, only when an issuer is configured."
  def children, do: if(config(), do: [IssuerCache], else: [])

  @doc """
  Validates decoded `PULSE_ISSUER_JSON`. Raises on any invalid field so a
  misconfiguration stops the node at boot.
  """
  def parse!(raw) when is_map(raw) do
    if Map.keys(raw) -- @config_keys != [],
      do: fail!("unknown keys (expected #{Enum.join(@config_keys, ", ")})")

    issuer = raw["issuer"]
    audience = raw["audience"]
    check!(https?(issuer), "issuer must be an https URL")

    check!(
      https?(audience) and not String.ends_with?(audience, "/"),
      "audience must be an https URL without a trailing slash"
    )

    check!(https?(raw["jwks_url"]), "jwks_url must be an https URL")
    check!(is_nil(raw["status_url"]) or https?(raw["status_url"]), "status_url must be an https URL")

    if ca = raw["ca_file"], do: check!(is_binary(ca) and File.regular?(ca), "ca_file must name a readable file")

    %{
      issuer: issuer,
      audience: audience,
      audiences: [audience, audience <> "/mcp"],
      jwks_url: raw["jwks_url"],
      status_url: raw["status_url"],
      ca_file: raw["ca_file"],
      refresh_interval_seconds: int!(raw, "refresh_interval_seconds", 60, 10..3600),
      key_retention_seconds: int!(raw, "key_retention_seconds", 7 * 86_400, 3600..(30 * 86_400)),
      expired_grace_seconds: int!(raw, "expired_grace_seconds", 3600, 0..86_400),
      max_access_ttl_seconds: int!(raw, "max_access_ttl_seconds", 86_400, 60..(7 * 86_400)),
      max_ingest_key_ttl_seconds: int!(raw, "max_ingest_key_ttl_seconds", 366 * 86_400, 86_400..(366 * 86_400)),
      mirror: Map.get(raw, "mirror", true) == true
    }
  end

  def parse!(_), do: fail!("must be a JSON object")

  defp int!(raw, key, default, range) do
    value = Map.get(raw, key, default)
    check!(is_integer(value) and value in range, "#{key} must be an integer in #{inspect(range)}")
    value
  end

  defp https?(url) when is_binary(url) do
    uri = URI.parse(url)
    uri.scheme == "https" and uri.host not in [nil, ""] and is_nil(uri.userinfo) and is_nil(uri.fragment)
  end

  defp https?(_), do: false

  @doc "Whether `token` is shaped like a credential from this issuer (never one for another verifier)."
  def credential?(@ingest_key_prefix <> _), do: true

  def credential?(token) when is_binary(token) and byte_size(token) <= @max_token_bytes do
    case split(token) do
      {:ok, %{"typ" => typ}, _, _} when is_binary(typ) -> String.downcase(typ) in typ(:access)
      _ -> false
    end
  end

  def credential?(_), do: false

  @doc """
  Finds and authenticates an issuer credential on `conn`: a Bearer token, or a
  Basic password whose username must equal the credential's tenant. Returns
  `:none` when no issuer is configured or the request carries another kind of
  credential, so other verifiers handle it.
  """
  def from_conn(conn) do
    with %{} = config <- config(),
         {:ok, token, username} <- credential(conn),
         true <- credential?(token) do
      case authenticate(token, config) do
        {:ok, %{tenant: tenant}} when not is_nil(username) and username != tenant -> {:error, :invalid_token}
        result -> result
      end
    else
      _ -> :none
    end
  end

  defp credential(conn) do
    with [header] <- Plug.Conn.get_req_header(conn, "authorization"),
         [scheme, token] when token != "" <- String.split(header, " ", parts: 2) do
      if String.downcase(scheme) == "bearer", do: {:ok, String.trim(token), nil}, else: basic(conn)
    else
      _ -> :error
    end
  end

  defp basic(conn) do
    case Pulse.Auth.basic_credentials(conn) do
      {:ok, username, password} -> {:ok, password, username}
      :error -> :error
    end
  end

  @doc """
  Verifies `token`. Returns the principal, `{:error, {:expired, principal}}`
  for a recently expired but otherwise valid token, or `{:error, reason}` with
  `:invalid_token`, `:forbidden` (suspended tenant) or `:auth_unavailable`.
  """
  @spec authenticate(String.t(), map(), integer()) :: {:ok, principal()} | {:error, term()}
  def authenticate(token, config \\ config(), now \\ System.os_time(:second))

  def authenticate(token, config, now) when is_binary(token) and byte_size(token) <= @max_token_bytes do
    {kind, jwt} =
      case token do
        @ingest_key_prefix <> jwt -> {:ingest_key, jwt}
        jwt -> {:access, jwt}
      end

    case run(jwt, kind, config, now) do
      # An unknown kid usually means the issuer rotated keys since the last
      # refresh: ask the cache for one rate-limited refresh, then retry once.
      {:error, :unknown_kid} ->
        IssuerCache.refresh()

        case run(jwt, kind, config, now) do
          {:error, :unknown_kid} -> log_reject(:unknown_kid, kind)
          result -> result
        end

      result ->
        result
    end
  end

  def authenticate(_token, _config, _now), do: {:error, :invalid_token}

  defp run(jwt, kind, config, now) do
    with {:ok, keys, status} <- material(),
         {:ok, claims} <- verified_claims(jwt, kind, keys, status, config, now) |> reject(kind),
         {:ok, principal} <- principal(claims, kind, config) |> reject(kind),
         :ok <- times(claims, kind, config, now) |> expired(principal) |> reject(kind),
         :ok <- status_checks(principal, status) do
      {:ok, principal}
    end
  end

  defp typ(:access), do: ["at+jwt", "application/at+jwt"]
  defp typ(:ingest_key), do: ["pulse-ik+jwt"]

  # The signature was verified: keep the principal of a recently expired token
  # so authorization can apply the ingest grace window.
  defp expired({:error, :expired}, principal), do: {:error, {:expired, principal}}
  defp expired(other, _principal), do: other

  defp material do
    case IssuerCache.material() do
      {:ok, keys, status} ->
        {:ok, keys, status}

      :unavailable ->
        Logger.warning("issuer credentials unavailable: no fresh signing keys or status list")
        {:error, :auth_unavailable}
    end
  end

  defp reject({:error, reason}, kind) when is_atom(reason) and reason != :unknown_kid, do: log_reject(reason, kind)

  defp reject(other, _kind), do: other

  defp log_reject(reason, kind) do
    Logger.warning("issuer #{kind} rejected: #{reason}")
    {:error, :invalid_token}
  end

  # Signature verification is the expensive step, so its result is cached
  # node-locally by credential kind and token digest. A hit still requires the
  # signing key to be in the current key set and its kid not to be revoked;
  # claims, times and the status list are checked on every request by `run/4`.
  # Entries live at most until the token's grace window ends, capped at one
  # hour, and only validly signed tokens are stored. A full table stops caching
  # rather than evicting.
  defp verified_claims(jwt, kind, keys, status, config, now) do
    table = Runtime.table(__MODULE__)
    id = {kind, :crypto.hash(:sha256, jwt)}

    case lookup(table, id, now) do
      {:ok, key, claims} ->
        cond do
          key.kid in revoked_kids(status) -> {:error, :revoked_kid}
          key in keys -> {:ok, claims}
          true -> verify_and_cache(table, id, jwt, kind, keys, status, config, now)
        end

      :miss ->
        verify_and_cache(table, id, jwt, kind, keys, status, config, now)
    end
  end

  defp lookup(table, id, now) do
    case :ets.whereis(table) != :undefined && :ets.lookup(table, id) do
      [{^id, key, claims, expires_at}] when expires_at > now -> {:ok, key, claims}
      _ -> :miss
    end
  end

  defp verify_and_cache(table, id, jwt, kind, keys, status, config, now) do
    with {:ok, key, claims} <- verify_signed(jwt, typ(kind), keys, status) do
      with %{"exp" => exp} when is_integer(exp) <- claims,
           ref when ref != :undefined <- :ets.whereis(table),
           true <- :ets.info(ref, :size) < @claims_cache_entries do
        expires_at = min(exp + config.expired_grace_seconds + @skew_seconds, now + @claims_cache_seconds)
        :ets.insert(ref, {id, key, claims, expires_at})
      end

      {:ok, claims}
    end
  end

  @doc "Drops cached verified claims whose lifetime has ended."
  def prune_claims(now \\ System.os_time(:second)) do
    with ref when ref != :undefined <- :ets.whereis(Runtime.table(__MODULE__)) do
      :ets.select_delete(ref, [{{:_, :_, :_, :"$1"}, [{:"=<", :"$1", now}], [true]}])
    end

    :ok
  end

  @doc """
  Verifies a compact JWS whose header `typ` is one of `typs` against `keys`,
  skipping keys revoked by `status`. Returns the decoded claims.
  """
  def verify_jws(jwt, typs, keys, status) do
    with {:ok, _key, claims} <- verify_signed(jwt, typs, keys, status), do: {:ok, claims}
  end

  defp verify_signed(jwt, typs, keys, status) do
    with {:ok, header, signing_input, signature} <- split(jwt),
         :ok <- check_header(header, typs),
         :ok <- not_revoked(header["kid"], status),
         {:ok, key} <- key(keys, header),
         :ok <- signature(key, signing_input, signature),
         [_, payload] = String.split(signing_input, "."),
         {:ok, claims} when is_map(claims) <- JSON.decode(Base.url_decode64!(payload, padding: false)) do
      {:ok, key, claims}
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      _ -> {:error, :malformed_token}
    end
  end

  defp not_revoked(kid, status), do: if(kid in revoked_kids(status), do: {:error, :revoked_kid}, else: :ok)

  defp signature(key, input, signature),
    do: if(signed?(key, input, signature), do: :ok, else: {:error, :invalid_signature})

  defp revoked_kids(%{revoked_kids: kids}), do: kids
  defp revoked_kids(_), do: []

  defp split(jwt) do
    with [h, p, s] <- String.split(jwt, "."),
         {:ok, header_json} <- Base.url_decode64(h, padding: false),
         {:ok, header} when is_map(header) <- JSON.decode(header_json),
         {:ok, signature} when signature != "" <- Base.url_decode64(s, padding: false),
         {:ok, _} <- Base.url_decode64(p, padding: false) do
      {:ok, header, h <> "." <> p, signature}
    else
      _ -> {:error, :malformed_token}
    end
  end

  defp check_header(header, typs) do
    cond do
      header["alg"] not in ["RS256", "ES256", "EdDSA"] -> {:error, :unsupported_algorithm}
      Map.has_key?(header, "crit") -> {:error, :unsupported_header}
      not (is_binary(header["typ"]) and String.downcase(header["typ"]) in typs) -> {:error, :wrong_type}
      not (is_binary(header["kid"]) and header["kid"] != "") -> {:error, :missing_kid}
      true -> :ok
    end
  end

  defp key(keys, %{"kid" => kid, "alg" => alg}) do
    case Enum.filter(keys, &(&1.kid == kid)) do
      [%{alg: ^alg} = key] -> {:ok, key}
      [_] -> {:error, :algorithm_mismatch}
      [] -> {:error, :unknown_kid}
      _ -> {:error, :ambiguous_key}
    end
  end

  defp signed?(%{alg: "RS256", n: n, e: e, size: size}, input, signature),
    do: byte_size(signature) == size and :crypto.verify(:rsa, :sha256, input, signature, [e, n])

  defp signed?(%{alg: "ES256", point: point}, input, <<r::binary-size(32), s::binary-size(32)>>) do
    :crypto.verify(:ecdsa, :sha256, input, der_signature(r, s), [point, :secp256r1])
  rescue
    _ -> false
  end

  defp signed?(%{alg: "EdDSA", x: x}, input, <<_::binary-size(64)>> = signature) do
    :crypto.verify(:eddsa, :none, input, signature, [x, :ed25519])
  rescue
    _ -> false
  end

  defp signed?(_key, _input, _signature), do: false

  # JWS ES256 signatures are raw r||s; Erlang expects a DER ECDSA-Sig-Value.
  defp der_signature(r, s) do
    body = der_integer(r) <> der_integer(s)
    <<0x30, byte_size(body)>> <> body
  end

  defp der_integer(bytes) do
    trimmed =
      case String.trim_leading(bytes, <<0>>) do
        "" -> <<0>>
        <<1::1, _::bitstring>> = high -> <<0>> <> high
        value -> value
      end

    <<0x02, byte_size(trimmed)>> <> trimmed
  end

  defp principal(claims, kind, config) do
    scopes = if is_binary(claims["scope"]), do: String.split(claims["scope"], " ", trim: true), else: []
    act = claims["act"]
    type = Map.get(claims, "principal_type", if(act, do: "agent", else: "service"))

    checks = [
      bad_issuer: claims["iss"] == config.issuer,
      bad_audience: audience?(claims["aud"], config.audiences),
      bad_subject: id?(claims["sub"]),
      bad_tenant: tenant?(claims["tenant"]),
      missing_scope: scopes != [],
      ingest_key_scope: kind != :ingest_key or scopes == ["ingest"],
      missing_jti: kind != :ingest_key or id?(claims["jti"]),
      bad_jti: is_nil(claims["jti"]) or id?(claims["jti"]),
      bad_actor: actor?(act),
      bad_principal_type: type in @principal_types
    ]

    case first_failure(checks) do
      {:error, _} = error ->
        error

      :ok ->
        {:ok,
         %{
           tenant: claims["tenant"],
           subject: claims["sub"],
           type: type,
           act: act && act["sub"],
           scopes: Enum.uniq(scopes),
           kind: kind,
           jti: claims["jti"],
           iat: claims["iat"]
         }}
    end
  end

  defp id?(value), do: is_binary(value) and Regex.match?(@id_pattern, value)
  defp tenant?(value), do: id?(value) and value not in [".", ".."]
  defp actor?(act), do: is_nil(act) or (is_map(act) and id?(act["sub"]))

  # The first check that does not hold, in order, as `{:error, reason}`.
  defp first_failure(checks) do
    case Enum.find(checks, fn {_reason, ok?} -> not ok? end) do
      nil -> :ok
      {reason, _} -> {:error, reason}
    end
  end

  defp audience?(aud, accepted) when is_binary(aud), do: aud in accepted
  defp audience?([_ | _] = aud, accepted), do: Enum.any?(aud, &(is_binary(&1) and &1 in accepted))
  defp audience?(_, _), do: false

  defp times(claims, kind, config, now) do
    max_ttl = if kind == :ingest_key, do: config.max_ingest_key_ttl_seconds, else: config.max_access_ttl_seconds

    with {:ok, exp, iat, nbf} <- time_claims(claims),
         :ok <-
           first_failure(
             token_not_yet_valid: max(iat, nbf) <= now + @skew_seconds,
             token_ttl_exceeded: exp >= iat and exp - iat <= max_ttl
           ) do
      cond do
        exp > now - @skew_seconds -> :ok
        now - exp <= config.expired_grace_seconds -> {:error, :expired}
        true -> {:error, :token_expired}
      end
    end
  end

  defp time_claims(%{"exp" => exp, "iat" => iat} = claims) when is_integer(exp) and is_integer(iat) do
    case Map.get(claims, "nbf", iat) do
      nbf when is_integer(nbf) -> {:ok, exp, iat, nbf}
      _ -> {:error, :bad_time_claims}
    end
  end

  defp time_claims(_claims), do: {:error, :bad_time_claims}

  defp status_checks(_principal, nil), do: :ok

  defp status_checks(principal, status) do
    cond do
      principal.tenant in status.suspended_tenants ->
        Logger.warning("issuer credential refused: tenant #{inspect(principal.tenant)} is suspended")
        {:error, :forbidden}

      principal.jti && MapSet.member?(status.revoked_credentials, principal.jti) ->
        log_reject(:revoked_credential, principal.kind)

      Map.get(status.revoked_before, principal.tenant, 0) > principal.iat ->
        log_reject(:revoked_before, principal.kind)

      true ->
        :ok
    end
  end

  @doc """
  Authorizes an authentication result for `tenant` and `capability`
  (`:read`, `:ingest`). Expired ingest credentials fail as retryable.
  """
  def authorize({:ok, principal}, tenant, capability) do
    cond do
      principal.tenant != tenant ->
        Logger.warning(
          "issuer credential forbidden: #{principal.subject} is not authorized for tenant #{inspect(tenant)}"
        )

        {:error, :forbidden}

      Atom.to_string(capability) not in principal.scopes ->
        Logger.warning("issuer credential forbidden: #{principal.subject} lacks the #{capability} scope")
        {:error, :forbidden}

      true ->
        :ok
    end
  end

  def authorize({:error, {:expired, %{tenant: tenant}}}, tenant, :ingest), do: {:error, :auth_unavailable}
  def authorize({:error, {:expired, _}}, _tenant, _capability), do: {:error, :invalid_token}
  def authorize({:error, reason}, _tenant, _capability), do: {:error, reason}

  @doc "The audit identity of `principal`: its subject, or `<subject>.via.<actor>` when delegated."
  def actor_id(%{subject: subject, act: nil}), do: subject

  def actor_id(%{subject: subject, act: act}) do
    id = "#{subject}.via.#{act}"
    if byte_size(id) <= 128, do: id, else: subject
  end

  @doc "Parses and verifies a fetched JWKS document; keys Pulse cannot use are skipped."
  def parse_jwks(document) do
    with {:ok, %{"keys" => keys}} when is_list(keys) <- JSON.decode(document),
         [_ | _] = usable <- for(raw <- keys, {:ok, key} <- [jwk(raw)], do: key) do
      {:ok, usable}
    else
      [] -> {:error, :no_usable_keys}
      _ -> {:error, :invalid_jwks}
    end
  end

  defp jwk(%{"kid" => kid} = raw) when is_binary(kid) and kid != "" do
    cond do
      Enum.any?(~w(d p q dp dq qi k), &Map.has_key?(raw, &1)) -> {:error, :private_key}
      Map.get(raw, "use", "sig") != "sig" -> {:error, :not_signing_key}
      true -> public_key(raw)
    end
  end

  defp jwk(_), do: {:error, :invalid_key}

  defp public_key(%{"kty" => "RSA", "kid" => kid, "n" => n, "e" => e} = raw) do
    with "RS256" <- Map.get(raw, "alg", "RS256"),
         {:ok, n} when n != "" <- decode(n),
         {:ok, e} when e != "" <- decode(e),
         bits when bits >= 2048 <- bit_size(String.trim_leading(n, <<0>>)) do
      {:ok, %{kid: kid, alg: "RS256", n: n, e: e, size: div(bits + 7, 8)}}
    else
      _ -> {:error, :invalid_key}
    end
  end

  defp public_key(%{"kty" => "EC", "crv" => "P-256", "kid" => kid, "x" => x, "y" => y} = raw) do
    with "ES256" <- Map.get(raw, "alg", "ES256"),
         {:ok, <<_::binary-size(32)>> = x} <- decode(x),
         {:ok, <<_::binary-size(32)>> = y} <- decode(y) do
      {:ok, %{kid: kid, alg: "ES256", point: <<4>> <> x <> y}}
    else
      _ -> {:error, :invalid_key}
    end
  end

  defp public_key(%{"kty" => "OKP", "crv" => "Ed25519", "kid" => kid, "x" => x} = raw) do
    with alg when alg in ["EdDSA", "Ed25519"] <- Map.get(raw, "alg", "EdDSA"),
         {:ok, <<_::binary-size(32)>> = x} <- decode(x) do
      {:ok, %{kid: kid, alg: "EdDSA", x: x}}
    else
      _ -> {:error, :invalid_key}
    end
  end

  defp public_key(_), do: {:error, :invalid_key}

  defp decode(value) when is_binary(value), do: Base.url_decode64(value, padding: false)
  defp decode(_), do: :error

  @doc """
  Verifies a fetched status list JWT against `keys` and returns the parsed
  status, or an error. `current` is the status already held: an older
  version is refused so a replayed signed document cannot undo revocations.
  """
  def parse_status(jwt, keys, current, config, now \\ System.os_time(:second)) do
    with {:ok, claims} <- verify_jws(String.trim(jwt), ["pulse-status+jwt"], keys, current),
         :ok <- status_claims(claims, config, now),
         :ok <- newer(claims["version"], current),
         {:ok, status} <- status_fields(claims) do
      if jwt_kid(jwt) in status.revoked_kids, do: {:error, :revoked_kid}, else: {:ok, status}
    end
  end

  defp newer(_version, nil), do: :ok
  defp newer(version, %{version: current}), do: if(version >= current, do: :ok, else: {:error, :stale_version})

  defp jwt_kid(jwt) do
    case split(String.trim(jwt)) do
      {:ok, header, _, _} -> header["kid"]
      _ -> nil
    end
  end

  # Integer checks come first, so the later comparisons only see integers.
  defp status_claims(claims, config, now) do
    first_failure(
      bad_issuer: claims["iss"] == config.issuer,
      bad_audience: audience?(claims["aud"], config.audiences),
      bad_version: is_integer(claims["version"]) and claims["version"] >= 0,
      bad_time_claims: is_integer(claims["iat"]) and is_integer(claims["exp"]),
      not_yet_valid: claims["iat"] <= now + @skew_seconds,
      expired: claims["exp"] > now
    )
  end

  defp status_fields(claims) do
    ids = fn key -> Map.get(claims, key, []) end
    revoked_before = Map.get(claims, "revoked_before", %{})
    projects = Map.get(claims, "sentry_projects", %{})
    quotas = Map.get(claims, "quotas", %{})

    valid? =
      Enum.all?(~w(revoked_kids revoked_credentials suspended_tenants), &id_list?(ids.(&1))) and
        revoked_before?(revoked_before) and projects?(projects) and is_map(quotas) and Enum.all?(quotas, &quota?/1)

    if valid? do
      {:ok,
       %{
         version: claims["version"],
         exp: claims["exp"],
         revoked_kids: ids.("revoked_kids"),
         revoked_credentials: MapSet.new(ids.("revoked_credentials")),
         suspended_tenants: MapSet.new(ids.("suspended_tenants")),
         revoked_before: revoked_before,
         sentry_projects: projects,
         quotas: Map.new(quotas, fn {tenant, quota} -> {tenant, quota["ingest_bytes_per_second"]} end)
       }}
    else
      {:error, :invalid_status}
    end
  end

  defp id_list?(values), do: is_list(values) and Enum.all?(values, &(is_binary(&1) and byte_size(&1) in 1..256))

  defp revoked_before?(map), do: is_map(map) and Enum.all?(map, fn {tenant, at} -> id?(tenant) and is_integer(at) end)

  defp projects?(map), do: is_map(map) and map_size(map) <= 100_000 and Enum.all?(map, &Pulse.Sentry.valid_project?/1)

  defp quota?({tenant, %{"ingest_bytes_per_second" => rate} = quota}),
    do: id?(tenant) and map_size(quota) == 1 and is_integer(rate) and rate > 0

  defp quota?(_), do: false

  @doc "Whether `tenant` is suspended by the current status list."
  def suspended?(tenant) do
    case config() && IssuerCache.material() do
      {:ok, _keys, %{suspended_tenants: suspended}} -> MapSet.member?(suspended, tenant)
      _ -> false
    end
  end

  @doc "Sentry projects published in the status list (empty without one)."
  def sentry_projects do
    case config() && IssuerCache.material() do
      {:ok, _keys, %{sentry_projects: projects}} -> projects
      _ -> %{}
    end
  end

  defp check!(true, _message), do: :ok
  defp check!(_false, message), do: fail!(message)

  defp fail!(message), do: raise(ArgumentError, "PULSE_ISSUER_JSON: " <> message)
end
