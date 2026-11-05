defmodule Pulse.Auth.WorkloadIdentity do
  @moduledoc """
  Offline verification of Kubernetes projected ServiceAccount tokens.

  Each trust entry pins an issuer string, accepted audiences, a maximum token
  lifetime, the cluster's public signing keys (JWKS) and explicit principal
  bindings. Kubernetes clusters commonly share the default issuer string, so
  the signing key, not the issuer, identifies the trusted cluster: a token is
  attributed to the entry whose pinned key verified its signature, and only
  then are that entry's issuer, audience and bindings checked.

  Keys are either pinned inline or fetched from a JWKS URL by
  `Pulse.Auth.JWKS`, which caches them node-locally. While a URL source has no
  fresh keys, tokens that no other key verifies fail as `:auth_unavailable`
  rather than being attributed to any entry.

  Only RS256 is accepted. Tokens are never logged; rejections log the detailed
  reason and the trust entry name only.
  """

  alias Pulse.Auth.JWKS
  alias Pulse.Runtime

  require Logger

  @skew_seconds 60
  @max_token_bytes 16_384
  @default_max_ttl 3600
  @capabilities %{"read" => :read, "ingest" => :ingest}
  @entry_keys ~w(name issuer audiences max_token_ttl_seconds keys bindings)
  @url_keys ~w(type url ca_file token_file refresh_interval_seconds)
  @sa_prefix "system:serviceaccount:"

  @type capability :: :read | :ingest

  @doc "The configured trust entries (already validated by `parse!/1` at boot)."
  def trust, do: Runtime.get_env(:pulse, __MODULE__, []) |> Keyword.get(:trust, [])

  @doc """
  Whether `token` is shaped like a JWT: three base64url segments whose header
  decodes to a JSON object naming an `alg`. Only such bearers are routed here.
  """
  def jwt?(token) when is_binary(token) and byte_size(token) <= @max_token_bytes do
    match?({:ok, %{"alg" => _}, _, _}, split(token))
  end

  def jwt?(_), do: false

  @doc """
  Verifies `token` and authorizes it for `tenant` and `capability`. Returns
  `:invalid_token` for every authentication failure, `:forbidden` when an
  authenticated principal lacks a binding for the tenant and capability, and
  `:auth_unavailable` when no key verified the token while a JWKS URL source
  could not supply fresh keys.
  """
  @spec verify(String.t(), String.t(), capability(), list(), integer()) ::
          :ok | {:error, :invalid_token | :forbidden | :auth_unavailable}
  def verify(token, tenant, capability, trust \\ trust(), now \\ System.os_time(:second)) do
    case authenticate(token, trust, now) do
      {:ok, principal} ->
        if Enum.any?(principal.bindings, &(&1.tenant == tenant and capability in &1.capabilities)) do
          :ok
        else
          Logger.warning(
            "workload identity forbidden: #{principal.subject} (trust #{principal.trust}) " <>
              "has no #{capability} binding for tenant #{inspect(tenant)}"
          )

          {:error, :forbidden}
        end

      {:error, {:keys_unavailable, _}} ->
        Logger.warning("workload identity unavailable: a JWKS URL source has no fresh keys")
        {:error, :auth_unavailable}

      {:error, {reason, trust_name}} ->
        Logger.warning("workload identity rejected: #{reason} (trust #{trust_name || "none"})")
        {:error, :invalid_token}
    end
  end

  @doc """
  Authenticates `token` against `trust`, returning the principal and its
  bindings or `{:error, {reason, trust_name | nil}}` with a detailed reason.
  """
  def authenticate(token, trust, now) when is_binary(token) and byte_size(token) <= @max_token_bytes do
    with {:ok, header, signing_input, signature} <- split(token) |> tag(nil),
         :ok <- check_header(header) |> tag(nil),
         {:ok, entry, payload} <- verify_signature(trust, header["kid"], signing_input, signature),
         {:ok, claims} <- decode_json(payload, :malformed_token) |> tag(entry),
         :ok <- validate(claims, entry, now) |> tag(entry),
         {:ok, subject} <- service_account(claims) |> tag(entry) do
      case Enum.filter(entry.bindings, &(&1.subject == subject)) do
        [] -> {:error, {:unknown_subject, entry.name}}
        bindings -> {:ok, %{trust: entry.name, subject: subject, bindings: bindings}}
      end
    end
  end

  def authenticate(_token, _trust, _now), do: {:error, {:malformed_token, nil}}

  defp tag({:error, reason}, entry), do: {:error, {reason, entry && entry.name}}
  defp tag(other, _entry), do: other

  defp split(token) do
    with [h, p, s] <- String.split(token, "."),
         {:ok, header_json} <- Base.url_decode64(h, padding: false),
         {:ok, header} when is_map(header) <- JSON.decode(header_json),
         {:ok, signature} when signature != "" <- Base.url_decode64(s, padding: false),
         {:ok, _} <- Base.url_decode64(p, padding: false) do
      {:ok, header, h <> "." <> p, signature}
    else
      _ -> {:error, :malformed_token}
    end
  end

  defp check_header(%{"alg" => "RS256"} = header) do
    cond do
      Map.has_key?(header, "crit") -> {:error, :unsupported_header}
      Map.get(header, "typ", "JWT") not in ["JWT", "jwt"] -> {:error, :unsupported_header}
      not (is_binary(header["kid"]) and header["kid"] != "") -> {:error, :missing_kid}
      true -> :ok
    end
  end

  defp check_header(_header), do: {:error, :unsupported_algorithm}

  # Inline kids are unique (enforced by `parse!/1`), but fetched kids are only
  # known at runtime, so exactly one candidate key must verify the signature;
  # a key shared by two entries is ambiguous and rejected. An unknown kid asks
  # URL sources for a rate-limited refresh, which covers issuer key rotation.
  defp verify_signature(trust, kid, signing_input, signature) do
    {candidates, unavailable?} =
      case candidates(trust, kid) do
        {[], _} ->
          for entry <- trust, entry.jwks_url, do: JWKS.refresh(entry)
          candidates(trust, kid)

        found ->
          found
      end

    case Enum.filter(candidates, fn {_entry, key} -> signed_by?(key, signing_input, signature) end) do
      [{entry, _key}] ->
        [_, payload] = String.split(signing_input, ".")
        {:ok, entry, Base.url_decode64!(payload, padding: false)}

      [_, _ | _] ->
        {:error, {:ambiguous_key, nil}}

      [] ->
        {:error, {no_key_reason(candidates, unavailable?), nil}}
    end
  end

  defp candidates(trust, kid) do
    Enum.reduce(trust, {[], false}, fn entry, {found, unavailable?} ->
      case entry_keys(entry) do
        :unavailable -> {found, true}
        keys -> {found ++ for(key <- keys, key.kid == kid, do: {entry, key}), unavailable?}
      end
    end)
  end

  defp entry_keys(%{jwks_url: nil, keys: keys}), do: keys
  defp entry_keys(entry), do: JWKS.cached(entry)

  defp no_key_reason([], true), do: :keys_unavailable
  defp no_key_reason([], false), do: :unknown_kid
  defp no_key_reason(_candidates, _unavailable?), do: :invalid_signature

  defp signed_by?(key, signing_input, signature),
    do: byte_size(signature) == key.size and :crypto.verify(:rsa, :sha256, signing_input, signature, [key.e, key.n])

  defp decode_json(binary, reason) do
    case JSON.decode(binary) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, reason}
    end
  end

  defp validate(claims, entry, now) do
    cond do
      claims["iss"] != entry.issuer -> {:error, :bad_issuer}
      not audience?(claims["aud"], entry.audiences) -> {:error, :bad_audience}
      true -> validate_times(claims["exp"], claims["iat"], Map.get(claims, "nbf", claims["iat"]), entry, now)
    end
  end

  defp validate_times(exp, iat, nbf, entry, now) when is_integer(exp) and is_integer(iat) and is_integer(nbf) do
    cond do
      exp <= now - @skew_seconds -> {:error, :token_expired}
      iat > now + @skew_seconds or nbf > now + @skew_seconds -> {:error, :token_not_yet_valid}
      exp < iat or exp - iat > entry.max_token_ttl_seconds -> {:error, :token_ttl_exceeded}
      true -> :ok
    end
  end

  defp validate_times(_exp, _iat, _nbf, _entry, _now), do: {:error, :bad_time_claims}

  defp audience?(aud, accepted) when is_binary(aud), do: aud in accepted
  defp audience?([_ | _] = aud, accepted), do: Enum.any?(aud, &(is_binary(&1) and &1 in accepted))
  defp audience?(_, _), do: false

  defp service_account(%{"sub" => @sa_prefix <> rest = subject} = claims) do
    case {String.split(rest, ":"), claims["kubernetes.io"]} do
      {[namespace, name], %{"namespace" => namespace, "serviceaccount" => %{"name" => name}}}
      when namespace != "" and name != "" ->
        {:ok, subject}

      {[namespace, name], _} when namespace != "" and name != "" ->
        {:error, :bad_kubernetes_claims}

      _ ->
        {:error, :not_service_account}
    end
  end

  defp service_account(_claims), do: {:error, :not_service_account}

  @doc """
  Validates decoded trust configuration (a JSON array) and returns normalized
  entries. Raises on any invalid entry so a misconfiguration stops the node at
  boot instead of failing open or closed later on traffic.
  """
  def parse!(entries) when is_list(entries) and length(entries) <= 64 do
    trust = Enum.with_index(entries, &entry!/2)
    names = Enum.map(trust, & &1.name)
    kids = for entry <- trust, key <- entry.keys, do: key.kid

    if length(Enum.uniq(names)) != length(names), do: fail!("trust entry names must be unique")
    if length(Enum.uniq(kids)) != length(kids), do: fail!("key IDs (kid) must be unique across all trust entries")
    trust
  end

  def parse!(_), do: fail!("must be a JSON array of at most 64 trust entries")

  defp entry!(%{} = raw, index) do
    if Map.keys(raw) -- @entry_keys != [],
      do: fail!("entry #{index} has unknown keys (expected #{Enum.join(@entry_keys, ", ")})")

    name = raw["name"]
    issuer = raw["issuer"]
    audiences = raw["audiences"]
    ttl = Map.get(raw, "max_token_ttl_seconds", @default_max_ttl)

    check!(is_binary(name) and Regex.match?(~r/\A[A-Za-z0-9_.-]{1,128}\z/, name), "entry #{index} needs a name")
    check!(is_binary(issuer) and issuer != "", "#{name}: issuer is required")

    check!(
      is_list(audiences) and audiences != [] and Enum.all?(audiences, &(is_binary(&1) and &1 != "")),
      "#{name}: audiences must be a non-empty list of strings"
    )

    check!(is_integer(ttl) and ttl in 600..86_400, "#{name}: max_token_ttl_seconds must be an integer in 600..86400")
    {keys, jwks_url} = key_source!(raw["keys"], name)

    %{
      name: name,
      issuer: issuer,
      audiences: audiences,
      max_token_ttl_seconds: ttl,
      keys: keys,
      jwks_url: jwks_url,
      bindings: bindings!(raw["bindings"], name)
    }
  end

  defp entry!(_raw, index), do: fail!("entry #{index} must be an object")

  # `jwks` is the JWKS object, or that document as a JSON string so operators
  # can paste `/openid/v1/jwks` output verbatim.
  defp key_source!(%{"type" => "inline", "jwks" => jwks} = source, name)
       when is_binary(jwks) and map_size(source) == 2 do
    case JSON.decode(jwks) do
      {:ok, %{} = decoded} -> key_source!(%{source | "jwks" => decoded}, name)
      _ -> fail!("#{name}: keys.jwks is not a valid JSON document")
    end
  end

  defp key_source!(%{"type" => "inline", "jwks" => %{"keys" => [_ | _] = keys}} = source, name)
       when map_size(source) == 2, do: {Enum.map(keys, &jwk!(&1, name)), nil}

  defp key_source!(%{"type" => "url"} = source, name) do
    check!(
      Map.keys(source) -- @url_keys == [],
      "#{name}: keys has unknown fields (expected #{Enum.join(@url_keys, ", ")})"
    )

    url = source["url"]
    uri = is_binary(url) && URI.parse(url)
    check!((uri && uri.scheme == "https") and uri.host not in [nil, ""], "#{name}: keys.url must be an https URL")
    refresh = Map.get(source, "refresh_interval_seconds", 300)
    check!(is_integer(refresh) and refresh in 60..3600, "#{name}: keys.refresh_interval_seconds must be in 60..3600")

    # Files are mounted by the deployment, so their absence is a misconfiguration
    # worth stopping for; their contents are read again on every fetch.
    for field <- ["ca_file", "token_file"], Map.has_key?(source, field) do
      path = source[field]
      check!(is_binary(path) and File.regular?(path), "#{name}: keys.#{field} must name a readable file")
    end

    {[], %{url: url, ca_file: source["ca_file"], token_file: source["token_file"], refresh_interval_seconds: refresh}}
  end

  defp key_source!(_source, name),
    do:
      fail!(
        ~s(#{name}: keys must be {"type": "inline", "jwks": {"keys": [...]}} with at least one key, ) <>
          ~s(or {"type": "url", "url": "https://..."})
      )

  @doc """
  Parses a fetched JWKS document. Keys Pulse cannot use (non-RSA, non-RS256,
  weak, or carrying private material) are skipped; at least one must remain.
  """
  def parse_jwks(document) do
    with {:ok, %{"keys" => keys}} when is_list(keys) <- JSON.decode(document),
         [_ | _] = usable <- for(raw <- keys, {:ok, key} <- [jwk(raw)], do: key) do
      {:ok, usable}
    else
      [] -> {:error, :no_usable_keys}
      _ -> {:error, :invalid_jwks}
    end
  end

  defp jwk!(raw, name) do
    case jwk(raw) do
      {:ok, key} -> key
      {:error, message} -> fail!("#{name}: #{message}")
    end
  end

  defp jwk(%{"kty" => "RSA", "kid" => kid, "n" => n, "e" => e} = jwk) when is_binary(kid) and kid != "" do
    with {:ok, n} when is_binary(n) <- decode_uint(n),
         {:ok, e} when is_binary(e) <- decode_uint(e),
         bits when bits >= 2048 <- bit_size(n) - leading_zero_bits(n),
         true <- odd_at_least?(n, 3) and odd_at_least?(e, 3) do
      cond do
        Map.has_key?(jwk, "d") -> {:error, "key #{kid} contains private key material"}
        Map.get(jwk, "alg", "RS256") != "RS256" -> {:error, "key #{kid} must be RS256"}
        Map.get(jwk, "use", "sig") != "sig" -> {:error, "key #{kid} must be a signing key"}
        true -> {:ok, %{kid: kid, n: n, e: e, size: div(bits + 7, 8)}}
      end
    else
      _ -> {:error, "key #{kid} must have a base64url RSA modulus of at least 2048 bits and an odd exponent >= 3"}
    end
  end

  defp jwk(_jwk),
    do: {:error, ~s(every key must be an RSA JWK with kid, n and e \(quote "n" in YAML, which reads n as false\))}

  defp decode_uint(value) when is_binary(value) and value != "", do: Base.url_decode64(value, padding: false)
  defp decode_uint(_), do: :error

  defp odd_at_least?(binary, min) do
    value = :binary.decode_unsigned(binary)
    value >= min and rem(value, 2) == 1
  end

  defp leading_zero_bits(<<0::1, rest::bitstring>>), do: 1 + leading_zero_bits(rest)
  defp leading_zero_bits(_), do: 0

  defp bindings!([_ | _] = bindings, name) when length(bindings) <= 1024 do
    parsed = Enum.map(bindings, &binding!(&1, name))
    pairs = Enum.map(parsed, &{&1.subject, &1.tenant})
    if length(Enum.uniq(pairs)) != length(pairs), do: fail!("#{name}: duplicate subject/tenant binding")
    parsed
  end

  defp bindings!(_bindings, name), do: fail!("#{name}: bindings must be a non-empty list of at most 1024 entries")

  defp binding!(%{"subject" => subject, "tenant" => tenant, "capabilities" => [_ | _] = caps} = binding, name)
       when map_size(binding) == 3 and is_binary(subject) and is_binary(tenant) do
    with @sa_prefix <> rest <- subject,
         [namespace, sa] when namespace != "" and sa != "" <- String.split(rest, ":"),
         true <- Regex.match?(~r/\A[A-Za-z0-9_.-]{1,128}\z/, tenant),
         mapped = Enum.map(caps, &Map.get(@capabilities, &1)),
         false <- nil in mapped do
      %{subject: subject, tenant: tenant, capabilities: Enum.uniq(mapped)}
    else
      _ -> fail!("#{name}: invalid binding for #{inspect(subject)}")
    end
  end

  defp binding!(_binding, name),
    do: fail!("#{name}: each binding needs exactly subject, tenant and capabilities ([\"read\"], [\"ingest\"] or both)")

  defp check!(true, _message), do: :ok
  defp check!(_false, message), do: fail!(message)

  defp fail!(message), do: raise(ArgumentError, "PULSE_WORKLOAD_IDENTITY_JSON: " <> message)
end
