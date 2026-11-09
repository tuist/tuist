defmodule PulseWeb.TenantLifecycleTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Auth.SharedSecret
  alias Pulse.OTLP.Traces
  alias Pulse.Runtime
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Tenants
  alias Pulse.Tenants.Purger
  alias Pulse.Test.CompactionStore
  alias Pulse.Test.OTLPTraceFixture, as: Fixture

  @admin "admin-token"

  setup do
    agent =
      start_supervised!(
        {Agent,
         fn ->
           %{
             objects: %{},
             reads: [],
             version: 0,
             hook: nil,
             faults: %{},
             barriers: %{},
             lists: 0,
             deletes: [],
             requests: []
           }
         end}
      )

    server =
      start_supervised!(
        {Bandit,
         plug: {CompactionStore, agent: agent},
         ip: {127, 0, 0, 1},
         port: 0,
         thousand_island_options: [shutdown_timeout: 100]}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(server)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{port}",
      region: "us-east-1",
      access_key_id: "test-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    Runtime.put_env(:pulse, S3, config)
    Runtime.put_env(:pulse, Pulse.Storage, adapter: S3)
    Runtime.put_env(:pulse, Pulse.Auth, module: SharedSecret, tokens: %{"static" => digest("static-token")})
    Runtime.put_env(:pulse, PulseWeb.AdminController, token_hashes: [digest(@admin)])

    Runtime.put_env(:pulse, Tenants,
      enabled: true,
      cache_ttl_ms: 60_000,
      deletion_grace_ms: 3_600_000,
      purge_interval_ms: 3_600_000,
      max_lookups_per_second: 1_000
    )

    Runtime.put_env(:pulse, Pulse.Usage, enabled: true, flush_interval_ms: 3_600_000)
    start_supervised!(ManifestSupervision)
    start_supervised!(Tenants)
    start_supervised!(Pulse.Usage)
    %{agent: agent}
  end

  defp digest(token), do: "sha256$" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)

  defp admin(method, path, body \\ nil, token \\ @admin) do
    conn = build_conn() |> put_req_header("authorization", "Bearer " <> token)

    conn =
      if body,
        do:
          conn
          |> put_req_header("content-type", "application/json")
          |> dispatch(@endpoint, method, path, Pulse.JSON.encode!(body)),
        else: dispatch(conn, @endpoint, method, path)

    {conn.status, Pulse.JSON.decode!(conn.resp_body)}
  end

  defp ingest(tenant, token) do
    build_conn()
    |> put_req_header("content-type", "application/x-protobuf")
    |> put_req_header("x-scope-orgid", tenant)
    |> put_req_header("authorization", "Bearer " <> token)
    |> put_req_header("content-length", Integer.to_string(byte_size(Fixture.protobuf())))
    |> post("/v1/traces", Fixture.protobuf())
  end

  defp query(tenant, token) do
    build_conn()
    |> put_req_header("x-scope-orgid", tenant)
    |> put_req_header("authorization", "Bearer " <> token)
    |> get("/api/v1/query", %{"query" => "vector(1)", "time" => "1700000000"})
  end

  defp keys(agent, prefix),
    do: Agent.get(agent, &(&1.objects |> Map.keys() |> Enum.filter(fn key -> String.starts_with?(key, prefix) end)))

  test "provisioned tenants authenticate, are metered once per acknowledged request, and stop when suspended" do
    assert {401, _} = admin("put", "/api/v1/admin/tenants/acme", %{"token_hashes" => [digest("acme-token")]}, "wrong")
    assert {400, _} = admin("put", "/api/v1/admin/tenants/acme", %{"state" => "deleted"})
    assert {400, _} = admin("put", "/api/v1/admin/tenants/acme", %{"token_hashes" => ["plain"]})

    assert {200, record} = admin("put", "/api/v1/admin/tenants/acme", %{"token_hashes" => [digest("acme-token")]})
    assert %{"tenant" => "acme", "state" => "active", "token_count" => 1} = record
    refute Map.has_key?(record, "token_hashes")
    assert {200, %{"tenants" => ["acme"], "next" => nil}} = admin("get", "/api/v1/admin/tenants")

    assert ingest("acme", "acme-token").status == 200
    assert ingest("acme", "wrong").status == 401
    # A refused request is not metered.
    assert ingest("acme", "wrong").status == 401
    assert query("acme", "acme-token").status == 200
    assert ingest("ghost", "acme-token").status == 401

    # Flushes overwrite cumulative totals: repeating one never double-counts.
    assert :ok = Pulse.Usage.flush()
    assert :ok = Pulse.Usage.flush()
    assert {200, usage} = admin("get", "/api/v1/admin/tenants/acme/usage")
    spans = Traces.decode_protobuf(Fixture.protobuf()) |> elem(1) |> length()

    assert usage["total"]["traces"] == %{
             "requests" => 1,
             "bytes" => byte_size(Fixture.protobuf()),
             "records" => spans
           }

    assert usage["total"]["queries"]["requests"] == 1
    assert usage["total"]["logs"] == %{"requests" => 0, "bytes" => 0, "records" => 0}

    # Suspension takes effect for ingest and queries, without touching data.
    assert {200, %{"state" => "suspended", "token_count" => 1}} =
             admin("put", "/api/v1/admin/tenants/acme", %{"state" => "suspended"})

    assert ingest("acme", "acme-token").status == 403
    assert query("acme", "acme-token").status == 403
    # Tenants without a record keep their configured tokens.
    assert ingest("static", "static-token").status == 200

    assert {200, %{"state" => "active"}} = admin("put", "/api/v1/admin/tenants/acme", %{"state" => "active"})
    assert ingest("acme", "acme-token").status == 200

    # Rotation: both hashes work until the old one is removed.
    hashes = [digest("acme-token"), digest("acme-next")]
    assert {200, %{"token_count" => 2}} = admin("put", "/api/v1/admin/tenants/acme", %{"token_hashes" => hashes})
    assert ingest("acme", "acme-next").status == 200
    assert ingest("acme", "acme-token").status == 200
  end

  test "deletion refuses the tenant, purges its data after the grace period, keeps usage and reserves the name",
       %{agent: agent} do
    assert {200, _} = admin("put", "/api/v1/admin/tenants/acme", %{"token_hashes" => [digest("acme-token")]})
    assert ingest("acme", "acme-token").status == 200
    assert ingest("static", "static-token").status == 200
    assert :ok = Pulse.Usage.flush()
    assert keys(agent, "tenants/acme/") != []

    assert {202, %{"state" => "deleting"}} = admin("delete", "/api/v1/admin/tenants/acme")
    assert {202, %{"state" => "deleting"}} = admin("delete", "/api/v1/admin/tenants/acme")
    assert ingest("acme", "acme-token").status == 403
    assert {409, _} = admin("put", "/api/v1/admin/tenants/acme", %{"state" => "active"})

    # Tenants authenticated by configured tokens can be deleted too.
    assert {202, _} = admin("delete", "/api/v1/admin/tenants/static")
    assert ingest("static", "static-token").status == 403

    # Within the grace period nothing is deleted.
    assert {:ok, %{"acme" => {:ok, :waiting}, "static" => {:ok, :waiting}}} = Purger.run()
    assert keys(agent, "tenants/acme/") != []

    # Small batches exercise resumption across passes; the fake store lists
    # three keys per page.
    Runtime.put_env(
      :pulse,
      Tenants,
      Keyword.merge(Runtime.get_env(:pulse, Tenants), deletion_grace_ms: 0, purge_batch: 2)
    )

    assert {:ok, %{"acme" => {:ok, :budget}}} = Purger.run()

    Runtime.put_env(:pulse, Tenants, Keyword.put(Runtime.get_env(:pulse, Tenants), :purge_batch, 5_000))
    assert {:ok, %{"acme" => {:ok, :deleted}, "static" => {:ok, :deleted}}} = Purger.run()

    assert keys(agent, "tenants/acme/") == []
    assert keys(agent, "tenants/static/") == []
    assert keys(agent, Tenants.deletion_prefix()) == []
    assert {200, %{"state" => "deleted", "deleted_at" => _}} = admin("get", "/api/v1/admin/tenants/acme")
    assert {409, _} = admin("put", "/api/v1/admin/tenants/acme", %{"token_hashes" => [digest("acme-token")]})
    assert ingest("acme", "acme-token").status == 403

    # Usage outlives the tenant's data.
    assert {200, usage} = admin("get", "/api/v1/admin/tenants/acme/usage")
    assert usage["total"]["traces"]["requests"] == 1
    assert {:ok, %{}} = Purger.run()
  end

  test "registry reads for unknown tenants are bounded per instance" do
    Runtime.put_env(:pulse, Tenants, Keyword.put(Runtime.get_env(:pulse, Tenants), :max_lookups_per_second, 2))
    first_window = div(System.monotonic_time(:millisecond), 1000)
    statuses = for n <- 1..6, do: ingest("unknown-#{n}", "token").status
    windows = div(System.monotonic_time(:millisecond), 1000) - first_window + 1
    # Two reads per one-second window are allowed, so requests spread over
    # more windows under load get more; the rest get a retryable 503, not a
    # storage read.
    assert Enum.count(statuses, &(&1 == 401)) in 2..min(6, 2 * windows)
    assert Enum.count(statuses, &(&1 == 503)) == 6 - Enum.count(statuses, &(&1 == 401))
  end

  test "the admin API is hidden without admin tokens" do
    Runtime.put_env(:pulse, PulseWeb.AdminController, token_hashes: [])
    assert {404, _} = admin("get", "/api/v1/admin/tenants")
  end
end
