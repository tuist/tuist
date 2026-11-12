defmodule Pulse.Auth.IssuerTest do
  use PulseWeb.ConnCase, async: true

  alias Plug.Parsers.ParseError
  alias Pulse.Alerting.Principal
  alias Pulse.Auth
  alias Pulse.Auth.Issuer
  alias Pulse.Auth.IssuerCache
  alias Pulse.Auth.SharedSecret
  alias Pulse.Record.Log
  alias Pulse.Storage
  alias Pulse.Storage.Memory

  @moduletag :capture_log

  @issuer "https://tuist.dev"
  @audience "https://eu.pulse.tuist.dev"
  @raw_config %{
    "issuer" => @issuer,
    "audience" => @audience,
    "jwks_url" => "https://tuist.dev/.well-known/pulse-jwks.json",
    "status_url" => "https://tuist.dev/pulse/status.jwt",
    "mirror" => false
  }

  defmodule MirrorStore do
    @moduledoc false
    # Object store stand-in backed by the Agent named in the config.
    def get(%{agent: agent}, key) do
      case Agent.get(agent, &Map.get(&1, key)) do
        nil -> {:error, :not_found}
        body -> {:ok, body}
      end
    end

    def put(%{agent: agent}, key, body) do
      Agent.update(agent, &Map.put(&1, key, body))
      {:ok, "etag"}
    end

    def list(%{agent: agent}, prefix),
      do: {:ok, agent |> Agent.get(&Map.keys/1) |> Enum.filter(&String.starts_with?(&1, prefix))}

    def delete(%{agent: agent}, key), do: Agent.update(agent, &Map.delete(&1, key))
  end

  setup_all do
    {es_pub, es_priv} = :crypto.generate_key(:ecdh, :secp256r1)
    {ed_pub, ed_priv} = :crypto.generate_key(:eddsa, :ed25519)
    rsa = :public_key.generate_key({:rsa, 2048, 65_537})

    {:ok,
     keys: %{
       es: {:es, "es-1", es_pub, es_priv},
       ed: {:ed, "ed-1", ed_pub, ed_priv},
       rsa: {:rsa, "rsa-1", rsa},
       rotated: {:es, "es-2", es_pub, es_priv}
     }}
  end

  setup do
    Memory.reset()
    Pulse.Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{})
    :ok
  end

  # -- Issuer stand-in -------------------------------------------------------

  defp start_issuer(ctx, overrides \\ %{}, opts \\ []) do
    raw = Map.merge(@raw_config, Map.get(overrides, :config, %{}))
    config = Issuer.parse!(raw)
    Pulse.Runtime.put_env(:pulse, Issuer, config)

    agent =
      start_supervised!(
        {Agent,
         fn ->
           %{
             jwks: jwks(Map.get(overrides, :jwks, [ctx.keys.es, ctx.keys.ed, ctx.keys.rsa])),
             status: Map.get_lazy(overrides, :status, fn -> status(ctx, %{}) end),
             up: Map.get(overrides, :up, true)
           }
         end},
        id: :issuer_agent
      )

    plug = fn conn ->
      state = Agent.get(agent, & &1)

      cond do
        not state.up -> Plug.Conn.send_resp(conn, 503, "down")
        conn.request_path =~ "jwks" -> Plug.Conn.send_resp(conn, 200, state.jwks)
        is_binary(state.status) -> Plug.Conn.send_resp(conn, 200, state.status)
        true -> Plug.Conn.send_resp(conn, 404, "")
      end
    end

    start_supervised!(
      {IssuerCache, Keyword.merge([http_options: [plug: plug], object_store: nil, min_refresh_ms: 0], opts)}
    )

    IssuerCache.refresh()
    {agent, config}
  end

  defp jwks(keys), do: JSON.encode!(%{"keys" => Enum.map(keys, &public_jwk/1)})

  defp public_jwk({:es, kid, <<4, x::binary-size(32), y::binary-size(32)>>, _}),
    do: %{"kty" => "EC", "crv" => "P-256", "kid" => kid, "x" => b64(x), "y" => b64(y), "alg" => "ES256", "use" => "sig"}

  defp public_jwk({:ed, kid, x, _}), do: %{"kty" => "OKP", "crv" => "Ed25519", "kid" => kid, "x" => b64(x)}

  defp public_jwk({:rsa, kid, {:RSAPrivateKey, _, n, e, _, _, _, _, _, _, _}}),
    do: %{"kty" => "RSA", "kid" => kid, "n" => b64(:binary.encode_unsigned(n)), "e" => b64(:binary.encode_unsigned(e))}

  defp b64(bytes), do: Base.url_encode64(bytes, padding: false)

  defp sign(key, typ, claims) do
    {alg, kid} =
      case key do
        {:es, kid, _, _} -> {"ES256", kid}
        {:ed, kid, _, _} -> {"EdDSA", kid}
        {:rsa, kid, _} -> {"RS256", kid}
      end

    input = b64(JSON.encode!(%{"alg" => alg, "kid" => kid, "typ" => typ})) <> "." <> b64(JSON.encode!(claims))
    input <> "." <> b64(signature(key, input))
  end

  defp signature({:es, _, _, priv}, input) do
    der = :crypto.sign(:ecdsa, :sha256, input, [priv, :secp256r1])
    {:"ECDSA-Sig-Value", r, s} = :public_key.der_decode(:"ECDSA-Sig-Value", der)
    pad(r) <> pad(s)
  end

  defp signature({:ed, _, _, priv}, input), do: :crypto.sign(:eddsa, :none, input, [priv, :ed25519])
  defp signature({:rsa, _, key}, input), do: :public_key.sign(input, :sha256, key)

  defp pad(int) do
    bytes = :binary.encode_unsigned(int)
    <<0::size((32 - byte_size(bytes)) * 8), bytes::binary>>
  end

  defp now, do: System.os_time(:second)

  defp claims(overrides) do
    Map.merge(
      %{
        "iss" => @issuer,
        "aud" => @audience,
        "sub" => "user-1",
        "tenant" => "acme",
        "scope" => "ingest read",
        "iat" => now(),
        "exp" => now() + 3600,
        "jti" => "token-1"
      },
      overrides
    )
  end

  defp token(ctx, overrides \\ %{}, key \\ :es), do: sign(ctx.keys[key], "at+jwt", claims(overrides))

  defp ingest_key(ctx, overrides \\ %{}) do
    claims = claims(Map.merge(%{"scope" => "ingest", "exp" => now() + 180 * 86_400, "jti" => "key-1"}, overrides))
    "pulse_ik_" <> sign(ctx.keys.es, "pulse-ik+jwt", claims)
  end

  defp status(ctx, fields) do
    claims =
      Map.merge(
        %{"iss" => @issuer, "aud" => [@audience], "version" => 1, "iat" => now(), "exp" => now() + 86_400},
        fields
      )

    sign(ctx.keys.es, "pulse-status+jwt", claims)
  end

  defp publish_status(agent, jwt) do
    Agent.update(agent, &%{&1 | status: jwt})
    IssuerCache.refresh()
  end

  defp payload do
    %{
      "resourceLogs" => [
        %{
          "resource" => %{"attributes" => [%{"key" => "service.name", "value" => %{"stringValue" => "api"}}]},
          "scopeLogs" => [
            %{
              "logRecords" => [
                %{"timeUnixNano" => "1700000000000000000", "body" => %{"stringValue" => "hello"}}
              ]
            }
          ]
        }
      ]
    }
  end

  defp export(conn, credential, headers \\ []) do
    conn = conn |> put_req_header("content-type", "application/json")
    conn = if credential, do: put_req_header(conn, "authorization", credential), else: conn
    conn = Enum.reduce(headers, conn, fn {k, v}, conn -> put_req_header(conn, k, v) end)
    post(conn, "/v1/logs", payload())
  end

  defp basic(username, password), do: "Basic " <> Base.encode64("#{username}:#{password}")

  defp verify(credential, tenant, capability) do
    build_conn() |> put_req_header("authorization", credential) |> Auth.verify(tenant, capability)
  end

  # -- Ingestion and tenancy --------------------------------------------------

  test "an access token names its tenant: OTLP ingest without X-Scope-OrgID lands in the claimed tenant", ctx do
    start_issuer(ctx)

    assert json_response(export(ctx.conn, "Bearer " <> token(ctx)), 200) == %{}
    assert {:ok, [%Log{body: "hello"}]} = Storage.query(:logs, "acme")
    assert {:ok, []} = Storage.query(:logs, "default")
  end

  test "tenant, scope and Basic username must all match the credential", ctx do
    start_issuer(ctx)
    read_only = token(ctx, %{"scope" => "read"})

    assert export(ctx.conn, "Bearer " <> token(ctx), [{"x-scope-orgid", "other"}]).status == 403
    assert export(ctx.conn, "Bearer " <> read_only).status == 403
    assert verify("Bearer " <> read_only, "acme", :read) == :ok

    # Basic carries the token as password for clients without bearer support.
    assert json_response(export(ctx.conn, basic("acme", token(ctx))), 200) == %{}
    assert export(ctx.conn, basic("other", token(ctx))).status == 401
  end

  test "ES256, EdDSA and RS256 issuer keys verify; tampered, foreign or mistyped tokens do not", ctx do
    start_issuer(ctx)

    for key <- [:es, :ed, :rsa], do: assert(verify("Bearer " <> token(ctx, %{}, key), "acme", :ingest) == :ok)

    [h, p, s] = String.split(token(ctx), ".")
    forged = b64(JSON.encode!(claims(%{"tenant" => "other"})))
    assert verify("Bearer " <> Enum.join([h, forged, s], "."), "other", :ingest) == {:error, :invalid_token}
    assert verify("Bearer " <> Enum.join([h, p, s], "."), "acme", :ingest) == :ok

    for overrides <- [%{"iss" => "https://evil.example"}, %{"aud" => "https://us.pulse.tuist.dev"}, %{"sub" => "a b"}] do
      assert verify("Bearer " <> token(ctx, overrides), "acme", :ingest) == {:error, :invalid_token}
    end

    # Typed JWS cannot cross roles: a status list or bare ingest-key JWS is not
    # an access token, and an access token is not an ingest key.
    for typ <- ["pulse-status+jwt", "pulse-ik+jwt", "JWT"] do
      refute verify("Bearer " <> sign(ctx.keys.es, typ, claims(%{})), "acme", :ingest) == :ok
    end

    assert verify("Bearer pulse_ik_" <> sign(ctx.keys.es, "at+jwt", claims(%{"scope" => "ingest"})), "acme", :ingest) ==
             {:error, :invalid_token}
  end

  test "ingest keys are long-lived, ingest-only and revocable by jti", ctx do
    {agent, _config} = start_issuer(ctx)
    key = ingest_key(ctx)

    assert verify("Bearer " <> key, "acme", :ingest) == :ok
    assert verify("Bearer " <> key, "acme", :read) == {:error, :forbidden}

    assert verify("Bearer " <> ingest_key(ctx, %{"scope" => "ingest read"}), "acme", :ingest) ==
             {:error, :invalid_token}

    # A one-year access token exceeds the access lifetime ceiling.
    assert verify("Bearer " <> token(ctx, %{"exp" => now() + 180 * 86_400}), "acme", :ingest) ==
             {:error, :invalid_token}

    publish_status(agent, status(ctx, %{"version" => 2, "revoked_credentials" => ["key-1"]}))
    assert verify("Bearer " <> key, "acme", :ingest) == {:error, :invalid_token}
    assert verify("Bearer " <> ingest_key(ctx, %{"jti" => "key-2"}), "acme", :ingest) == :ok
  end

  test "recently expired ingest tokens are retryable; reads and older tokens are not", ctx do
    start_issuer(ctx)
    expired = token(ctx, %{"iat" => now() - 1800, "exp" => now() - 600})
    long_expired = token(ctx, %{"iat" => now() - 9000, "exp" => now() - 7200})

    response = export(ctx.conn, "Bearer " <> expired)
    assert response.status == 503
    assert get_resp_header(response, "retry-after") == ["1"]
    assert {:ok, []} = Storage.query(:logs, "acme")

    assert verify("Bearer " <> expired, "acme", :read) == {:error, :invalid_token}
    assert export(ctx.conn, "Bearer " <> long_expired).status == 401
  end

  test "OTLP exports are rejected before the JSON body is parsed", ctx do
    start_issuer(ctx)

    malformed = fn credential ->
      conn = ctx.conn |> put_req_header("content-type", "application/json")
      conn = if credential, do: put_req_header(conn, "authorization", credential), else: conn
      post(conn, "/v1/logs", "{not json")
    end

    assert malformed.(nil).status == 401
    assert malformed.("Bearer " <> token(ctx, %{"tenant" => "acme", "scope" => "read"})).status == 403
    # Authenticated callers reach the parser and get its error.
    assert_raise ParseError, fn -> malformed.("Bearer " <> token(ctx)) end
  end

  # -- Status list -------------------------------------------------------------

  test "the status list suspends tenants, revokes by issue time and by key, and never goes backwards", ctx do
    {agent, _config} = start_issuer(ctx)
    old = token(ctx, %{"iat" => now() - 120})

    publish_status(agent, status(ctx, %{"version" => 5, "suspended_tenants" => ["acme"]}))
    assert verify("Bearer " <> old, "acme", :ingest) == {:error, :forbidden}
    refute Issuer.suspended?("other")
    assert Issuer.suspended?("acme")

    # A replayed older document cannot lift the suspension.
    publish_status(agent, status(ctx, %{"version" => 4}))
    assert verify("Bearer " <> old, "acme", :ingest) == {:error, :forbidden}

    publish_status(agent, status(ctx, %{"version" => 6, "revoked_before" => %{"acme" => now() - 60}}))
    assert verify("Bearer " <> old, "acme", :ingest) == {:error, :invalid_token}
    assert verify("Bearer " <> token(ctx), "acme", :ingest) == :ok

    # Revocations apply to credentials already verified and cached.
    ed = token(ctx, %{}, :ed)
    assert verify("Bearer " <> ed, "acme", :ingest) == :ok
    publish_status(agent, status(ctx, %{"version" => 7, "revoked_kids" => ["ed-1"]}))
    assert verify("Bearer " <> ed, "acme", :ingest) == {:error, :invalid_token}
    assert verify("Bearer " <> token(ctx), "acme", :ingest) == :ok
  end

  test "cached verifications still need the signing key and the credential's own type", ctx do
    {agent, _config} = start_issuer(ctx)
    rsa = token(ctx, %{}, :rsa)
    assert verify("Bearer " <> rsa, "acme", :ingest) == :ok

    # A key dropped from the JWKS stops verifying tokens it signed earlier.
    Agent.update(agent, &%{&1 | jwks: jwks([ctx.keys.es])})
    IssuerCache.refresh()
    assert verify("Bearer " <> rsa, "acme", :ingest) == {:error, :invalid_token}

    # A cached ingest key's JWT is not an access token on its own, even with an
    # access-token lifetime.
    "pulse_ik_" <> jwt = key = ingest_key(ctx, %{"exp" => now() + 3600})
    assert verify("Bearer " <> key, "acme", :ingest) == :ok
    assert Issuer.authenticate(jwt) == {:error, :invalid_token}
  end

  test "a configured status list that never loaded fails closed as retryable", ctx do
    start_issuer(ctx, %{status: nil})
    assert IssuerCache.material() == :unavailable
    assert verify("Bearer " <> token(ctx), "acme", :ingest) == {:error, :auth_unavailable}
  end

  test "keys rotated in after start verify through one on-demand refresh", ctx do
    {agent, _config} = start_issuer(ctx, %{jwks: [ctx.keys.es]})
    rotated = sign(ctx.keys.rotated, "at+jwt", claims(%{}))

    Agent.update(agent, &%{&1 | jwks: jwks([ctx.keys.es, ctx.keys.rotated])})
    assert verify("Bearer " <> rotated, "acme", :ingest) == :ok
  end

  test "an instance that cannot reach the issuer loads keys and status from the object-store mirror", ctx do
    mirror = start_supervised!({Agent, fn -> %{} end}, id: :mirror)
    store = [object_store: MirrorStore, store_config: %{agent: mirror}]

    # A healthy instance writes the mirror.
    {issuer, _} = start_issuer(ctx, %{config: %{"mirror" => true}}, store)
    assert %{"auth/issuer/jwks.json" => _, "auth/issuer/status.jwt" => _} = Agent.get(mirror, & &1)
    stop_supervised!(IssuerCache)

    # A fresh instance during an issuer outage still verifies tokens.
    Agent.update(issuer, &%{&1 | up: false})
    start_supervised!({IssuerCache, [http_options: [plug: fn conn -> Plug.Conn.send_resp(conn, 503, "") end]] ++ store})
    IssuerCache.refresh()
    assert verify("Bearer " <> token(ctx), "acme", :ingest) == :ok
  end

  test "status quotas divide ingest bytes per window and answer 429", ctx do
    start_issuer(ctx, %{status: status(ctx, %{"quotas" => %{"acme" => %{"ingest_bytes_per_second" => 30}}})})

    first = export(ctx.conn, "Bearer " <> token(ctx), [{"content-length", "200"}])
    assert first.status == 200
    second = export(ctx.conn, "Bearer " <> token(ctx), [{"content-length", "200"}])
    assert second.status == 429
    assert get_resp_header(second, "retry-after") == ["10"]
  end

  test "unclustered instances divide quotas through object-store heartbeats", ctx do
    gone = "auth/members/gone/#{now() - 86_400}"
    store = start_supervised!({Agent, fn -> %{"auth/members/peer/#{now()}" => "", gone => ""} end}, id: :store)
    quota = status(ctx, %{"quotas" => %{"acme" => %{"ingest_bytes_per_second" => 30}}})
    start_issuer(ctx, %{status: quota}, object_store: MirrorStore, store_config: %{agent: store})

    # This instance plus one live peer: each admits 30 × 10 ÷ 2 = 150 bytes per window.
    assert IssuerCache.members() == 2
    keys = Agent.get(store, &Map.keys/1)
    refute gone in keys
    assert Enum.count(keys, &String.starts_with?(&1, "auth/members/")) == 2

    assert export(ctx.conn, "Bearer " <> token(ctx), [{"content-length", "100"}]).status == 200
    assert export(ctx.conn, "Bearer " <> token(ctx), [{"content-length", "100"}]).status == 429
  end

  test "instances write no heartbeats while the status list publishes no quotas", ctx do
    store = start_supervised!({Agent, fn -> %{} end}, id: :store)
    start_issuer(ctx, %{}, object_store: MirrorStore, store_config: %{agent: store})

    assert IssuerCache.members() == 1
    refute Enum.any?(Agent.get(store, &Map.keys/1), &String.starts_with?(&1, "auth/members/"))
  end

  # -- MCP, alerting, Sentry -------------------------------------------------

  test "hosted MCP challenges unauthenticated calls with protected-resource metadata", ctx do
    start_issuer(ctx)

    mcp = fn credential ->
      conn =
        ctx.conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("mcp-protocol-version", "2026-07-28")

      conn = if credential, do: put_req_header(conn, "authorization", credential), else: conn
      post(conn, "/mcp", JSON.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}))
    end

    response = mcp.(nil)
    assert response.status == 401
    assert [challenge] = get_resp_header(response, "www-authenticate")
    assert challenge =~ ~s(resource_metadata="#{@audience}/.well-known/oauth-protected-resource/mcp")

    assert mcp.("Bearer " <> token(ctx, %{"scope" => "ingest"})).status == 403
    [h, p, _signature] = String.split(token(ctx), ".")
    invalid = mcp.("Bearer #{h}.#{p}.#{b64("forged")}")
    assert invalid.status == 401
    assert [challenge] = get_resp_header(invalid, "www-authenticate")
    assert challenge =~ ~s(error="invalid_token")
    assert mcp.("Bearer " <> token(ctx, %{"aud" => @audience <> "/mcp"})).status != 401

    metadata = json_response(get(build_conn(), "/.well-known/oauth-protected-resource/mcp"), 200)
    assert metadata["resource"] == @audience <> "/mcp"
    assert metadata["authorization_servers"] == [@issuer]
  end

  test "delegated tokens become alerting principals with their alert scopes and actor", ctx do
    start_issuer(ctx)

    conn =
      put_req_header(
        build_conn(),
        "authorization",
        "Bearer " <> token(ctx, %{"scope" => "read alert:read alert:rules:write", "act" => %{"sub" => "atlas"}})
      )

    assert {:ok, %{tenant: "acme", id: "user-1.via.atlas", type: "agent", capabilities: caps}} =
             Principal.authenticate(conn, "acme")

    assert Enum.sort(caps) == ["alert:read", "alert:rules:write"]
    assert Principal.authenticate(conn, "other") == {:error, :unauthorized}
  end

  test "Sentry projects published in the status list ingest; bad header keys fail before the body is read", ctx do
    key = "public-key"
    digest = Base.encode16(:crypto.hash(:sha256, key), case: :lower)
    project = %{"tenant" => "acme", "service" => "ios", "public_key_hashes" => [digest]}
    start_issuer(ctx, %{status: status(ctx, %{"sentry_projects" => %{"42" => project}})})

    event = JSON.encode!(%{"event_id" => String.duplicate("a", 32), "message" => "boom", "level" => "error"})

    stored =
      ctx.conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-sentry-auth", "Sentry sentry_key=#{key}, sentry_version=7")
      |> post("/api/42/store", event)

    assert stored.status == 200
    assert {:ok, [_]} = Storage.query(:logs, "acme")

    # An unsupported encoding would be a 415 if the body were read first.
    rejected =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("content-encoding", "br")
      |> put_req_header("x-sentry-auth", "Sentry sentry_key=wrong, sentry_version=7")
      |> post("/api/42/store", event)

    assert rejected.status == 403
  end
end
