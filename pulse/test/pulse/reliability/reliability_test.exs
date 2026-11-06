defmodule Pulse.ReliabilityTest do
  use PulseWeb.ConnCase, async: true

  alias Pulse.Alerting.Canonical
  alias Pulse.Auth.SharedSecret
  alias Pulse.MCP.Tools
  alias Pulse.Record.{Log, MetricSample, Span}
  alias Pulse.Reliability
  alias Pulse.Reliability.{Investigations, Repository}
  alias Pulse.Reliability.Worker
  alias Pulse.Runtime
  alias Pulse.Runtime.Task
  alias Pulse.Storage
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestSupervision
  alias Pulse.Test.CompactionStore

  @minute 60_000_000_000
  @finish 1_800_000_000_000_000_000
  @now @finish + 2 * @minute

  setup do
    objects =
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

    before_request = fn method, key, body ->
      if hook = Agent.get(objects, &Map.get(&1, :request_hook)), do: hook.(method, key, body)
    end

    store =
      start_supervised!(
        {Bandit, plug: {CompactionStore, agent: objects, before_request: before_request}, ip: {127, 0, 0, 1}, port: 0}
      )

    {:ok, {_, storage_port}} = ThousandIsland.listener_info(store)

    config = %{
      bucket: "pulse",
      endpoint: "http://127.0.0.1:#{storage_port}",
      region: "us-east-1",
      access_key_id: "test-#{System.unique_integer([:positive])}",
      secret_access_key: "test",
      allow_http: true,
      refresh_stale_ms: 0
    }

    Runtime.put_env(:pulse, S3, config)
    Runtime.put_env(:pulse, Storage, adapter: S3)
    start_supervised!(ManifestSupervision)
    owner = self()

    replies =
      start_supervised!(
        {Agent,
         fn -> %{owner: owner, replies: [{"investigate", "none"}], status: 200, webhook_status: 202, block: false} end},
        id: :replies
      )

    api = start_supervised!({Bandit, plug: {__MODULE__, replies}, ip: {127, 0, 0, 1}, port: 0}, id: :api)
    {:ok, {_, port}} = ThousandIsland.listener_info(api)

    settings = [
      enabled: true,
      tenants: ["tenant"],
      api_key: "test-secret",
      base_url: "http://127.0.0.1:#{port}/v1",
      max_input_tokens: 5000,
      input_nano_usd_per_token: 110,
      assessment_budget_nano_usd: 500_000_000_000,
      object_budget_nano_usd: 100_000_000_000,
      investigation_budget_nano_usd: 1_000_000_000_000,
      price_valid_until: "2099-12-31",
      investigation_url: nil,
      investigation_token: "test-hook"
    ]

    Runtime.put_env(:pulse, Reliability, settings)
    %{objects: objects, replies: replies, settings: settings, webhook: "http://127.0.0.1:#{port}/investigate"}
  end

  def init(state), do: state

  def call(conn, state) do
    {:ok, bytes, conn} = read_body(conn)
    input = Pulse.JSON.decode!(bytes)
    current = Agent.get(state, & &1)
    send(current.owner, {:provider_request, conn.request_path, input, conn.req_headers, self()})

    if current.block,
      do:
        (receive do
           :release -> :ok
         end)

    if conn.request_path == "/investigate" do
      send_resp(conn, current.webhook_status, "")
    else
      {decision, query} =
        Agent.get_and_update(state, fn current ->
          [answer | rest] = current.replies
          {answer, %{current | replies: if(rest == [], do: [answer], else: rest)}}
        end)

      result = %{
        "answers" => [
          %{"type" => "choice", "name" => "decision", "choice" => decision},
          %{"type" => "choice", "name" => "query", "choice" => query}
        ],
        "usage" => %{"input_tokens" => 200}
      }

      conn |> put_resp_content_type("application/json") |> send_resp(current.status, Pulse.JSON.encode!(result))
    end
  end

  test "Parquet/S3 to Decisions follow-up to durable MCP signal and capped authenticated handoff", ctx do
    seed()
    Agent.update(ctx.replies, &%{&1 | replies: [{"watch", "slow_traces"}, {"investigate", "none"}]})
    Runtime.put_env(:pulse, Reliability, Keyword.put(ctx.settings, :investigation_url, ctx.webhook))
    assert {:ok, signal} = step()
    assert signal["assessment"]["decision"] == "investigate"
    assert signal["followup_query"] == "slow_traces"
    assert signal["evidence"]["baseline"]["logs"]["count"] == 2
    assert signal["evidence"]["current"]["logs"]["count"] == 1
    assert signal["evidence"]["current"]["traces"]["duration_ns"]["max"] == 500_000_000
    assert_receive {:provider_request, "/v1/decisions", first, _, _}
    assert_receive {:provider_request, "/v1/decisions", second, _, _}
    refute Map.has_key?(Pulse.JSON.decode!(first["input"]), "followup")
    assert Pulse.JSON.decode!(second["input"])["followup"]["query"] == "slow_traces"
    assert signal["followup_evidence"] == Pulse.JSON.decode!(second["input"])["followup"]["result"]
    assert signal["followup_evidence"]["current"]["histogram"] == [0, 0, 0, 1, 0, 0]
    refute first["input"] =~ "private-secret"
    assert_receive {:provider_request, "/investigate", payload, headers, _}
    run = payload["run"]
    assert {"idempotency-key", run["id"]} in headers
    assert run["max_cost_nano_usd"] == 5_000_000_000
    assert {:ok, %{"status" => "complete"}} = step()
    refute_receive {:provider_request, _, _, _, _}
    page = signals()
    assert [stored] = page["results"]
    assert stored["id"] == signal["id"]
    assert stored["followup_evidence"] == signal["followup_evidence"]
    assert page["spend_nano_usd"] |> Map.values() |> hd() |> Map.fetch!("model") == 1_100_000
    assert [%{"status" => "accepted"}] = page["investigations"]
    refute Pulse.JSON.encode!(page) =~ payload["completion_token"]

    assert {:ok, [%{"text" => json}]} =
             Tools.call("get_reliability_signal", %{"tenant" => "tenant", "id" => signal["id"]})

    assert Pulse.JSON.decode!(json)["revision"] == 1

    assert {:error, :completion_receipt_unavailable} =
             Investigations.complete("different", run["id"], payload["completion_token"], "completed")

    assert {:error, :unauthorized} =
             Investigations.complete("tenant", run["id"], String.duplicate("a", 64), "completed")

    conn =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> payload["completion_token"])
      |> post(payload["completion_path"], %{"tenant" => "tenant", "outcome" => "completed"})

    assert json_response(conn, 200) == %{"status" => "completed"}

    assert {:ok, %{"status" => "completed"}} =
             Investigations.complete("tenant", run["id"], payload["completion_token"], "completed")

    assert {:error, :completion_conflict} =
             Investigations.complete("tenant", run["id"], payload["completion_token"], "failed")
  end

  test "ordinary windows are assessed without a deterministic anomaly gate", ctx do
    seed()
    Agent.update(ctx.replies, &%{&1 | replies: [{"expected", "none"}]})
    assert {:ok, %{"assessment" => %{"decision" => "expected"}}} = step()
    assert_receive {:provider_request, "/v1/decisions", _, _, _}
    refute_receive {:provider_request, "/investigate", _, _, _}
  end

  test "enabled supervision performs assessment without a manual step", ctx do
    finish = div(System.system_time(:nanosecond) - 2 * @minute, 5 * @minute) * 5 * @minute
    :ok = S3.append(:logs, "tenant", [log(finish - @minute)])
    Agent.update(ctx.replies, &%{&1 | replies: [{"expected", "none"}]})
    assert [{Pulse.Reliability.Supervisor, opts}] = Pulse.Reliability.Supervisor.children()
    start_supervised!({Pulse.Reliability.Supervisor, Keyword.put(opts, :interval_ms, 60_000)})
    assert_receive {:provider_request, "/v1/decisions", _, _, _}, 30_000
    worker = Runtime.whereis(Worker)
    _ = :sys.get_state(worker)
    assert [%{"window_end_ns" => ^finish, "assessment" => %{"decision" => "expected"}}] = signals()["results"]
  end

  test "runtime configuration validates paid enrollment and declared limits" do
    path = Path.expand("../../../config/runtime.exs", __DIR__)
    read = fn -> Config.Reader.read!(path, env: :test, target: :host)[:pulse][Reliability] end
    refute read.()[:enabled]
    Runtime.put_env("PULSE_RELIABILITY_ENABLED", "true")
    assert_raise RuntimeError, fn -> read.() end
    Runtime.put_env("PULSE_RELIABILITY_TENANTS_JSON", ~s(["tenant"]))
    Runtime.put_env("PULSE_RELIABILITY_OPENAI_API_KEY", "fake-test-key")
    Runtime.put_env("PULSE_RELIABILITY_PRICE_VALID_UNTIL", "2099-12-31")
    assert read.()[:enabled]
    assert read.()[:assessment_budget_nano_usd] == 500_000_000_000
    Runtime.put_env("PULSE_RELIABILITY_INPUT_NANO_USD_PER_TOKEN", "0")
    assert_raise RuntimeError, fn -> read.() end
    Runtime.put_env("PULSE_RELIABILITY_INPUT_NANO_USD_PER_TOKEN", "110")
    Runtime.put_env("PULSE_RELIABILITY_TENANTS_JSON", ~s(["tenant","tenant"]))
    assert_raise RuntimeError, fn -> read.() end

    for tenant <- [".", ".."] do
      Runtime.put_env("PULSE_RELIABILITY_TENANTS_JSON", Pulse.JSON.encode!([tenant]))
      assert_raise RuntimeError, fn -> read.() end
    end

    Runtime.put_env("PULSE_RELIABILITY_TENANTS_JSON", ~s(["tenant.prod","tenant-dev","tenant_1"]))
    assert read.()[:tenants] == ["tenant.prod", "tenant-dev", "tenant_1"]
    Runtime.put_env("PULSE_RELIABILITY_TENANTS_JSON", ~s(["tenant"]))
    Runtime.put_env("PULSE_RELIABILITY_INVESTIGATION_URL", "http://example.com/investigate")
    Runtime.put_env("PULSE_RELIABILITY_INVESTIGATION_TOKEN", "fake-test-token")
    assert_raise RuntimeError, fn -> read.() end
    Runtime.put_env("PULSE_RELIABILITY_INVESTIGATION_URL", "https://example.com/investigate")
    Runtime.put_env("PULSE_RELIABILITY_INVESTIGATION_BUDGET_USD", "0")
    assert read.()[:investigation_budget_nano_usd] == 0
  end

  test "unauthenticated stalled callbacks have bounded admission separate from tenant and interactive queries", ctx do
    owner = self()
    head = Repository.key("tenant")
    Runtime.put_env(:pulse, Pulse.QueryRunner, max_per_tenant: 1, max_interactive: 1)

    hook = fn method, key, _body ->
      if method == "GET" and key == head do
        send(owner, {:callback_read, self()})
        receive do: (:release -> :ok)
      end
    end

    Agent.update(ctx.objects, &Map.put(&1, :request_hook, hook))

    callback =
      Task.async(fn ->
        Investigations.complete("tenant", String.duplicate("a", 32), String.duplicate("b", 64), "completed")
      end)

    assert_receive {:callback_read, handler}, 30_000
    assert {:ok, :same_tenant} = Pulse.QueryRunner.run("tenant", :raw, fn _ -> {:ok, :same_tenant} end)
    assert {:ok, :other_tenant} = Pulse.QueryRunner.run("other", :raw, fn _ -> {:ok, :other_tenant} end)

    assert {:error, :query_overloaded} =
             Investigations.complete("other", String.duplicate("c", 32), String.duplicate("d", 64), "completed")

    refute_receive {:callback_read, _}
    send(handler, :release)
    assert {:error, :completion_receipt_unavailable} = Task.await(callback)
    refute_receive {:provider_request, _, _, _, _}
  end

  test "callback HTTP distinguishes authorization, conflicts and retryable admission, timeout and storage failures",
       ctx do
    seed()
    settings = Keyword.put(ctx.settings, :investigation_url, ctx.webhook)
    Runtime.put_env(:pulse, Reliability, settings)
    assert {:ok, _} = step()
    assert_receive {:provider_request, "/investigate", payload, _, _}
    owner = self()

    blocker =
      Task.async(fn ->
        Pulse.QueryRunner.run("other", :reliability_callback, fn _ ->
          send(owner, {:callback_slot, self()})
          receive do: (:release -> :ok)
        end)
      end)

    assert_receive {:callback_slot, worker}, 30_000
    busy = callback(payload)
    assert json_response(busy, 429) == %{"error" => "completion_busy"}
    assert get_resp_header(busy, "retry-after") == ["1"]
    assert {:ok, root, _} = Repository.load("tenant")
    assert root["investigations"][payload["run"]["id"]]["status"] == "accepted"
    send(worker, :release)
    assert :ok = Task.await(blocker)

    head = Repository.key("tenant")
    Agent.update(ctx.objects, &%{&1 | faults: %{{"GET", head} => {403, :before, 1}}})
    assert json_response(callback(payload), 503) == %{"error" => "completion_unavailable"}

    Agent.update(ctx.objects, &%{&1 | faults: %{{"PUT", head} => {412, :before, 4}}})
    assert json_response(callback(payload), 503) == %{"error" => "completion_unavailable"}
    assert {:ok, root, _} = Repository.load("tenant")
    assert root["investigations"][payload["run"]["id"]]["status"] == "accepted"

    hook = fn method, key, _body ->
      if method == "GET" and key == head do
        send(owner, {:timed_callback_read, self()})
        receive do: (:release -> :ok)
      end
    end

    Agent.update(ctx.objects, &Map.put(&1, :request_hook, hook))
    Runtime.put_env(:pulse, Pulse.QueryRunner, timeout_ms: 100)
    timed = Task.async(fn -> callback(payload) end)
    assert_receive {:timed_callback_read, handler}, 30_000
    assert json_response(Task.await(timed), 504) == %{"error" => "completion_timeout"}
    send(handler, :release)
    Agent.update(ctx.objects, &Map.put(&1, :request_hook, nil))
    Runtime.put_env(:pulse, Pulse.QueryRunner, [])

    bad = Map.put(payload, "completion_token", String.duplicate("x", 64))
    assert json_response(callback(bad), 403) == %{"error" => "completion_rejected"}
    assert json_response(callback(payload, "running"), 400) == %{"error" => "invalid_arguments"}

    invalid_tenant =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> payload["completion_token"])
      |> post(payload["completion_path"], %{"tenant" => "..", "outcome" => "completed"})

    assert json_response(invalid_tenant, 400) == %{"error" => "invalid_arguments"}
    assert json_response(callback(payload), 200) == %{"status" => "completed"}
    assert json_response(callback(payload, "failed"), 409) == %{"error" => "completion_conflict"}
    assert json_response(callback(payload), 200) == %{"status" => "completed"}
  end

  test "completion receipts survive more than thirty starts and expire explicitly after seven days", ctx do
    seed()
    assert {:ok, signal} = step()
    clock = start_supervised!({Agent, fn -> @now end}, id: :receipt_clock)

    settings =
      ctx.settings
      |> Keyword.put(:investigation_url, ctx.webhook)
      |> Keyword.put(:clock_ns, fn -> Agent.get(clock, & &1) end)

    Runtime.put_env(:pulse, Reliability, settings)

    receipts =
      for i <- 0..31 do
        now = @now + i * 120 * @minute
        Agent.update(clock, fn _ -> now end)

        assert {:ok, "accepted"} =
                 dispatch_at("tenant", signal, now, System.monotonic_time(:millisecond) + 5000, settings)

        assert_receive {:provider_request, "/investigate", payload, _, _}
        assert json_response(callback(payload), 200) == %{"status" => "completed"}
        payload
      end

    first = hd(receipts)
    assert {:ok, root, _} = Repository.load("tenant")
    assert map_size(root["investigations"]) == 32
    assert json_response(callback(first), 200) == %{"status" => "completed"}
    Agent.update(clock, fn _ -> @now + 7 * 24 * 60 * @minute - 1 end)
    assert json_response(callback(first), 200) == %{"status" => "completed"}
    assert {:ok, root, _} = Repository.load("tenant")
    assert root["investigations"][first["run"]["id"]]["completed_at_ns"] == @now

    expired = @now + 7 * 24 * 60 * @minute
    Agent.update(clock, fn _ -> expired end)
    assert json_response(callback(first), 410) == %{"error" => "completion_receipt_unavailable"}

    assert {:ok, "accepted"} =
             dispatch_at("tenant", signal, expired, System.monotonic_time(:millisecond) + 5000, settings)

    assert_receive {:provider_request, "/investigate", _, _, _}
    assert {:ok, root, _} = Repository.load("tenant")
    refute Map.has_key?(root["investigations"], first["run"]["id"])
    assert json_response(callback(first), 410) == %{"error" => "completion_receipt_unavailable"}
  end

  test "a late completion receives a full replay horizon measured from completion, not grant time", ctx do
    seed()
    assert {:ok, signal} = step()
    clock = start_supervised!({Agent, fn -> @now end}, id: :receipt_clock)

    settings =
      ctx.settings
      |> Keyword.put(:investigation_url, ctx.webhook)
      |> Keyword.put(:clock_ns, fn -> Agent.get(clock, & &1) end)

    Runtime.put_env(:pulse, Reliability, settings)
    assert {:ok, "accepted"} = dispatch_at("tenant", signal, @now, System.monotonic_time(:millisecond) + 5000, settings)
    assert_receive {:provider_request, "/investigate", first, _, _}
    late = @now + 8 * 24 * 60 * @minute
    Agent.update(clock, fn _ -> late end)
    assert json_response(callback(first), 200) == %{"status" => "completed"}
    assert {:ok, "accepted"} = dispatch_at("tenant", signal, late, System.monotonic_time(:millisecond) + 5000, settings)
    assert_receive {:provider_request, "/investigate", _, _, _}
    assert {:ok, root, _} = Repository.load("tenant")
    assert root["investigations"][first["run"]["id"]]["completed_at_ns"] == late
    Agent.update(clock, fn _ -> late + 7 * 24 * 60 * @minute - 1 end)
    assert json_response(callback(first), 200) == %{"status" => "completed"}

    # Older heads did not record completion times. Do not infer their replay
    # horizon from a potentially much older start time during an upgrade.
    assert {:ok, _} =
             Repository.transact("tenant", fn root ->
               legacy = Map.delete(root["investigations"][first["run"]["id"]], "completed_at_ns")
               {:ok, put_in(root, ["investigations", first["run"]["id"]], legacy), :legacy_receipt}
             end)

    assert json_response(callback(first), 200) == %{"status" => "completed"}
    assert {:ok, root, _} = Repository.load("tenant")
    assert root["investigations"][first["run"]["id"]]["completed_at_ns"] == late + 7 * 24 * 60 * @minute - 1
  end

  test "failed webhook delivery retains spend and its unresolved slot without retry", ctx do
    seed()
    Agent.update(ctx.replies, &%{&1 | webhook_status: 503})
    settings = Keyword.put(ctx.settings, :investigation_url, ctx.webhook)
    Runtime.put_env(:pulse, Reliability, settings)
    assert {:ok, first} = step()
    assert_receive {:provider_request, "/v1/decisions", _, _, _}
    assert_receive {:provider_request, "/investigate", payload, _, _}
    page = signals()
    assert [%{"status" => "delivery_unknown"}] = page["investigations"]
    assert page["spend_nano_usd"] |> Map.values() |> hd() |> Map.fetch!("investigation") == 5_000_000_000

    assert {:error, :investigation_active} =
             dispatch_at(
               "tenant",
               first,
               @now + 61 * @minute,
               System.monotonic_time(:millisecond) + 5000,
               settings
             )

    refute_receive {:provider_request, _, _, _, _}
    assert {:ok, _} = Investigations.complete("tenant", payload["run"]["id"], payload["completion_token"], "failed")
    assert [%{"status" => "failed"}] = signals()["investigations"]
  end

  test "monthly investigation allowance reserves full runs and daily cap resets only next UTC day", ctx do
    seed()
    assert {:ok, signal} = step()
    assert_receive {:provider_request, "/v1/decisions", _, _, _}
    settings = Keyword.put(ctx.settings, :investigation_url, ctx.webhook)
    deadline = System.monotonic_time(:millisecond) + 5000

    assert {:error, :reliability_budget_exhausted} =
             dispatch_at(
               "tenant",
               signal,
               @now,
               deadline,
               Keyword.put(settings, :investigation_budget_nano_usd, 4_999_999_999)
             )

    refute_receive {:provider_request, "/investigate", _, _, _}
    day = div(@now, 86_400_000_000_000)

    assert {:ok, _} =
             Repository.transact("tenant", fn root ->
               {:ok, Map.merge(root, %{"investigation_day" => day, "investigation_starts" => 19}), :seeded}
             end)

    assert {:ok, "accepted"} = dispatch_at("tenant", signal, @now, deadline, settings)
    assert_receive {:provider_request, "/investigate", payload, _, _}
    assert {:ok, _} = Investigations.complete("tenant", payload["run"]["id"], payload["completion_token"], "completed")

    assert {:error, :investigation_daily_limit} =
             dispatch_at("tenant", signal, @now + 61 * @minute, deadline, settings)

    next_day = (day + 1) * 86_400_000_000_000 + 61 * @minute

    assert {:error, :reliability_budget_exhausted} =
             dispatch_at(
               "tenant",
               signal,
               next_day,
               deadline,
               Keyword.put(settings, :investigation_budget_nano_usd, 5_000_000_000)
             )

    assert {:ok, "accepted"} = dispatch_at("tenant", signal, next_day, deadline, settings)
    assert_receive {:provider_request, "/investigate", _, _, _}
  end

  test "partial instrumentation works but missing published segments fail the entire window", ctx do
    :ok = S3.append(:logs, "tenant", [log(@finish - @minute)])
    assert {:ok, signal} = step()
    assert signal["evidence"]["current"]["metrics"]["count"] == 0
    assert_receive {:provider_request, "/v1/decisions", _, _, _}

    Agent.update(ctx.objects, fn state ->
      objects = Map.reject(state.objects, fn {key, _} -> String.ends_with?(key, ".parquet") end)
      %{state | objects: objects}
    end)

    assert {:error, _} = step(now_ns: @now + 5 * @minute)
    assert signals()["results"] |> hd() |> Map.fetch!("revision") == 1
    refute_receive {:provider_request, "/v1/decisions", _, _, _}
  after
    0
  end

  test "full reservations bound follow-ups and budget deferral is explicit", ctx do
    seed()
    Agent.update(ctx.replies, &%{&1 | replies: [{"watch", "metric_inventory"}]})
    assert {:ok, signal} = step(assessment_budget_nano_usd: 550_000)
    assert signal["assessment"] == %{"status" => "unknown", "reason" => "followup_budget_exhausted", "decision" => nil}
    assert_receive {:provider_request, "/v1/decisions", _, _, _}
    refute_receive {:provider_request, _, _, _, _}

    assert {:ok, %{"status" => "budget_deferred"}} =
             step(now_ns: @now + 5 * @minute, assessment_budget_nano_usd: 550_000)

    assert Enum.any?(signals()["assessments"], fn {_, value} -> value["status"] == "budget_deferred" end)
    refute_receive {:provider_request, _, _, _, _}
  end

  test "failed model requests retain spend and are not retried after restart", ctx do
    seed()
    Agent.update(ctx.replies, &%{&1 | status: 503, block: true})
    publisher = Task.async(fn -> step() end)
    assert_receive {:provider_request, "/v1/decisions", _, _, provider}, 30_000
    head = Repository.key("tenant")
    Agent.update(ctx.objects, &%{&1 | faults: %{{"PUT", head} => {500, :after, 1}}})
    send(provider, :release)
    assert {:ok, %{"revision" => 1, "assessment" => %{"status" => "unknown"}}} = Task.await(publisher)
    assert [%{"revision" => 1}] = Enum.filter(changes(), &(&1["kind"] == "assessment"))
    assert {:ok, %{"status" => "complete"}} = step()
    assert signals()["spend_nano_usd"] |> Map.values() |> hd() |> Map.fetch!("model") == 550_000
    refute_receive {:provider_request, _, _, _, _}
  end

  test "overlapping workers cannot authorize duplicate model calls", ctx do
    seed()
    Runtime.put_env(:pulse, Pulse.QueryRunner, max_per_tenant: 4, class_limits: %{alerting: 4})
    Agent.update(ctx.replies, &%{&1 | block: true})
    task = Task.async(fn -> step() end)
    assert_receive {:provider_request, "/v1/decisions", _, _, provider}, 30_000
    assert {:ok, %{"status" => "complete"}} = step()
    send(provider, :release)
    assert {:ok, %{"revision" => 1}} = Task.await(task)
    refute_receive {:provider_request, _, _, _, _}
    assert signals()["spend_nano_usd"] |> Map.values() |> hd() |> Map.fetch!("model") == 550_000
  end

  test "an applied assessment PUT with a failed response cannot emit another revision or handoff", ctx do
    seed()
    Agent.update(ctx.replies, &%{&1 | block: true})
    Runtime.put_env(:pulse, Reliability, Keyword.put(ctx.settings, :investigation_url, ctx.webhook))
    publisher = Task.async(fn -> step() end)
    assert_receive {:provider_request, "/v1/decisions", _, _, provider}, 30_000
    head = Repository.key("tenant")
    Agent.update(ctx.objects, &%{&1 | faults: %{{"PUT", head} => {500, :after, 1}}})
    Agent.update(ctx.replies, &%{&1 | block: false})
    send(provider, :release)
    assert {:ok, %{"revision" => 1} = signal} = Task.await(publisher)
    assert_receive {:provider_request, "/investigate", payload, _, _}
    assert payload["signal"]["revision"] == 1
    assert [%{"revision" => 1}] = signals()["results"]
    assert [%{"revision" => 1, "kind" => "assessment"}] = Enum.filter(changes(), &(&1["kind"] == "assessment"))
    assert signals()["results"] |> hd() |> Map.fetch!("episode_id") == signal["episode_id"]
    assert {:ok, %{"status" => "complete"}} = step()
    refute_receive {:provider_request, _, _, _, _}
    assert signals()["spend_nano_usd"] |> Map.values() |> hd() |> Map.fetch!("model") == 550_000
  end

  test "an applied snapshot PUT with a failed response preserves a competing paid claim", ctx do
    seed()
    Runtime.put_env(:pulse, Pulse.QueryRunner, max_per_tenant: 4, class_limits: %{alerting: 4})
    Agent.update(ctx.replies, &%{&1 | block: true})
    owner = self()
    head = Repository.key("tenant")

    hook = fn method, key, _body ->
      if method == "PUT" and String.contains?(key, "/reliability/v1/windows/") do
        Agent.update(ctx.objects, fn state ->
          state
          |> Map.put(:request_hook, nil)
          |> Map.put(:faults, %{{"PUT", head} => {500, :after, 1}})
          |> Map.put(:barriers, %{{"PUT", head} => owner})
        end)
      end
    end

    Agent.update(ctx.objects, &Map.put(&1, :request_hook, hook))
    publisher = Task.async(fn -> step() end)
    assert_receive {:storage_barrier, response, "PUT", ^head}, 30_000
    Agent.update(ctx.objects, &%{&1 | barriers: %{}})
    assessor = Task.async(fn -> step() end)
    assert_receive {:provider_request, "/v1/decisions", _, _, provider}, 30_000
    send(response, {:release_storage, head})
    assert {:ok, {:ok, %{"status" => "complete"}}} = Task.yield(publisher, 3000)
    page = signals()
    assert [%{"calls" => 1, "status" => "outcome_unknown"}] = Map.values(page["assessments"])
    assert Enum.count(changes(), &(&1["status"] == "snapshot_ready")) == 1
    refute_receive {:provider_request, _, _, _, _}
    send(provider, :release)
    assert {:ok, %{"revision" => 1}} = Task.await(assessor)
    assert signals()["spend_nano_usd"] |> Map.values() |> hd() |> Map.fetch!("model") == 550_000
  end

  test "a stale budget deferral cannot replace a new-month paid reservation", ctx do
    before_midnight = next_month(@now) - 1
    :ok = S3.append(:logs, "tenant", [log(before_midnight - 6 * @minute)])
    Runtime.put_env(:pulse, Pulse.QueryRunner, max_per_tenant: 4, class_limits: %{alerting: 4})
    assert {:ok, _} = step(now_ns: before_midnight)
    assert_receive {:provider_request, "/v1/decisions", _, _, _}
    assert {:ok, _} = Repository.transact("tenant", &{:ok, Map.put(&1, "assessments", %{}), :pending})
    owner = self()
    head = Repository.key("tenant")

    hook = fn method, key, body ->
      if method == "PUT" and key == head and body =~ "budget_deferred" do
        Agent.update(ctx.objects, &Map.put(&1, :request_hook, nil))
        send(owner, {:deferral_pending, self()})

        receive do
          :release -> :ok
        end
      end
    end

    Agent.update(ctx.objects, &Map.put(&1, :request_hook, hook))
    deferred = Task.async(fn -> step(now_ns: before_midnight, assessment_budget_nano_usd: 550_000) end)
    assert_receive {:deferral_pending, response}, 30_000
    Agent.update(ctx.replies, &%{&1 | block: true})
    assessor = Task.async(fn -> step(now_ns: before_midnight + 1) end)
    assert_receive {:provider_request, "/v1/decisions", _, _, provider}, 30_000
    send(response, :release)
    assert {:error, :reliability_already_assessed} = Task.await(deferred)
    assert [%{"calls" => 1, "status" => "outcome_unknown"}] = Map.values(signals()["assessments"])
    send(provider, :release)
    assert {:ok, %{"revision" => 2}} = Task.await(assessor)
  end

  test "advancing replicas do not suppress follow-ups or handoffs and new months own new spend", ctx do
    seed()
    :ok = S3.append(:logs, "tenant", [%{log(@finish - @minute) | service: "worker"}])
    Runtime.put_env(:pulse, Pulse.QueryRunner, max_per_tenant: 4, class_limits: %{alerting: 4})
    Agent.update(ctx.replies, &%{&1 | block: true})
    clock = start_supervised!({Agent, fn -> @now end}, id: :clock)
    read_clock = fn -> Agent.get(clock, & &1) end
    Runtime.put_env(:pulse, Reliability, Keyword.put(ctx.settings, :investigation_url, ctx.webhook))
    first = Task.async(fn -> step(clock_ns: read_clock, assessment_budget_nano_usd: 550_000) end)
    assert_receive {:provider_request, "/v1/decisions", _, _, first_provider}, 30_000
    Agent.update(clock, fn _ -> @now + 1 end)
    second = Task.async(fn -> step(now_ns: @now + 1, clock_ns: read_clock) end)
    assert_receive {:provider_request, "/v1/decisions", _, _, second_provider}, 30_000
    Agent.update(ctx.replies, &%{&1 | replies: [{"expected", "none"}]})
    send(second_provider, :release)
    assert {:ok, _} = Task.await(second, 30_000)
    later = next_month(@now)
    Agent.update(clock, fn _ -> later end)
    Agent.update(ctx.replies, &%{&1 | block: false, replies: [{"watch", "slow_traces"}, {"investigate", "none"}]})
    send(first_provider, :release)
    assert {:ok, signal} = Task.await(first, 30_000)
    assert signal["window_end_ns"] == @finish
    assert signal["assessment"]["decision"] == "investigate"
    assert_receive {:provider_request, "/v1/decisions", _, _, _}, 30_000
    assert_receive {:provider_request, "/investigate", payload, _, _}, 30_000
    assert payload["run"]["started_at_ns"] == later
    page = signals()
    month = later |> div(1_000_000_000) |> DateTime.from_unix!() |> Calendar.strftime("%Y-%m")
    assert page["spend_nano_usd"][month]["model"] == 550_000
    assert page["spend_nano_usd"][month]["investigation"] == 5_000_000_000
  end

  test "a model reservation resamples authorization time after losing its CAS at midnight", ctx do
    before_midnight = next_month(@now) - 1
    :ok = S3.append(:logs, "tenant", [log(before_midnight - 6 * @minute)])
    assert {:ok, _} = step(now_ns: before_midnight)
    assert_receive {:provider_request, "/v1/decisions", _, _, _}
    assert {:ok, _} = Repository.transact("tenant", &{:ok, Map.put(&1, "assessments", %{}), :pending})
    clock = start_supervised!({Agent, fn -> before_midnight end}, id: :clock)
    read_clock = fn -> Agent.get(clock, & &1) end
    owner = self()
    head = Repository.key("tenant")

    hook = fn method, key, body ->
      if method == "PUT" and key == head and body =~ "outcome_unknown" do
        Agent.update(ctx.objects, &Map.put(&1, :request_hook, nil))
        send(owner, {:reservation_pending, self()})

        receive do
          :release -> :ok
        end
      end
    end

    Agent.update(ctx.objects, &Map.put(&1, :request_hook, hook))
    task = Task.async(fn -> step(clock_ns: read_clock, assessment_budget_nano_usd: 1_100_000) end)
    assert_receive {:reservation_pending, response}, 30_000
    Agent.update(clock, fn now -> now + 1 end)

    assert {:ok, _} =
             Repository.transact("tenant", fn root ->
               {:ok, Map.put(root, "clock_ns", before_midnight + 1), :competing_authorization}
             end)

    send(response, :release)
    assert {:ok, %{"revision" => 2}} = Task.await(task)
    assert_receive {:provider_request, "/v1/decisions", _, _, _}
    spend = signals()["spend_nano_usd"] |> Enum.sort() |> Enum.map(fn {_, value} -> value["model"] end)
    assert spend == [550_000, 550_000]
    refute_receive {:provider_request, _, _, _, _}
  end

  test "expiry after a committed reservation prevents HTTP dispatch without refunding it", ctx do
    seed()
    clock = start_supervised!({Agent, fn -> @now end}, id: :clock)
    owner = self()
    head = Repository.key("tenant")

    hook = fn method, key, body ->
      if method == "PUT" and key == head and body =~ "outcome_unknown" do
        Agent.update(ctx.objects, fn state ->
          state |> Map.put(:request_hook, nil) |> Map.put(:barriers, %{{"PUT", head} => owner})
        end)
      end
    end

    Agent.update(ctx.objects, &Map.put(&1, :request_hook, hook))
    date = @now |> div(1_000_000_000) |> DateTime.from_unix!() |> DateTime.to_date() |> Date.to_iso8601()
    task = Task.async(fn -> step(clock_ns: fn -> Agent.get(clock, & &1) end, price_valid_until: date) end)
    assert_receive {:storage_barrier, response, "PUT", ^head}, 30_000
    Agent.update(clock, fn now -> now + 86_400_000_000_000 end)
    Agent.update(ctx.objects, &%{&1 | barriers: %{}})
    send(response, {:release_storage, head})
    assert {:ok, signal} = Task.await(task)
    assert signal["assessment"] == %{"status" => "unknown", "reason" => "reliability_price_expired", "decision" => nil}
    refute_receive {:provider_request, _, _, _, _}
    assert signals()["spend_nano_usd"] |> Map.values() |> hd() |> Map.fetch!("model") == 550_000
  end

  for {answer, query} <- [{"watch", "slow_traces"}, {"investigate", "none"}] do
    test "price approval expiry blocks later #{answer} dispatches", ctx do
      seed()
      clock = start_supervised!({Agent, fn -> @now end}, id: :clock)
      read_clock = fn -> Agent.get(clock, & &1) end
      date = @now |> div(1_000_000_000) |> DateTime.from_unix!() |> DateTime.to_date() |> Date.to_iso8601()
      Agent.update(ctx.replies, &%{&1 | block: true, replies: [{unquote(answer), unquote(query)}]})
      Runtime.put_env(:pulse, Reliability, Keyword.put(ctx.settings, :investigation_url, ctx.webhook))
      task = Task.async(fn -> step(clock_ns: read_clock, price_valid_until: date) end)
      assert_receive {:provider_request, "/v1/decisions", _, _, provider}, 30_000
      Agent.update(clock, fn now -> now + 86_400_000_000_000 end)
      send(provider, :release)
      assert {:ok, _} = Task.await(task)
      refute_receive {:provider_request, _, _, _, _}
      assert signals()["investigations"] == []
      assert signals()["spend_nano_usd"] |> Map.values() |> hd() |> Map.fetch!("model") == 550_000
    end
  end

  test "completed worker windows stop storage polling, resume at settle, and survive restart", ctx do
    seed()
    clock = start_supervised!({Agent, fn -> @now end}, id: :clock)
    settings = Keyword.put(ctx.settings, :clock_ns, fn -> Agent.get(clock, & &1) end)
    Runtime.put_env(:pulse, Reliability, settings)
    Agent.update(ctx.replies, &%{&1 | replies: [{"expected", "none"}]})
    start_supervised!({Pulse.Reliability.Supervisor, Keyword.put(settings, :interval_ms, 60_000)})
    assert_receive {:provider_request, "/v1/decisions", _, _, _}, 30_000
    worker = Runtime.whereis(Worker)
    _ = :sys.get_state(worker)
    tick(worker)
    requests = Agent.get(ctx.objects, & &1.requests)
    for _ <- 1..10, do: tick(worker)
    assert Agent.get(ctx.objects, & &1.requests) == requests
    Agent.update(clock, fn _ -> @now + 5 * @minute - 1 end)
    tick(worker)
    assert Agent.get(ctx.objects, & &1.requests) == requests
    Agent.update(clock, fn _ -> @now + 5 * @minute end)
    tick(worker)
    assert_receive {:provider_request, "/v1/decisions", _, _, _}
    assert signals()["results"] |> hd() |> Map.fetch!("revision") == 2
    stop_supervised!(Pulse.Reliability.Supervisor)
    requests = Agent.get(ctx.objects, & &1.requests)
    start_supervised!({Pulse.Reliability.Supervisor, Keyword.put(settings, :interval_ms, 60_000)})
    _ = :sys.get_state(Runtime.whereis(Worker))
    assert length(Agent.get(ctx.objects, & &1.requests)) == length(requests) + 1
    refute_receive {:provider_request, _, _, _, _}
  end

  test "competing CAS reservations cannot exceed a shared budget" do
    tasks =
      for _ <- 1..8,
          do:
            Task.async(fn ->
              Repository.transact("tenant", fn root ->
                with {:ok, next} <- Repository.charge(root, @now, "model", 7, 10), do: {:ok, next, :reserved}
              end)
            end)

    results = Enum.map(tasks, &Task.await/1)
    assert Enum.count(results, &(&1 == {:ok, :reserved})) == 1

    assert Enum.all?(
             results,
             &(&1 in [{:ok, :reserved}, {:error, :reliability_budget_exhausted}, {:error, :reliability_conflict}])
           )
  end

  test "investigation cooldown survives assessments and concurrency is tenant-global", ctx do
    seed()
    settings = Keyword.put(ctx.settings, :investigation_url, ctx.webhook)
    Runtime.put_env(:pulse, Reliability, settings)
    assert {:ok, first} = step()
    assert_receive {:provider_request, "/v1/decisions", _, _, _}
    assert_receive {:provider_request, "/investigate", payload, _, _}
    assert {:ok, _} = Investigations.complete("tenant", payload["run"]["id"], payload["completion_token"], "completed")
    assert {:ok, second} = step(now_ns: @now + 5 * @minute)
    assert second["episode_id"] == first["episode_id"]
    assert second["last_investigation_ns"] == @now
    assert_receive {:provider_request, "/v1/decisions", _, _, _}
    refute_receive {:provider_request, "/investigate", _, _, _}
    # Pending outcomes never expire into a free concurrency slot, including
    # across day/month changes and after their external execution deadline.
    {:ok, _} =
      Repository.transact("tenant", fn root ->
        pending = Map.new(1..2, &{Integer.to_string(&1), %{"status" => "delivery_unknown"}})
        {:ok, Map.put(root, "investigations", pending), :seeded}
      end)

    assert {:error, :investigation_concurrency_limit} =
             dispatch_at(
               "tenant",
               second,
               @now + 2 * 3_600_000_000_000,
               System.monotonic_time(:millisecond) + 5000,
               settings
             )
  end

  test "expired prices, disabled assessment, object exhaustion and tenant auth fail closed", ctx do
    seed()
    assert {:error, :reliability_disabled} = step(enabled: false)
    assert {:error, :reliability_price_expired} = step(price_valid_until: "2020-01-01")
    assert {:error, :reliability_budget_exhausted} = step(object_budget_nano_usd: 0)
    assert {:ok, _} = Repository.transact("tenant", &{:ok, Map.put(&1, "clock_ns", @now + 1), :clock_advanced})
    assert {:error, :reliability_clock_regressed} = step()
    refute_receive {:provider_request, _, _, _, _}
    hash = Canonical.digest("secret")
    Runtime.put_env(:pulse, Pulse.Auth, module: SharedSecret, tokens: %{"tenant" => "sha256$" <> hash})
    assert {:error, {:unauthorized, _}} = Tools.call("list_reliability_signals", %{"tenant" => "tenant"})
    conn = build_conn() |> put_req_header("authorization", "Bearer secret")
    assert {:ok, _} = Tools.call("list_reliability_signals", %{"tenant" => "tenant"}, %{conn: conn})
    assert {:error, {:unauthorized, _}} = Tools.call("list_reliability_changes", %{"tenant" => "other"}, %{conn: conn})
    assert ctx.settings[:enabled]
  end

  test "durable cursors bind tenant, operation and bounded replay floor" do
    seed()
    assert {:ok, _} = step()
    assert {:ok, page} = Reliability.read(:changes, "tenant")
    assert {:ok, %{"results" => []}} = Reliability.read(:changes, "tenant", %{"cursor" => page["next_cursor"]})
    assert {:error, :reset_required} = Reliability.read(:changes, "other", %{"cursor" => page["next_cursor"]})
    assert {:error, :reset_required} = Reliability.read(:signals, "tenant", %{"cursor" => page["next_cursor"]})

    assert {:ok, _} =
             Repository.transact("tenant", fn root ->
               next =
                 Enum.reduce(1..130, root, fn _, acc -> Repository.event(acc, "coverage", %{"status" => "unknown"}) end)

               {:ok, next, :advanced}
             end)

    assert {:error, :reset_required} = Reliability.read(:changes, "tenant", %{"cursor" => page["next_cursor"]})
    assert {:ok, %{"results" => rows}} = Reliability.read(:changes, "tenant", %{"limit" => 100})
    assert length(rows) == 100
  end

  defp step(opts \\ []) do
    {now, opts} = Keyword.pop(opts, :now_ns, @now)
    Reliability.step("tenant", Keyword.put_new(opts, :clock_ns, fn -> now end))
  end

  defp dispatch_at(tenant, signal, now, deadline, config),
    do: Investigations.dispatch(tenant, signal, deadline, Keyword.put(config, :clock_ns, fn -> now end))

  defp callback(payload, outcome \\ "completed") do
    build_conn()
    |> put_req_header("authorization", "Bearer " <> payload["completion_token"])
    |> post(payload["completion_path"], %{"tenant" => "tenant", "outcome" => outcome})
  end

  defp tick(worker) do
    send(worker, :assess)
    _ = :sys.get_state(worker)
  end

  defp changes do
    assert {:ok, page} = Reliability.read(:changes, "tenant", %{"limit" => 100})
    page["results"]
  end

  defp next_month(now) do
    date = now |> div(1_000_000_000) |> DateTime.from_unix!() |> DateTime.to_date()

    Date.add(date, Date.days_in_month(date) - date.day + 1)
    |> DateTime.new!(~T[00:00:00])
    |> DateTime.to_unix(:nanosecond)
  end

  defp signals do
    assert {:ok, [%{"text" => text}]} = Tools.call("list_reliability_signals", %{"tenant" => "tenant"})
    Pulse.JSON.decode!(text)
  end

  defp seed do
    for service <- ["api"] do
      :ok =
        S3.append(
          :logs,
          "tenant",
          Enum.map([@finish - 25 * @minute, @finish - 10 * @minute, @finish - @minute], &%{log(&1) | service: service})
        )

      :ok =
        S3.append(:metrics, "tenant", [
          %MetricSample{
            timestamp_ns: @finish - @minute,
            value: 42.0,
            labels: %{"__name__" => "temperature", "service_name" => service, "deployment_environment" => "prod"}
          }
        ])

      :ok =
        S3.append(:traces, "tenant", [
          %Span{
            timestamp_ns: @finish - @minute,
            end_timestamp_ns: @finish - @minute + 500_000_000,
            trace_id: String.duplicate("1", 32),
            span_id: String.duplicate("2", 16),
            service: service,
            kind: 2,
            resource: %{"deployment.environment.name" => "prod"}
          }
        ])
    end
  end

  defp log(ts),
    do: %Log{
      timestamp_ns: ts,
      service: "api",
      severity_text: "INFO",
      body: "private-secret token=123",
      resource: %{"deployment.environment.name" => "prod"}
    }
end
