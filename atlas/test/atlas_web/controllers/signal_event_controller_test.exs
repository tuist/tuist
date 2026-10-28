defmodule AtlasWeb.SignalEventControllerTest do
  use AtlasWeb.ConnCase, async: true
  use Mimic

  import Atlas.AutomationsFixtures
  import Ecto.Query

  alias Atlas.Authorization.UserRole
  alias Atlas.Automations.Executor
  alias Atlas.Automations.Run
  alias Atlas.LLMs.Runner
  alias Atlas.Orbit
  alias Atlas.Repo
  alias Atlas.Signals
  alias Atlas.Signals.Config
  alias Atlas.Signals.Signal
  alias Atlas.Signals.Source

  setup %{conn: conn} do
    stub(Runner, :orbit_configured?, fn _ -> true end)
    {_, actor} = log_in_user(conn, %{scopes: ["automation:write", "accounts:read"]})

    {_, revision} =
      workflow_fixture(actor, [
        %{
          "id" => "triage",
          "behavior" => "signals.decide@1",
          "inputs" => %{
            "signal_id" => %{"$ref" => "input.signal_id"},
            "action" => "opened",
            "priority" => "today",
            "reason" => "Investigate new flaky tests"
          }
        }
      ])

    attrs = %{
      "name" => "Project test health",
      "revision_id" => revision.id,
      "reader_ids" => [],
      "required_scopes" => ["accounts:read"],
      "event_receiver" => %{
        "name" => "test_case.marked_flaky",
        "title" => "New flaky test",
        "summary" => "Inspect the test's recent runs and propose a fix; do not change its state.",
        "match" => %{"account_handle" => "example", "project_handle" => "ios"},
        "correlation_field" => "test_case_id",
        "subjects" => ["service:ios"],
        "topics" => ["testing"]
      }
    }

    token = oauth_access_token_fixture(actor)

    created =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/automation/signal-sources", attrs)
      |> json_response(200)
      |> Map.fetch!("data")

    %{
      actor: actor,
      token: token,
      source_id: created["id"],
      path: created["delivery"]["path"],
      secret: created["delivery"]["secret"],
      created: created
    }
  end

  test "signed verification works while disabled; secrets are encrypted, redacted and returned only on creation",
       context do
    %{actor: actor, token: token, source_id: id, path: path, secret: secret, created: created} = context
    refute Map.has_key?(created, "signing_secret")
    response = deliver(path, secret, %{"type" => "verification", "challenge" => "prove-this-callback"})
    assert json_response(response, 200) == %{"challenge" => "prove-this-callback"}
    assert get_resp_header(response, "cache-control") == ["no-store"]
    assert Repo.aggregate(Signal, :count) == 0
    assert Repo.aggregate(Run, :count) == 0

    listed =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> token)
      |> get("/api/automation/signal-sources")
      |> json_response(200)
      |> JSON.encode!()

    refute listed =~ secret
    refute listed =~ "signing_secret"
    source = Repo.get!(Source, id)
    refute inspect(source) =~ source.signing_secret
    {:ok, key} = secret |> String.replace_prefix("whsec_", "") |> Base.decode64()
    [[encrypted]] = Repo.query!("SELECT signing_secret FROM signal_sources WHERE id = $1", [Ecto.UUID.dump!(id)]).rows
    refute encrypted == key
    assert json_response(deliver(path, secret, event()), 409)["error"] == "source_disabled"
    assert {:ok, _} = Signals.set_enabled(actor, id, true)
  end

  test "a flaky event admits once, opens a correlated investigation, and different tests stay separate", context do
    %{actor: actor, source_id: id, path: path, secret: secret} = context
    assert {:ok, _} = Signals.set_enabled(actor, id, true)
    event = event()
    received = deliver(path, secret, event) |> json_response(202)
    assert deliver(path, secret, event) |> json_response(202) == received
    assert Repo.aggregate(Signal, :count) == 1
    signal = Repo.get!(Signal, received["signal_id"])
    advance(signal.execution_id)
    assert {:ok, opened} = Signals.get(actor, signal.id)
    assert opened.status == "opened"
    assert opened.envelope["data"]["test_case_id"] == "test-a"
    assert {:ok, thread} = Orbit.fetch(actor, opened.thread_id)
    assert thread.priority == "today"
    assert Repo.get_by!(Atlas.Orbit.Run, thread_id: thread.id).status == "queued"

    follow_up = Map.put(event, "eventId", Ecto.UUID.generate())
    next = deliver(path, secret, follow_up) |> json_response(202)
    advance(Repo.get!(Signal, next["signal_id"]).execution_id)
    assert {:ok, %{thread_id: same}} = Signals.get(actor, next["signal_id"])
    assert same == thread.id

    other = follow_up |> Map.put("eventId", Ecto.UUID.generate()) |> put_in(["data", "test_case_id"], "test-b")
    next = deliver(path, secret, other) |> json_response(202)
    advance(Repo.get!(Signal, next["signal_id"]).execution_id)
    assert {:ok, %{thread_id: different}} = Signals.get(actor, next["signal_id"])
    refute different == thread.id
    changed = put_in(event, ["data", "url"], "https://example.org/changed")
    assert deliver(path, secret, changed) |> json_response(409)
    assert Repo.aggregate(Signal, :count) == 3
  end

  test "tampering, stale signatures, cross-source replay and nonmatching events cannot admit work", context do
    %{actor: actor, source_id: id, path: path, secret: secret} = context
    {:ok, _} = Signals.set_enabled(actor, id, true)
    event = event()
    assert deliver(path, secret, event, signed_body: "{}") |> json_response(401)
    assert deliver(path, secret, event, timestamp: System.system_time(:second) - 301) |> json_response(401)
    assert deliver(path, secret, event, timestamp: System.system_time(:second) + 301) |> json_response(401)
    assert deliver("/api/signals/#{Ecto.UUID.generate()}/mcp-events", secret, event) |> json_response(401)
    assert deliver(path, secret, event, message_id: "a-different-id") |> json_response(422)

    for invalid <- [
          Map.put(event, "name", "test_case.deleted"),
          put_in(event, ["data", "project_handle"], "android"),
          put_in(event, ["data", "test_case_id"], nil),
          put_in(event, ["data", "test_case_id"], %{"nested" => true}),
          Map.put(event, "timestamp", "invalid")
        ] do
      assert deliver(path, secret, invalid) |> json_response(422)
    end

    assert Repo.aggregate(Signal, :count) == 0
    Repo.delete_all(from assignment in UserRole, where: assignment.user_id == ^actor.id)
    assert deliver(path, secret, event) |> json_response(422)
    assert Repo.aggregate(Signal, :count) == 0
    assert Repo.aggregate(Run, :count) == 0
  end

  test "typed CI and workflow filters reject string equivalents and structured values", context do
    %{actor: actor, source_id: id} = context
    source = Repo.get!(Source, id)
    config = put_in(source.event_receiver, ["match", "is_ci"], true)
    config = put_in(config, ["match", "workflow_run_id"], 37)

    attrs = %{
      "name" => "CI test health",
      "revision_id" => source.revision_id,
      "reader_ids" => [],
      "required_scopes" => ["accounts:read"],
      "event_receiver" => config
    }

    assert {:ok, filtered} = Signals.create_source(actor, attrs)
    assert {:ok, _} = Signals.set_enabled(actor, filtered.id, true)
    %{path: path, secret: secret} = filtered.delivery
    event = event() |> put_in(["data", "is_ci"], true) |> put_in(["data", "workflow_run_id"], 37)

    for {field, value} <- [{"is_ci", "true"}, {"is_ci", false}, {"workflow_run_id", "37"}, {"workflow_run_id", 37.0}] do
      assert deliver(path, secret, put_in(event, ["data", field], value)) |> json_response(422)
    end

    assert Repo.aggregate(Signal, :count) == 0
    assert deliver(path, secret, event) |> json_response(202)
    assert Repo.aggregate(Signal, :count) == 1

    for value <- [nil, [], %{"nested" => true}, 9_007_199_254_740_992] do
      invalid = put_in(attrs, ["event_receiver", "match", "is_ci"], value)
      assert {:error, :invalid_source} = Signals.create_source(actor, invalid)
    end
  end

  test "the operator gate blocks activation, callbacks and decisions but preserves verification and pausing", context do
    %{actor: actor, token: token, source_id: id, path: path, secret: secret} = context
    assert {:ok, _} = Signals.set_enabled(actor, id, true)
    stub(Config, :enabled?, fn -> false end)

    denied =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> token)
      |> post("/api/automation/signal-sources/#{id}/enabled", %{"enabled" => true})

    assert json_response(denied, 503) == %{"error" => "signals_disabled"}
    assert json_response(deliver(path, secret, event()), 503) == %{"error" => "signals_disabled"}

    assert {:error, :signals_disabled} =
             Signals.decide(actor, %{
               "signal_id" => Ecto.UUID.generate(),
               "action" => "opened",
               "priority" => "today",
               "reason" => "Gate must precede admission"
             })

    assert json_response(deliver(path, secret, %{"type" => "verification", "challenge" => "still-verifies"}), 200) ==
             %{"challenge" => "still-verifies"}

    assert {:ok, %{enabled: false}} = Signals.set_enabled(actor, id, false)
    assert {:ok, _} = Signals.list_sources(actor)
    assert Repo.aggregate(Signal, :count) == 0
    assert Repo.aggregate(Run, :count) == 0
  end

  defp event do
    %{
      "eventId" => Ecto.UUID.generate(),
      "name" => "test_case.marked_flaky",
      "timestamp" => "2026-10-28T15:00:00Z",
      "cursor" => nil,
      "data" => %{
        "account_handle" => "example",
        "project_handle" => "ios",
        "test_case_id" => "test-a",
        "url" => "https://example.org/tests/a"
      }
    }
  end

  defp deliver(path, "whsec_" <> encoded, payload, opts \\ []) do
    body = JSON.encode!(payload)
    timestamp = to_string(Keyword.get(opts, :timestamp, System.system_time(:second)))
    id = Keyword.get(opts, :message_id, payload["eventId"] || Ecto.UUID.generate())
    {:ok, key} = Base.decode64(encoded)

    signature =
      :crypto.mac(:hmac, :sha256, key, "#{id}.#{timestamp}.#{Keyword.get(opts, :signed_body, body)}") |> Base.encode64()

    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("webhook-id", id)
    |> put_req_header("webhook-timestamp", timestamp)
    |> put_req_header("webhook-signature", "v1," <> signature)
    |> post(path, body)
  end

  defp advance(id) do
    run =
      Enum.reduce_while(1..10, nil, fn _, _ ->
        assert {:ok, _} = Executor.advance(id)
        run = Repo.get!(Run, id)
        if run.status in ~w(succeeded failed cancelled), do: {:halt, run}, else: {:cont, run}
      end)

    assert run.status == "succeeded"
  end
end
