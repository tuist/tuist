defmodule Atlas.Engineering.Errors.PulseMirrorTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Errors.Availability
  alias Atlas.Engineering.Errors.Event
  alias Atlas.Engineering.Errors.IssueCoalescer
  alias Atlas.Engineering.Errors.LoggerHandler
  alias Atlas.Engineering.Errors.PulseMirror
  alias Atlas.Engineering.Errors.SelfMonitor
  alias Atlas.Engineering.Errors.SentryEvent
  alias Atlas.Engineering.Projects

  setup_all do
    start_supervised!(
      {Finch,
       name: PulseMirror.Finch, pools: %{default: [size: 1, count: 1, conn_opts: [transport_opts: [timeout: 500]]]}}
    )

    :ok
  end

  setup do
    owner = self()
    stub(Availability, :enabled?, fn -> true end)

    stub(Event.Buffer, :insert, fn row ->
      send(owner, {:primary, row})
      {:ok, row}
    end)

    stub(IssueCoalescer, :observe, fn _, _, _, _, _ -> :ok end)

    {:ok, project} =
      Projects.create_project(%{"name" => "Mirror-#{System.unique_integer([:positive])}", "visibility" => "private"})

    {:ok, key} = Errors.create_project_key(project.id)
    {:ok, project: project, key: key}
  end

  # A real, test-owned HTTP receiver. Tests choose when/how each request ends.
  def init(owner), do: owner

  def call(conn, owner) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    send(owner, {:pulse_request, self(), conn.request_path, conn.req_headers, body})

    receive do
      {:respond, status} -> Plug.Conn.send_resp(conn, status, "ignored remote diagnostic")
    after
      5_000 -> Plug.Conn.send_resp(conn, 503, "late")
    end
  end

  test "unavailable Pulse retries stable bytes, while clients and Atlas primary still succeed", ctx do
    {_worker, _table} = mirror(ctx.project)
    assert client_capture(ctx.key, %{"message" => "external", "event_id" => event_id()}).status == 200
    assert_receive {:primary, row}
    assert_receive {:pulse_request, receiver, "/api/42/store/", headers, first}, 2_000
    assert {"x-sentry-auth", "Sentry sentry_key=mirror-key"} in headers
    assert Jason.decode!(first)["event_id"] == String.replace(row.event_id, "-", "")
    send(receiver, {:respond, 503})

    # The retry is the identical event (including timestamp and ID), not a new capture.
    assert_receive {:pulse_request, receiver, _, _, ^first}, 3_000
    assert client_capture(ctx.key, %{"message" => "during outage"}).status == 200
    assert_receive {:primary, %Event{}}
    send(receiver, {:respond, 503})
    assert_receive {:pulse_request, receiver, _, _, second}, 2_000
    send(receiver, {:respond, 200})
    assert second != first
    assert_receive {:pulse_request, receiver, _, _, ^first}, 7_000
    send(receiver, {:respond, 503})
    eventually(fn -> PulseMirror.stats().failed == 1 end)
    assert PulseMirror.stats().retried == 2
    refute_receive {:pulse_request, _, _, _, ^first}, 200
  end

  test "slow Pulse cannot hold the client path and saturated admission drops only mirror copies", ctx do
    {worker, table} = mirror(ctx.project)
    assert client_capture(ctx.key, %{"message" => "slow Pulse"}).status == 200
    assert_receive {:primary, %Event{}}
    assert_receive {:pulse_request, receiver, _, _, _}, 2_000

    # This completes while the receiver has not answered the first upload.
    assert client_capture(ctx.key, %{"message" => "not blocked"}).status == 200
    assert_receive {:primary, %Event{}}
    eventually(fn -> PulseMirror.stats().retried == 1 end)
    send(receiver, {:respond, 200})

    :sys.suspend(worker)

    try do
      for _ <- 1..100 do
        assert client_capture(ctx.key, %{"message" => "saturation"}).status == 200
        assert_receive {:primary, %Event{}}
      end

      assert queued_count(table) == 64
      assert PulseMirror.stats().full >= 36
      assert {:message_queue_len, queued_messages} = Process.info(worker, :message_queue_len)
      assert queued_messages <= 1
    after
      :sys.resume(worker)
    end
  end

  test "SDK and native capture share admission; scrubbing precedes queue storage without changing Atlas", ctx do
    {worker, table} = mirror(ctx.project)
    :sys.suspend(worker)

    try do
      payload = %{
        "message" => "retained diagnostic",
        "user" => %{"email" => "private@example.com"},
        "request" => %{"data" => "private-body"},
        "SENTRY.INTERFACES.Http" => %{"url" => "private-url"},
        "extra" => %{"nested" => [%{"api_key" => "private-key", "passwd" => "private-passwd"}]},
        "sentry_key" => "private-sentry-key",
        "tags" => [["token", "private-token"]],
        "atlas_project_id" => "forged",
        "atlas_domain_id" => "forged",
        "project" => "999"
      }

      assert client_capture(ctx.key, payload).status == 200
      assert_receive {:primary, row}
      assert queued_count(table) == 1
      assert row.payload =~ "private-body"
      refute inspect(:ets.tab2list(table)) =~ "private-body"
      refute inspect(:ets.tab2list(table)) =~ "private@example.com"
      refute inspect(:ets.tab2list(table)) =~ "private-token"
      refute inspect(:ets.tab2list(table)) =~ "private-url"
      refute inspect(:ets.tab2list(table)) =~ "private-key"
      refute inspect(:ets.tab2list(table)) =~ "private-passwd"
      refute inspect(:ets.tab2list(table)) =~ "private-sentry-key"

      stub(SelfMonitor, :self_project_id, fn -> ctx.project.id end)
      assert :ok = LoggerHandler.log(%{level: :error, msg: {:string, "native failure"}, meta: %{}}, %{})
      assert_receive {:primary, native}
      assert Jason.decode!(native.payload)["sdk"]["name"] == "atlas.self"
      assert queued_count(table) == 2
    after
      :sys.resume(worker)
    end

    assert_receive {:pulse_request, receiver, _, _, body}, 2_000
    event = Jason.decode!(body)
    assert event["atlas_project_id"] == ctx.project.id
    assert event["atlas_domain_id"] == nil
    assert event["project"] == "42"
    assert event["message"] == "retained diagnostic"
    assert event["user"] == "[Filtered]"
    send(receiver, {:respond, 200})
    assert_receive {:pulse_request, receiver, _, _, body}, 2_000
    assert Jason.decode!(body)["sdk"]["name"] == "atlas.self"
    send(receiver, {:respond, 200})
  end

  test "exact source domain selects the provisioned target, never client project or tenant claims", ctx do
    domain = Ecto.UUID.generate()
    {worker, table} = mirror(ctx.project, domain)
    :sys.suspend(worker)

    try do
      event = SentryEvent.parse(%{"message" => "domain", "project" => "999", "tenant" => "another"})
      assert :ok = Errors.record_event(ctx.project, event)
      assert queued_count(table) == 0
      assert :ok = Errors.record_event(ctx.project, event, domain_id: Ecto.UUID.generate())
      assert queued_count(table) == 0
      assert :ok = Errors.record_event(ctx.project, event, domain_id: domain)
      assert queued_count(table) == 1
    after
      :sys.resume(worker)
    end

    assert_receive {:pulse_request, receiver, "/api/42/store/", headers, body}, 2_000
    assert Jason.decode!(body)["atlas_domain_id"] == domain
    refute Enum.any?(headers, fn {name, _} -> name == "x-scope-orgid" end)
    send(receiver, {:respond, 200})
  end

  test "SDK resubmission preserves project/event identity and permanent rejections do not retry", ctx do
    mirror(ctx.project)
    payload = %{"event_id" => event_id(), "timestamp" => "2026-11-01T01:02:03Z", "message" => "duplicate"}
    assert client_capture(ctx.key, payload).status == 200
    assert_receive {:pulse_request, receiver, _, _, body}, 2_000
    send(receiver, {:respond, 200})
    assert client_capture(ctx.key, payload).status == 200
    assert_receive {:pulse_request, receiver, _, _, ^body}, 2_000
    send(receiver, {:respond, 403})
    eventually(fn -> PulseMirror.stats().failed == 1 end)
    assert PulseMirror.stats().delivered == 1
    assert PulseMirror.stats().retried == 0
    refute_receive {:pulse_request, _, _, _, _}, 200
  end

  test "oversized copies and stopped mirrors do not alter Atlas results", ctx do
    {worker, table} = mirror(ctx.project)
    assert client_capture(ctx.key, %{"message" => String.duplicate("x", 131_073)}).status == 200
    assert_receive {:primary, row}
    assert byte_size(row.payload) > 131_072
    assert queued_count(table) == 0
    assert PulseMirror.stats().rejected == 1
    stop_supervised!(PulseMirror)
    refute Process.info(worker)
    assert client_capture(ctx.key, %{"message" => "stopped"}).status == 200
    assert_receive {:primary, %Event{}}
  end

  test "invalid and duplicate mappings fail closed without disclosing credentials", ctx do
    route = route(ctx.project, nil, "https://pulse.invalid")

    for bad <- [
          Map.put(route, "tenant", "untrusted"),
          Map.put(route, "pulse_project_id", "uuid"),
          Map.put(route, "url", "https://key@pulse.invalid"),
          Map.put(route, "atlas_domain_id", "*")
        ] do
      assert_raise ArgumentError, "invalid Pulse mirror route", fn -> PulseMirror.validate_routes!([bad]) end
    end

    assert_raise ArgumentError, "duplicate Pulse mirror source", fn -> PulseMirror.validate_routes!([route, route]) end
  end

  test "disabled configuration has no children; unexpected mirror exits cannot restart Atlas", ctx do
    stub(PulseMirror.Config, :options, fn -> [] end)
    assert PulseMirror.children() == []
    stub(PulseMirror.Config, :options, fn -> [routes: []] end)
    assert PulseMirror.children() == []

    stub(PulseMirror.Config, :options, fn ->
      [routes: [route(ctx.project, nil, "https://pulse.invalid")], named: false]
    end)

    [finch, worker] = Enum.map(PulseMirror.children(), &Supervisor.child_spec(&1, []))
    # The optional Finch must not collide with Atlas's existing Finch child ID.
    refute finch.id == Supervisor.child_spec(Atlas.HTTP.finch_child_spec(), []).id
    assert finch.restart == :temporary
    assert worker.restart == :temporary
    {Finch, :start_link, [options]} = finch.start
    finch = %{finch | start: {Finch, :start_link, [Keyword.put(options, :name, __MODULE__.CrashFinch)]}}

    supervisor =
      start_supervised!(%{
        id: :mirror_isolation,
        start: {Supervisor, :start_link, [[finch, worker], [strategy: :one_for_one]]}
      })

    for {_id, pid, _, _} <- Supervisor.which_children(supervisor) do
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
    end

    eventually(fn -> Supervisor.which_children(supervisor) == [] end)
    assert client_capture(ctx.key, %{"message" => "after unexpected subsystem failure"}).status == 200
    assert_receive {:primary, %Event{}}
  end

  defp mirror(project, domain \\ nil) do
    receiver = start_supervised!({Bandit, plug: {__MODULE__, self()}, port: 0, ip: {127, 0, 0, 1}})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(receiver)

    worker =
      start_supervised!({PulseMirror, routes: [route(project, domain, "http://127.0.0.1:#{port}")], named: false})

    table = :sys.get_state(worker).table
    stub(PulseMirror.Config, :table, fn -> table end)
    {worker, table}
  end

  defp route(project, domain, url) do
    %{
      "atlas_project_id" => project.id,
      "atlas_domain_id" => domain,
      "pulse_project_id" => "42",
      "url" => url,
      "public_key" => "mirror-key"
    }
  end

  defp client_capture(key, payload) do
    json = Jason.encode!(payload)
    body = "{}\n" <> Jason.encode!(%{"type" => "event", "length" => byte_size(json)}) <> "\n" <> json

    build_conn()
    |> put_req_header("content-type", "application/x-sentry-envelope")
    |> put_req_header("x-sentry-auth", "Sentry sentry_key=#{key.public_key}")
    |> post("/api/#{key.dsn_project_id}/envelope/", body)
  end

  defp queued_count(table), do: :ets.select_count(table, [{{:"$1", :_}, [{:is_integer, :"$1"}], [true]}])
  defp event_id, do: String.replace(Ecto.UUID.generate(), "-", "")

  # Receive with a deadline instead of sleeping; counters change only in the sender.
  defp eventually(check, attempts \\ 150)
  defp eventually(check, 0), do: assert(check.())

  defp eventually(check, attempts) do
    if !check.() do
      receive do
      after
        20 -> eventually(check, attempts - 1)
      end
    end
  end
end
