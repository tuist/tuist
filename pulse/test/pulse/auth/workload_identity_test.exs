defmodule Pulse.Auth.WorkloadIdentityTest do
  use PulseWeb.ConnCase, async: true

  import ExUnit.CaptureLog

  alias Pulse.Auth
  alias Pulse.Auth.JWKS
  alias Pulse.Auth.SharedSecret
  alias Pulse.Auth.WorkloadIdentity
  alias Pulse.Record.Log
  alias Pulse.Storage
  alias Pulse.Storage.Memory
  alias Pulse.Test.JWKSServer

  @moduletag :capture_log

  @issuer "https://kubernetes.default.svc.cluster.local"
  @subject "system:serviceaccount:atlas-production:atlas"
  @kid "atlas-key"

  setup_all do
    # Two clusters sharing kubeadm's default issuer: only the pinned key differs.
    # The TLS chain is for the JWKS URL tests' local HTTPS issuer.
    san = {:Extension, {2, 5, 29, 17}, false, [dNSName: ~c"localhost"]}
    rsa = [key: {:rsa, 2048, 65_537}]

    tls =
      :public_key.pkix_test_data(%{
        server_chain: %{root: rsa, intermediates: [], peer: rsa ++ [extensions: [san]]},
        client_chain: %{root: rsa, intermediates: [], peer: rsa}
      })

    {:ok,
     trusted: :public_key.generate_key({:rsa, 2048, 65_537}),
     other: :public_key.generate_key({:rsa, 2048, 65_537}),
     tls: tls}
  end

  setup %{trusted: trusted} do
    Memory.reset()
    trust = WorkloadIdentity.parse!([entry(trusted)])
    Pulse.Runtime.put_env(:pulse, WorkloadIdentity, trust: trust)

    digest = Base.encode16(:crypto.hash(:sha256, "shared-token"), case: :lower)
    Pulse.Runtime.put_env(:pulse, Auth, module: SharedSecret, tokens: %{"tuist" => "sha256$" <> digest})
    {:ok, trust: trust}
  end

  defp entry(key, bindings \\ [%{"subject" => @subject, "tenant" => "tuist", "capabilities" => ["read"]}]) do
    %{
      "name" => "atlas-production",
      "issuer" => @issuer,
      "audiences" => ["pulse.tuist.dev"],
      "max_token_ttl_seconds" => 3600,
      "keys" => %{"type" => "inline", "jwks" => %{"keys" => [jwk(key, @kid)]}},
      "bindings" => bindings
    }
  end

  defp jwk({:RSAPrivateKey, _, n, e, _, _, _, _, _, _, _}, kid) do
    encode = &Base.url_encode64(:binary.encode_unsigned(&1), padding: false)
    %{"kty" => "RSA", "kid" => kid, "alg" => "RS256", "use" => "sig", "n" => encode.(n), "e" => encode.(e)}
  end

  defp now, do: System.os_time(:second)

  defp claims(overrides \\ %{}) do
    iat = now()

    Map.merge(
      %{
        "iss" => @issuer,
        "aud" => ["pulse.tuist.dev"],
        "sub" => @subject,
        "iat" => iat,
        "nbf" => iat,
        "exp" => iat + 3600,
        "kubernetes.io" => %{
          "namespace" => "atlas-production",
          "serviceaccount" => %{"name" => "atlas", "uid" => "c0ffee"},
          "pod" => %{"name" => "atlas-0", "uid" => "f00d"}
        }
      },
      overrides
    )
  end

  defp sign(key, claims, header \\ %{"alg" => "RS256", "kid" => @kid}) do
    input = b64(JSON.encode!(header)) <> "." <> b64(JSON.encode!(claims))
    input <> "." <> b64(:public_key.sign(input, :sha256, key))
  end

  defp b64(data), do: Base.url_encode64(data, padding: false)

  defp conn_with(token, tenant \\ "tuist") do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("x-scope-orgid", tenant)
  end

  defp reason(token, trust, at \\ now()) do
    {:error, {reason, _trust}} = WorkloadIdentity.authenticate(token, trust, at)
    reason
  end

  test "a valid token reads its bound tenant only", %{trusted: key} do
    token = sign(key, claims())
    assert Auth.verify(conn_with(token), "tuist", :read) == :ok
    assert Auth.verify(conn_with(token), "other", :read) == {:error, :forbidden}
  end

  test "a read-only principal is refused on ingest, over the API too", %{trusted: key} do
    token = sign(key, claims())
    assert Auth.verify(conn_with(token), "tuist", :ingest) == {:error, :forbidden}

    conn =
      token
      |> conn_with()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/loki/api/v1/push", %{
        "streams" => [%{"stream" => %{"service" => "api"}, "values" => [["1700000000000000000", "hi"]]}]
      })

    assert json_response(conn, 403) == %{"error" => "forbidden"}
    assert {:ok, []} = Storage.query(:logs, "tuist")
  end

  test "shared-secret tokens keep granting both capabilities alongside JWT principals" do
    conn =
      "shared-token"
      |> conn_with()
      |> put_req_header("content-type", "application/json")
      |> post(~p"/loki/api/v1/push", %{
        "streams" => [%{"stream" => %{"service" => "api"}, "values" => [["1700000000000000000", "hi"]]}]
      })

    assert conn.status == 204
    assert {:ok, [%Log{body: "hi"}]} = Storage.query(:logs, "tuist")
    assert Auth.verify(conn_with("shared-token"), "tuist", :read) == :ok
    assert Auth.verify(conn_with("wrong"), "tuist", :read) == {:error, :invalid_token}
  end

  test "ingest bindings authorize ingest", %{trusted: key} do
    binding = %{"subject" => @subject, "tenant" => "tuist", "capabilities" => ["ingest"]}
    trust = WorkloadIdentity.parse!([entry(key, [binding])])
    token = sign(key, claims())
    assert WorkloadIdentity.verify(token, "tuist", :ingest, trust) == :ok
    assert WorkloadIdentity.verify(token, "tuist", :read, trust) == {:error, :forbidden}
  end

  test "the pinned key, not the shared issuer, selects the trust entry", %{trusted: a, other: b} do
    bind = fn tenant -> [%{"subject" => @subject, "tenant" => tenant, "capabilities" => ["read"]}] end
    entry_b = put_in(entry(b, bind.("b")), ["keys", "jwks", "keys"], [jwk(b, "other-key")])
    trust = WorkloadIdentity.parse!([entry(a, bind.("a")), Map.put(entry_b, "name", "other-cluster")])
    token_a = sign(a, claims())
    token_b = sign(b, claims(), %{"alg" => "RS256", "kid" => "other-key"})

    assert WorkloadIdentity.verify(token_a, "a", :read, trust) == :ok
    assert WorkloadIdentity.verify(token_a, "b", :read, trust) == {:error, :forbidden}
    assert WorkloadIdentity.verify(token_b, "b", :read, trust) == :ok
    assert WorkloadIdentity.verify(token_b, "a", :read, trust) == {:error, :forbidden}
    # Key B signing under entry A's kid does not borrow entry A's bindings.
    assert reason(sign(b, claims()), trust) == :invalid_signature
  end

  test "read paths answer 403 for an authenticated principal without a read binding", %{trusted: key} do
    binding = %{"subject" => @subject, "tenant" => "tuist", "capabilities" => ["ingest"]}
    Pulse.Runtime.put_env(:pulse, WorkloadIdentity, trust: WorkloadIdentity.parse!([entry(key, [binding])]))
    token = sign(key, claims())

    for path <- ["/api/v1/query?query=1", "/api/v1/labels", "/loki/api/v1/labels"] do
      assert token |> conn_with() |> get(path) |> Map.fetch!(:status) == 403, path
    end

    assert "wrong" |> conn_with() |> get("/api/v1/query?query=1") |> Map.fetch!(:status) == 401
  end

  test "wrong audience and issuer are rejected", %{trusted: key, trust: trust} do
    token = sign(key, claims(%{"aud" => ["https://kubernetes.default.svc"]}))
    assert Auth.verify(conn_with(token), "tuist", :read) == {:error, :invalid_token}
    assert reason(token, trust) == :bad_audience
    assert reason(sign(key, claims(%{"aud" => "pulse.tuist.dev.evil"})), trust) == :bad_audience
    assert reason(sign(key, claims(%{"iss" => "https://other"})), trust) == :bad_issuer
  end

  test "expiry, not-before and lifetime are enforced with 60 s of skew", %{trusted: key, trust: trust} do
    token = sign(key, claims())
    exp = now() + 3600

    assert {:ok, _} = WorkloadIdentity.authenticate(token, trust, exp + 59)
    assert reason(token, trust, exp + 60) == :token_expired
    assert Auth.verify(conn_with(sign(key, claims(%{"exp" => now() - 61}))), "tuist", :read) == {:error, :invalid_token}

    assert reason(sign(key, claims(%{"nbf" => now() + 120})), trust) == :token_not_yet_valid
    assert reason(sign(key, claims(%{"iat" => now() + 120, "exp" => now() + 600})), trust) == :token_not_yet_valid
    assert reason(sign(key, claims(%{"exp" => now() + 3601})), trust) == :token_ttl_exceeded
    assert reason(sign(key, Map.delete(claims(), "exp")), trust) == :bad_time_claims
    assert reason(sign(key, claims(%{"exp" => (now() + 60) * 1.0})), trust) == :bad_time_claims
  end

  test "a key from another cluster with the same issuer string is rejected", %{other: other, trust: trust} do
    # Same issuer, audience, subject and even kid: only the signing key differs.
    forged = sign(other, claims())
    assert Auth.verify(conn_with(forged), "tuist", :read) == {:error, :invalid_token}
    assert reason(forged, trust) == :invalid_signature

    assert reason(sign(other, claims(), %{"alg" => "RS256", "kid" => "other-cluster"}), trust) == :unknown_kid
    assert reason(sign(other, claims(), %{"alg" => "RS256"}), trust) == :missing_kid
  end

  test "tampered payloads and non-RS256 algorithms are rejected", %{trusted: key, trust: trust} do
    [h, _p, s] = String.split(sign(key, claims()), ".")

    tampered =
      Enum.join([h, b64(JSON.encode!(claims(%{"sub" => "system:serviceaccount:atlas-production:admin"}))), s], ".")

    assert reason(tampered, trust) == :invalid_signature

    payload = b64(JSON.encode!(claims()))

    for alg <- ["none", "HS256", "RS512", "ES256", "PS256"] do
      header = b64(JSON.encode!(%{"alg" => alg, "kid" => @kid}))
      token = header <> "." <> payload <> "." <> b64("sig")
      assert reason(token, trust) == :unsupported_algorithm
      assert Auth.verify(conn_with(token), "tuist", :read) == {:error, :invalid_token}
    end

    assert reason(sign(key, claims(), %{"alg" => "RS256", "kid" => @kid, "crit" => ["exp"]}), trust) ==
             :unsupported_header
  end

  test "unknown subjects and inconsistent ServiceAccount claims are rejected", %{trusted: key, trust: trust} do
    other = "system:serviceaccount:atlas-production:worker"

    token =
      sign(
        key,
        claims(%{
          "sub" => other,
          "kubernetes.io" => %{"namespace" => "atlas-production", "serviceaccount" => %{"name" => "worker"}}
        })
      )

    assert reason(token, trust) == :unknown_subject
    assert Auth.verify(conn_with(token), "tuist", :read) == {:error, :invalid_token}

    assert reason(sign(key, claims(%{"sub" => "atlas"})), trust) == :not_service_account
    assert reason(sign(key, claims(%{"sub" => "system:serviceaccount:a:b:c"})), trust) == :not_service_account

    assert reason(
             sign(key, claims(%{"kubernetes.io" => %{"namespace" => "x", "serviceaccount" => %{"name" => "atlas"}}})),
             trust
           ) ==
             :bad_kubernetes_claims
  end

  test "rejections never log the token", %{other: other} do
    forged = sign(other, claims())
    log = capture_log(fn -> Auth.verify(conn_with(forged), "tuist", :read) end)
    assert log =~ "invalid_signature"
    refute log =~ forged
    refute log =~ hd(String.split(forged, "."))
  end

  test "without trust configuration JWT-shaped bearers go to the shared secret", %{trusted: key} do
    Pulse.Runtime.put_env(:pulse, WorkloadIdentity, trust: [])
    assert Auth.verify(conn_with(sign(key, claims())), "tuist", :read) == {:error, :invalid_token}
  end

  test "configuration fails closed at boot", %{trusted: key} do
    valid = entry(key)
    jwk = jwk(key, @kid)
    with_keys = fn keys -> put_in(valid, ["keys", "jwks", "keys"], keys) end
    {:RSAPrivateKey, _, _n, _e, d, _, _, _, _, _, _} = key
    {:RSAPrivateKey, _, small_n, _, _, _, _, _, _, _, _} = :public_key.generate_key({:rsa, 1024, 65_537})

    invalid = [
      Map.delete(valid, "audiences"),
      Map.put(valid, "audiences", []),
      Map.put(valid, "unexpected", true),
      Map.put(valid, "max_token_ttl_seconds", 31_536_000),
      Map.put(valid, "bindings", []),
      Map.put(valid, "bindings", [%{"subject" => @subject, "tenant" => "tuist", "capabilities" => ["admin"]}]),
      Map.put(valid, "bindings", [%{"subject" => "atlas", "tenant" => "tuist", "capabilities" => ["read"]}]),
      with_keys.([Map.put(jwk, "d", Base.url_encode64(:binary.encode_unsigned(d), padding: false))]),
      with_keys.([Map.put(jwk, "alg", "HS256")]),
      # e = 1 would make every signature trivially forgeable.
      with_keys.([Map.put(jwk, "e", "AQ")]),
      with_keys.([Map.put(jwk, "n", Base.url_encode64(:binary.encode_unsigned(small_n), padding: false))]),
      with_keys.([jwk, jwk])
    ]

    for config <- invalid do
      assert_raise ArgumentError, ~r/PULSE_WORKLOAD_IDENTITY_JSON/, fn -> WorkloadIdentity.parse!([config]) end
    end

    assert_raise ArgumentError, ~r/unique/, fn -> WorkloadIdentity.parse!([valid, Map.put(valid, "name", "b")]) end

    assert [%{max_token_ttl_seconds: 3600, keys: [%{size: 256}]}] =
             WorkloadIdentity.parse!([Map.delete(valid, "max_token_ttl_seconds")])

    # The JWKS can be pasted verbatim from /openid/v1/jwks as a JSON string.
    as_string = put_in(valid, ["keys", "jwks"], JSON.encode!(%{"keys" => [jwk]}))
    assert [%{keys: [%{kid: @kid}]} = parsed] = WorkloadIdentity.parse!([as_string])
    assert WorkloadIdentity.verify(sign(key, claims()), "tuist", :read, [parsed]) == :ok
    assert_raise ArgumentError, fn -> WorkloadIdentity.parse!([put_in(valid, ["keys", "jwks"], "{")]) end

    # YAML reads a bare `n` key as false.
    yaml_n = jwk |> Map.delete("n") |> Map.put("false", jwk["n"])
    assert_raise ArgumentError, ~r/quote "n"/, fn -> WorkloadIdentity.parse!([with_keys.([yaml_n])]) end
  end

  test "runtime.exs reads PULSE_WORKLOAD_IDENTITY_JSON", %{trusted: key} do
    path = Path.expand("../../../config/runtime.exs", __DIR__)
    Pulse.Runtime.put_env("PULSE_WORKLOAD_IDENTITY_JSON", JSON.encode!([entry(key)]))
    config = Config.Reader.read!(path, env: :test, target: :host)
    assert [%{name: "atlas-production", issuer: @issuer}] = config[:pulse][WorkloadIdentity][:trust]

    Pulse.Runtime.put_env("PULSE_WORKLOAD_IDENTITY_JSON", "{")
    assert_raise RuntimeError, fn -> Config.Reader.read!(path, env: :test, target: :host) end
  end

  describe "JWKS URL key source" do
    @describetag :tmp_dir
    @alloy "system:serviceaccount:monitoring:alloy"

    # An HTTPS "API server" with its own CA, plus an unrelated CA and a pod token.
    setup %{tmp_dir: dir, tls: %{server_config: server, client_config: client}} do
      pem = fn name, entries -> Path.join(dir, name) |> tap(&File.write!(&1, :public_key.pem_encode(entries))) end
      {key_type, key_der} = server[:key]
      certfile = pem.("server.pem", [{:Certificate, server[:cert], :not_encrypted}])
      keyfile = pem.("server-key.pem", [{key_type, key_der, :not_encrypted}])
      ca = pem.("ca.pem", for(der <- client[:cacerts], do: {:Certificate, der, :not_encrypted}))
      # Each config's cacerts also lists the server root; keep only the unrelated CA.
      other_ca =
        pem.("other-ca.pem", for(der <- server[:cacerts] -- client[:cacerts], do: {:Certificate, der, :not_encrypted}))

      token_file = Path.join(dir, "token") |> tap(&File.write!(&1, "pod-token\n"))

      agent = start_supervised!({Agent, fn -> %{status: 200, body: "{}", requests: []} end})

      server =
        start_supervised!(
          {Bandit,
           plug: {JWKSServer, agent: agent},
           scheme: :https,
           certfile: certfile,
           keyfile: keyfile,
           ip: {127, 0, 0, 1},
           port: 0}
        )

      {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

      {:ok,
       agent: agent, url: "https://localhost:#{port}/openid/v1/jwks", ca: ca, other_ca: other_ca, token_file: token_file}
    end

    defp url_entry(ctx, overrides \\ %{}) do
      source =
        Map.merge(%{"type" => "url", "url" => ctx.url, "ca_file" => ctx.ca, "token_file" => ctx.token_file}, overrides)

      bindings = [%{"subject" => @alloy, "tenant" => "tuist", "capabilities" => ["ingest"]}]
      Map.merge(entry(ctx.trusted, bindings), %{"name" => "local-cluster", "keys" => source})
    end

    defp serve(agent, keys), do: Agent.update(agent, &%{&1 | body: JSON.encode!(%{"keys" => keys})})
    defp requests(agent), do: Agent.get(agent, &length(&1.requests))

    defp alloy_claims do
      claims(%{
        "sub" => @alloy,
        "kubernetes.io" => %{"namespace" => "monitoring", "serviceaccount" => %{"name" => "alloy"}}
      })
    end

    # Returns once the initial scheduled fetch has completed.
    defp start_cache(trust, opts \\ []) do
      Pulse.Runtime.put_env(:pulse, WorkloadIdentity, trust: trust)
      pid = start_supervised!({JWKS, Keyword.put(opts, :trust, trust)})
      _ = :sys.get_state(pid)
      pid
    end

    test "fetches keys over TLS with the CA bundle and pod token", %{agent: agent, trusted: key} = ctx do
      # Non-RSA keys the cluster also publishes are skipped, not fatal.
      serve(agent, [%{"kty" => "EC", "kid" => "ec", "crv" => "P-256", "x" => "AA", "y" => "AA"}, jwk(key, @kid)])
      start_cache(WorkloadIdentity.parse!([url_entry(ctx)]))
      token = sign(key, alloy_claims())

      assert Auth.verify(conn_with(token), "tuist", :ingest) == :ok
      assert Auth.verify(conn_with(token), "tuist", :read) == {:error, :forbidden}
      assert Agent.get(agent, & &1.requests) |> Enum.uniq() == [["Bearer pod-token"]]
    end

    test "a server outside the configured CA is never trusted", %{agent: agent, trusted: key} = ctx do
      serve(agent, [jwk(key, @kid)])

      log =
        capture_log(fn ->
          start_cache(WorkloadIdentity.parse!([url_entry(ctx, %{"ca_file" => ctx.other_ca})]))
          assert Auth.verify(conn_with(sign(key, alloy_claims())), "tuist", :ingest) == {:error, :auth_unavailable}
        end)

      assert log =~ "JWKS refresh failed for trust local-cluster"
      refute log =~ "pod-token"
      assert requests(agent) == 0
    end

    test "unavailable keys answer 503, and so do issuer errors", %{agent: agent, trusted: key} = ctx do
      trust = WorkloadIdentity.parse!([url_entry(ctx)])
      Pulse.Runtime.put_env(:pulse, WorkloadIdentity, trust: trust)
      token = sign(key, alloy_claims())

      # No cache process at all.
      assert Auth.verify(conn_with(token), "tuist", :ingest) == {:error, :auth_unavailable}

      Agent.update(agent, &%{&1 | status: 403, body: ~s({"kind":"Status"})})
      start_cache(trust)

      conn =
        token
        |> conn_with()
        |> put_req_header("content-type", "application/json")
        |> post(~p"/loki/api/v1/push", %{"streams" => []})

      assert json_response(conn, 503) == %{"error" => "auth_unavailable"}
    end

    test "an unknown kid picks up rotated keys, rate-limited per source", %{agent: agent, trusted: a, other: b} = ctx do
      serve(agent, [jwk(a, @kid)])
      start_cache(WorkloadIdentity.parse!([url_entry(ctx)]), min_refresh_ms: 0)
      rotated = sign(b, alloy_claims(), %{"alg" => "RS256", "kid" => "rotated"})

      assert Auth.verify(conn_with(sign(a, alloy_claims())), "tuist", :ingest) == :ok
      assert requests(agent) == 1

      serve(agent, [jwk(a, @kid), jwk(b, "rotated")])
      assert Auth.verify(conn_with(rotated), "tuist", :ingest) == :ok
      assert requests(agent) == 2

      stop_supervised!(JWKS)
      serve(agent, [jwk(a, @kid)])
      start_cache(WorkloadIdentity.parse!([url_entry(ctx)]))
      before = requests(agent)

      for kid <- ~w(x1 x2 x3 x4 x5) do
        forged = sign(b, alloy_claims(), %{"alg" => "RS256", "kid" => kid})
        assert Auth.verify(conn_with(forged), "tuist", :ingest) == {:error, :invalid_token}
      end

      assert requests(agent) == before
    end

    test "a fetched key that is also pinned inline is ambiguous", %{agent: agent, trusted: key} = ctx do
      serve(agent, [jwk(key, @kid)])
      inline = Map.put(entry(key), "name", "inline")
      trust = WorkloadIdentity.parse!([inline, url_entry(ctx)])
      start_cache(trust)

      assert {:error, {:ambiguous_key, nil}} = WorkloadIdentity.authenticate(sign(key, claims()), trust, now())
    end

    test "URL sources are validated at boot", ctx do
      for overrides <- [
            %{"url" => "http://kubernetes.default.svc/openid/v1/jwks"},
            %{"url" => "not a url"},
            %{"ca_file" => Path.join(ctx.tmp_dir, "missing.crt")},
            %{"token_file" => Path.join(ctx.tmp_dir, "missing")},
            %{"refresh_interval_seconds" => 5},
            %{"headers" => %{}}
          ] do
        assert_raise ArgumentError, ~r/PULSE_WORKLOAD_IDENTITY_JSON/, fn ->
          WorkloadIdentity.parse!([url_entry(ctx, overrides)])
        end
      end

      assert [%{keys: [], jwks_url: %{refresh_interval_seconds: 300, token_file: token}}] =
               WorkloadIdentity.parse!([url_entry(ctx)])

      assert token == ctx.token_file
    end
  end
end
