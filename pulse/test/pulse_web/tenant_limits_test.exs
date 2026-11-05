defmodule PulseWeb.TenantLimitsTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Auth.SharedSecret
  alias Pulse.QueryRunner
  alias Pulse.Storage
  alias Pulse.TenantLimits
  alias Pulse.Test.OTLPTraceFixture, as: Fixture

  @tokens %{"acme" => "acme-token", "other" => "other-token"}

  setup do
    start_supervised!(Pulse.IngestAdmission)

    digests =
      Map.new(@tokens, fn {tenant, token} ->
        {tenant, "sha256$" <> Base.encode16(:crypto.hash(:sha256, token), case: :lower)}
      end)

    Pulse.Runtime.put_env(:pulse, Pulse.Auth, module: SharedSecret, tokens: digests)
    :ok
  end

  defp limit(json), do: Pulse.Runtime.put_env(:pulse, TenantLimits, limits: TenantLimits.parse!(json))

  defp ingest(tenant, token \\ nil) do
    build_conn()
    |> put_req_header("content-type", "application/x-protobuf")
    |> put_req_header("x-scope-orgid", tenant)
    |> put_req_header("authorization", "Bearer " <> (token || @tokens[tenant]))
    |> put_req_header("content-length", Integer.to_string(byte_size(Fixture.protobuf())))
    |> post("/v1/traces", Fixture.protobuf())
  end

  defp hold(tenant) do
    owner = self()

    pid =
      spawn(
        Pulse.Runtime.capture(fn ->
          # A verified metrics request; the bound counts across signals.
          send(owner, {:held, Pulse.IngestAdmission.acquire(:metrics, tenant, tenant)})
          receive do: (:stop -> :ok)
        end)
      )

    assert_receive {:held, :ok}
    pid
  end

  test "a tenant at its concurrency share is refused while other tenants are admitted" do
    limit(~s({"default": {"ingest_max_concurrent": 1}}))
    holder = hold("acme")

    conn = ingest("acme")
    assert conn.status == 429
    assert get_resp_header(conn, "retry-after") == ["1"]

    assert Pulse.SelfMetrics.render() =~
             ~s(pulse_admission_rejections_total{layer="ingest",reason="tenant_concurrency"} 1\n)

    assert ingest("other").status == 200
    assert {:ok, []} = Storage.query(:traces, "acme")

    ref = Process.monitor(holder)
    Process.exit(holder, :kill)
    assert_receive {:DOWN, ^ref, :process, _, _}
    _ = :sys.get_state(Pulse.Runtime.whereis(Pulse.IngestAdmission))
    assert ingest("acme").status == 200
    # Released requests leave no tenant counters behind.
    assert :ets.match(Pulse.Runtime.table(Pulse.IngestAdmission), {{:limit, :_}, :_}) == []
  end

  test "byte rates are per tenant, refill over time, and never charge unverified callers" do
    size = byte_size(Fixture.protobuf())
    # Burst fits exactly two requests; the rate refills one per 10 seconds.
    limit(
      ~s({"tenants": {"acme": {"ingest_bytes_per_second": #{max(div(size, 10), 1)}, "ingest_burst_bytes": #{2 * size}}}})
    )

    # A spoofed tenant header with bad credentials is rejected by auth, not quota.
    for _ <- 1..3, do: assert(ingest("acme", "wrong").status == 401)

    assert ingest("acme").status == 200
    assert ingest("acme").status == 200
    conn = ingest("acme")
    assert conn.status == 429
    assert conn.resp_body =~ "tenant ingest rate limit reached"
    assert Pulse.SelfMetrics.render() =~ ~s(pulse_admission_rejections_total{layer="ingest",reason="tenant_rate"} 1\n)
    # Unlisted tenants have no rate limit.
    for _ <- 1..3, do: assert(ingest("other").status == 200)

    # Rewind the bucket clock instead of sleeping.
    table = Pulse.Runtime.table(TenantLimits.table())
    [{_, tokens, at}] = :ets.lookup(table, "acme")
    :ets.insert(table, {"acme", tokens, at - 11_000})
    assert ingest("acme").status == 200
  end

  test "query concurrency can be raised or lowered per tenant" do
    limit(~s({"default": {"query_max_concurrent": 1}, "tenants": {"acme": {"query_max_concurrent": 3}}}))
    caller = self()
    supervisor = start_supervised!({Pulse.Runtime.Task.Supervisor, name: __MODULE__.Callers})

    start = fn tenant ->
      {:ok, _} =
        Pulse.Runtime.Task.Supervisor.start_child(supervisor, fn ->
          QueryRunner.run(tenant, :promql, fn _ ->
            send(caller, {:started, tenant})
            receive do: (:release -> {:ok, tenant})
          end)
        end)

      assert_receive {:started, ^tenant}, 5_000
    end

    start.("other")
    assert {:error, :query_overloaded} = QueryRunner.run("other", :raw, fn _ -> {:ok, :unexpected} end)
    start.("acme")
    start.("acme")
  end

  test "limit documents parse strictly" do
    assert %{default: %{}, tenants: %{"a" => %{ingest_max_concurrent: 2}}} =
             TenantLimits.parse!(~s({"tenants": {"a": {"ingest_max_concurrent": 2}}}))

    for json <- [~s([]), ~s({"x": {}}), ~s({"default": {"unknown": 1}}), ~s({"default": {"query_max_concurrent": 0}})] do
      assert_raise RuntimeError, fn -> TenantLimits.parse!(json) end
    end
  end
end
