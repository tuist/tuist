defmodule Atlas.Signals.PollingTest do
  use Atlas.DataCase, async: true
  use Mimic
  use Oban.Testing, repo: Atlas.Repo

  import Atlas.AutomationsFixtures
  import Atlas.OrbitFixtures

  alias Atlas.Audit.Activity
  alias Atlas.Automations.Executor
  alias Atlas.Automations.Interface
  alias Atlas.Automations.Run
  alias Atlas.Connections
  alias Atlas.Connections.Connection
  alias Atlas.MCP.Server
  alias Atlas.Orbit
  alias Atlas.Orbit.Thread
  alias Atlas.Signals
  alias Atlas.Signals.Polling
  alias Atlas.Signals.Signal
  alias Atlas.Signals.Source
  alias Atlas.Signals.Workers.PollSource

  setup do
    actor = user_fixture(["automation:write", "accounts:read"])
    %{actor: actor}
  end

  test "Gmail requires separate consent and never falls back to another person's grant", %{actor: actor} do
    connect(actor, "google", ["https://www.googleapis.com/auth/calendar.readonly"])
    connect(user_fixture([]), "google", [Polling.scope("gmail")])
    assert {:error, :polling_authorization_required} = create_source(actor, "gmail")
    refute Repo.exists?(Source)
  end

  test "successful and rejected MCP source calls keep personal predicates out of shared audits", %{actor: actor} do
    connect(actor, "google", [Polling.scope("gmail")])
    {_, revision} = workflow_fixture(actor)
    conn = %{assigns: %{current_user: actor, audit_interface: "mcp"}}

    attrs = %{
      "name" => "Personal monitoring",
      "revision_id" => revision.id,
      "reader_ids" => [],
      "required_scopes" => [],
      "polling" => %{
        "provider" => "gmail",
        "query" => "from:lawyer@example.org subject:private-acquisition",
        "interval_seconds" => 60,
        "subjects" => ["private-account"],
        "topics" => ["private-topic"]
      }
    }

    for arguments <- [attrs, Map.put(attrs, "revision_id", "invalid")] do
      Server.handle_message(conn, %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 1,
        "params" => %{"name" => "create_signal_source", "arguments" => arguments}
      })
    end

    calls = Repo.all(from a in Activity, where: a.action == "mcp.tool_called")
    assert length(calls) == 2
    assert Enum.sort(Enum.map(calls, & &1.metadata["status"])) == ["error", "ok"]
    assert Enum.all?(calls, &(&1.metadata["arguments"] == %{}))
    refute inspect(Repo.all(Activity)) =~ "private-"
  end

  test "Gmail pages survive restarts, deduplicate, and open one policy-bound conversation", %{actor: actor} do
    connect(actor, "google", [Polling.scope("gmail")])
    {:ok, source} = create_source(actor, "gmail")
    source = earlier(source)
    at = DateTime.to_unix(DateTime.utc_now(), :millisecond) - 100_000

    plug = fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer personal-token"]

      body =
        case conn.request_path do
          "/gmail/v1/users/me/messages" ->
            assert conn.params["q"] =~ "label:support"
            assert conn.params["maxResults"] == "10"

            if conn.params["pageToken"] == "next-private-page",
              do: %{"messages" => [%{"id" => "message_b"}]},
              else: %{"messages" => [%{"id" => "message_a"}], "nextPageToken" => "next-private-page"}

          "/gmail/v1/users/me/messages/" <> id ->
            assert conn.params["format"] == "metadata"
            assert {"metadataHeaders", "Subject"} in Enum.to_list(URI.query_decoder(conn.query_string))

            %{
              "id" => id,
              "threadId" => "customer_thread",
              "internalDate" => to_string(at),
              "snippet" => "Can we use the documented remote cache with our CI?",
              "payload" => %{"headers" => [%{"name" => "Subject", "value" => "Remote cache question"}]}
            }
        end

      Req.Test.json(conn, body)
    end

    http(plug)
    assert :ok = Polling.schedule_due()
    refute_enqueued(worker: PollSource)
    assert {:ok, _} = Signals.set_enabled(actor, source.id, true)
    assert :ok = Polling.schedule_due()
    assert_enqueued(worker: PollSource, args: %{"source_id" => source.id})
    assert {:snooze, 1} = perform_job(PollSource, %{"source_id" => source.id})
    assert Repo.aggregate(Signal, :count) == 1
    assert :ok = perform_job(PollSource, %{"source_id" => source.id})
    assert Repo.aggregate(Signal, :count) == 2
    assert {:snooze, 1} = perform_job(PollSource, %{"source_id" => source.id})
    assert Repo.aggregate(Signal, :count) == 2

    for signal <- Repo.all(Signal) do
      assert {:ok, _} = Executor.advance(signal.execution_id)
      assert {:ok, :finished} = Executor.advance(signal.execution_id)
      assert Repo.get!(Run, signal.execution_id).status == "succeeded"
    end

    threads = Repo.all(Thread)
    assert [thread] = threads
    assert {:ok, thread} = Orbit.fetch(actor, thread.id)
    {messages, _} = Orbit.list_messages(thread)
    assert Enum.any?(messages, &String.contains?(&1.body, "documented remote cache"))

    assert {:ok, result} = Interface.execute(:list_signal_sources, actor, %{})
    refute JSON.encode!(result) =~ "next-private-page"
    refute JSON.encode!(result) =~ "personal-token"
    refute JSON.encode!(result) =~ "label:support"

    [[config, state]] =
      Repo.query!("SELECT poll_config, poll_state FROM signal_sources WHERE id = $1", [Ecto.UUID.dump!(source.id)]).rows

    refute config =~ "label:support"
    refute state =~ "next-private-page"
  end

  test "Gmail starts no detail reads after a pause or disconnect during listing", %{actor: actor} do
    for stop <- [:pause, :disconnect] do
      connect(actor, "google", [Polling.scope("gmail")])
      {:ok, source} = create_source(actor, "gmail")
      {:ok, _} = Signals.set_enabled(actor, source.id, true)

      http(fn conn ->
        assert conn.request_path == "/gmail/v1/users/me/messages"

        case stop do
          :pause -> Signals.set_enabled(actor, source.id, false)
          :disconnect -> Connections.disconnect(actor, "google")
        end

        Req.Test.json(conn, %{"messages" => [%{"id" => "private_message"}]})
      end)

      assert {:error, _} = perform_job(PollSource, %{"source_id" => source.id})
      assert Repo.get!(Source, source.id).poll_state == nil
      refute Repo.exists?(Signal)
    end
  end

  test "Slack uses the personal token and exact UTC window, including long Unicode messages", %{actor: actor} do
    connect(actor, "slack", ["search:read"])
    {:ok, source} = create_source(actor, "slack")
    source = earlier(source)
    {:ok, _} = Signals.set_enabled(actor, source.id, true)
    now = DateTime.to_unix(DateTime.utc_now())
    body = String.duplicate("問", 3000)

    http(fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      assert conn.params["sort"] == "timestamp"
      assert conn.params["sort_dir"] == "asc"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer personal-token"]
      matches = Enum.map([now - 900, now - 100, now + 100], &slack_message(&1, body))

      Req.Test.json(conn, %{
        "ok" => true,
        "messages" => %{"matches" => matches, "paging" => %{"page" => 1, "pages" => 1}}
      })
    end)

    assert :ok = perform_job(PollSource, %{"source_id" => source.id})
    assert [signal] = Repo.all(Signal)
    assert {:ok, protected} = Signals.get(actor, signal.id)
    assert protected.envelope["summary"] == String.duplicate("問", 500)
    assert protected.envelope["data"]["excerpt"] == String.duplicate("問", 1000)
    assert :ok = perform_job(PollSource, %{"source_id" => source.id})
    assert Repo.aggregate(Signal, :count) == 1
  end

  test "Slack cursors preserve surviving matches when an earlier page loses a message", %{actor: actor} do
    connect(actor, "slack", ["search:read"])
    {:ok, source} = create_source(actor, "slack")

    source
    |> Ecto.Changeset.change(inserted_at: DateTime.add(DateTime.utc_now(), -86_400, :second))
    |> Repo.update!()

    {:ok, _} = Signals.set_enabled(actor, source.id, true)
    start = DateTime.to_unix(DateTime.utc_now()) - 70_000
    timestamps = Enum.map(1..201, &(start + &1 * 100))

    http(fn conn ->
      conn = Plug.Conn.fetch_query_params(conn)
      refute Map.has_key?(conn.params, "page")

      remaining =
        case conn.params["cursor"] do
          "*" -> timestamps
          cursor -> Enum.filter(tl(timestamps), &(&1 > String.to_integer(cursor)))
        end

      page = Enum.take(remaining, 100)
      cursor = if length(remaining) > 100, do: to_string(List.last(page)), else: ""

      Req.Test.json(conn, %{
        "ok" => true,
        "messages" => %{"matches" => Enum.map(page, &slack_message(&1, "Message #{&1}"))},
        "response_metadata" => %{"next_cursor" => cursor}
      })
    end)

    assert {:snooze, 1} = perform_job(PollSource, %{"source_id" => source.id})
    assert {:snooze, 1} = perform_job(PollSource, %{"source_id" => source.id})
    assert :ok = perform_job(PollSource, %{"source_id" => source.id})
    assert Repo.aggregate(Signal, :count) == 201

    for timestamp <- timestamps do
      assert Repo.exists?(from s in Signal, where: like(s.external_id, ^"slack:C123:#{timestamp}.000123:%"))
    end
  end

  test "pausing or disconnecting during a fetch cannot admit the fetched evidence", %{actor: actor} do
    for stop <- [:pause, :disconnect] do
      connect(actor, "slack", ["search:read"])
      {:ok, source} = create_source(actor, "slack")
      source = earlier(source)
      {:ok, _} = Signals.set_enabled(actor, source.id, true)

      http(fn conn ->
        case stop do
          :pause -> Signals.set_enabled(actor, source.id, false)
          :disconnect -> Connections.disconnect(actor, "slack")
        end

        Req.Test.json(conn, %{
          "ok" => true,
          "messages" => %{
            "matches" => [slack_message(DateTime.to_unix(DateTime.utc_now()) - 30, "private evidence")],
            "paging" => %{"page" => 1, "pages" => 1}
          }
        })
      end)

      perform_job(PollSource, %{"source_id" => source.id})
      assert Repo.get!(Source, source.id).poll_state == nil
      refute Repo.exists?(Signal)
    end
  end

  test "reconnecting to another external identity cannot silently retarget a monitor", %{actor: actor} do
    connection = connect(actor, "slack", ["search:read"])
    {:ok, source} = create_source(actor, "slack")
    {:ok, _} = Signals.set_enabled(actor, source.id, true)
    connection |> Ecto.Changeset.change(provider_user_id: "different-person") |> Repo.update!()
    stub(Req, :request, fn _ -> flunk("A bound monitor must not fetch another account") end)
    assert {:error, "authorization_required"} = perform_job(PollSource, %{"source_id" => source.id})
    assert Repo.get!(Source, source.id).poll_state == nil
    refute Repo.exists?(Signal)
  end

  test "rate limits and malformed responses preserve the checkpoint and recover", %{actor: actor} do
    connect(actor, "slack", ["search:read"])
    {:ok, source} = create_source(actor, "slack")
    {:ok, _} = Signals.set_enabled(actor, source.id, true)
    http(fn conn -> conn |> Plug.Conn.put_resp_header("retry-after", "43") |> Plug.Conn.send_resp(429, "") end)
    assert {:snooze, 43} = perform_job(PollSource, %{"source_id" => source.id})
    assert Repo.get!(Source, source.id).poll_state == nil
    assert Repo.get!(Source, source.id).poll_error == "rate_limited"

    http(fn conn ->
      Req.Test.json(conn, %{
        "ok" => true,
        "messages" => %{"matches" => [%{"text" => "malformed"}], "paging" => %{"page" => 1, "pages" => 1}}
      })
    end)

    assert {:error, "provider_unavailable"} = perform_job(PollSource, %{"source_id" => source.id})
    assert Repo.get!(Source, source.id).poll_state == nil

    http(fn conn ->
      Req.Test.json(conn, %{"ok" => true, "messages" => %{"matches" => [], "paging" => %{"page" => 1, "pages" => 0}}})
    end)

    assert :ok = perform_job(PollSource, %{"source_id" => source.id})
    assert Repo.get!(Source, source.id).poll_error == nil
  end

  defp create_source(actor, provider) do
    {_, revision} =
      workflow_fixture(actor, [
        %{
          "id" => "triage",
          "behavior" => "signals.decide@1",
          "inputs" => %{
            "signal_id" => %{"$ref" => "input.signal_id"},
            "action" => "opened",
            "priority" => "today",
            "reason" => "Customer question"
          }
        }
      ])

    Signals.create_source(actor, %{
      "name" => "Customer questions",
      "revision_id" => revision.id,
      "reader_ids" => [],
      "required_scopes" => ["accounts:read"],
      "polling" => %{"provider" => provider, "query" => "label:support", "interval_seconds" => 60}
    })
  end

  defp connect(actor, provider, scopes) do
    %Connection{user_id: actor.id, provider: provider}
    |> Connection.changeset(%{
      provider_user_id: "person",
      workspace_id: "workspace",
      account_name: "Person",
      access_token: "personal-token",
      scopes: scopes
    })
    |> Repo.insert!(on_conflict: :replace_all, conflict_target: [:user_id, :provider])
  end

  defp earlier(source),
    do: source |> Ecto.Changeset.change(inserted_at: DateTime.add(DateTime.utc_now(), -600, :second)) |> Repo.update!()

  defp slack_message(at, body), do: %{"ts" => "#{at}.000123", "text" => body, "channel" => %{"id" => "C123"}}

  defp http(plug), do: stub(Req, :request, fn opts -> Req.request(Req.new(Keyword.put(opts, :plug, plug)), []) end)
end
