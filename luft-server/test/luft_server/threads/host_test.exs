defmodule LuftServer.Threads.HostTest do
  use ExUnit.Case, async: false

  import Ecto.Query
  import Plug.Conn

  alias Ecto.Adapters.SQL.Sandbox
  alias LuftServer.Agents.Bucket
  alias LuftServer.Agents.Kind
  alias LuftServer.Agents.Lease
  alias LuftServer.Repo
  alias LuftServer.RunnerCredentials.Binding
  alias LuftServer.Sessions
  alias LuftServer.Threads.Clients
  alias LuftServer.Threads.Host
  alias LuftServer.Threads.Message
  alias LuftServer.Threads.Run
  alias LuftServer.Threads.Runner
  alias LuftServer.Threads.Tasks
  alias LuftServer.Threads.Thread

  setup do
    owner = Sandbox.start_owner!(Repo, shared: true)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    LuftServer.FakeOpenAI.connect(11)
    :ok
  end

  test "idle acknowledgement carries the original runner token and exits normally" do
    host = start_supervised!({Host, {Ecto.UUID.generate(), 1}})
    ref = Process.monitor(host)
    token = {"session", 1, 7}
    assert :ok = Host.stop_if_idle(host, self(), token)
    assert_receive {Kind, :idle, ^host, ^token}
    assert_receive {:DOWN, ^ref, :process, ^host, :normal}
  end

  test "drain exits for handoff without needing a model session" do
    host = start_supervised!({Host, {Ecto.UUID.generate(), 1}})
    ref = Process.monitor(host)
    assert :ok = Host.drain(host)
    assert_receive {:DOWN, ^ref, :process, ^host, {:shutdown, :drain}}
  end

  test "question notifier drains only ask_user waits" do
    assert :ok =
             Host.publish("session", {:waiting, %{tool_calls: [%{tool: "Bash"}]}},
               host: self(),
               run_id: "run"
             )

    refute_received {:question_waiting, _}

    assert :ok =
             Host.publish("session", {:waiting, %{tool_calls: [%{tool: "ask_user"}]}},
               host: self(),
               run_id: "run"
             )

    assert_received {:question_waiting, "run"}
  end

  test "real host runs buffered inference and persists an encrypted durable reply" do
    Req.Test.set_req_test_to_shared()
    start_supervised!({Task.Supervisor, name: Tasks})
    {thread, run, epoch} = queued_runner_run()
    test = self()
    stub_runtime(test)

    reasoning = %{
      type: "reasoning",
      id: "rs_1",
      summary: [],
      encrypted_content: "opaque reasoning"
    }

    LuftServer.FakeOpenAI.stub(
      respond: fn request, conn ->
        send(test, {:inference, request})

        event = %{
          type: "response.completed",
          response: %{
            id: "response",
            model: "test-model",
            status: "completed",
            output: [
              reasoning,
              %{
                type: "message",
                content: [
                  %{
                    type: "output_text",
                    text: Jason.encode!(%{reply: "durable hello", suggestions: []})
                  }
                ]
              }
            ]
          }
        }

        send_resp(conn, 200, "data: " <> Jason.encode!(event) <> "\n\n")
      end
    )

    host = start_supervised!({Host, {thread.id, epoch}})

    request =
      receive do
        {:inference, request} -> request
      after
        5_000 ->
          flunk("Host did not infer: #{inspect({Repo.get!(Run, run.id), :sys.get_state(host)})}")
      end

    assert request["model"] == "test-model"
    names = Enum.map(request["tools"], & &1["name"])

    for name <-
          ~w(inspect_behaviors validate_behavior_release propose_behavior_release inspect_behavior_releases promote_behavior_release),
        do: assert(name in names)

    refute "approve_behavior_release" in names
    eventually(fn -> Repo.get!(Run, run.id).status == "succeeded" end, 500)

    reply = Repo.one!(from m in Message, where: m.thread_id == ^thread.id and m.kind == "agent")
    assert reply.body == "durable hello"
    assert {:ok, keys} = Bucket.list([], "agents/thread/#{thread.id}/", nil)
    assert keys != []

    for key <- keys do
      assert {:ok, bytes} = Bucket.get([], key)
      assert :binary.match(bytes, "durable hello") == :nomatch
    end

    message =
      Repo.insert!(%Message{
        thread_id: thread.id,
        position: reply.position + 1,
        kind: "human",
        author_id: thread.owner_id,
        author_session_id: thread.owner_session_id,
        body: "are you there?"
      })

    followup = Repo.insert!(%Run{thread_id: thread.id, message_id: message.id, status: "queued"})
    send(host, :work)
    assert_receive {:inference, continued}, 5_000
    assert Jason.decode!(Jason.encode!(reasoning)) in continued["input"]
    assert Enum.any?(continued["input"], &(&1["role"] == "assistant"))

    assert List.last(continued["input"])["content"] == [
             %{"type" => "input_text", "text" => "are you there?"}
           ]

    eventually(fn -> Repo.get!(Run, followup.id).status == "succeeded" end, 500)
    Host.drain(host)
  end

  test "an archived workspace retries capacity refusal and completes when room returns" do
    Req.Test.set_req_test_to_shared()
    start_supervised!({Task.Supervisor, name: Tasks})
    {thread, run, epoch} = queued_runner_run()
    sandbox_id = Ecto.UUID.generate()

    thread =
      Repo.update!(Ecto.Changeset.change(thread, runner_id: nil, sandbox_id: sandbox_id))

    attempts = start_supervised!({Agent, fn -> 0 end})

    stub_runtime(self(), false, 0, fn conn ->
      {:ok, body, conn} = read_body(conn)

      case Jason.decode!(body) do
        %{"operation" => "show", "sandbox_id" => ^sandbox_id} ->
          Req.Test.json(conn, %{result: %{id: sandbox_id, account_id: 21, state: "archived"}})

        %{"operation" => operation, "sandbox_id" => ^sandbox_id}
        when operation in ["acquire", "renew"] ->
          case Agent.get_and_update(attempts, &{&1, &1 + 1}) do
            0 ->
              conn |> put_status(409) |> Req.Test.json(%{code: "no_capacity"})

            _ ->
              Req.Test.json(conn, %{result: %{id: sandbox_id, account_id: 21, state: "running"}})
          end

        %{"operation" => "release", "sandbox_id" => ^sandbox_id} ->
          Req.Test.json(conn, %{result: %{}})
      end
    end)

    host = start_supervised!({Host, {thread.id, epoch}})
    assert_receive {:inference, _}, 10_000
    eventually(fn -> Repo.get!(Run, run.id).status == "succeeded" end, 500)
    assert Repo.get!(Thread, thread.id).sandbox_id == sandbox_id
    reply = Repo.one!(from m in Message, where: m.thread_id == ^thread.id and m.kind == "agent")
    assert reply.body == "durable hello"
    Host.drain(host)
  end

  test "drain kills the linked model and resumes the same journal under a new lease epoch" do
    Req.Test.set_req_test_to_shared()
    start_supervised!({Task.Supervisor, name: Tasks})
    {thread, run, epoch} = queued_runner_run()
    stub_runtime(self(), true)
    host = start_supervised!({Host, {thread.id, epoch}})
    assert_receive {:inference, first}, 5_000
    assert_receive {:blocked_inference, model}
    model_ref = Process.monitor(model)
    host_ref = Process.monitor(host)
    Host.drain(host)
    assert_receive {:DOWN, ^host_ref, :process, ^host, {:shutdown, :drain}}, 5_000
    assert_receive {:DOWN, ^model_ref, :process, ^model, _}, 5_000
    assert Repo.get!(Run, run.id).status == "running"
    :ok = Lease.release(thread.id, epoch)
    [%{epoch: next_epoch}] = Lease.claim(Ecto.UUID.generate(), 1)
    assert next_epoch > epoch

    stub_runtime(self())
    replacement = start_supervised!({Host, {thread.id, next_epoch}})
    assert_receive {:inference, resumed}, 5_000
    assert resumed["input"] == first["input"]
    assert resumed["instructions"] == first["instructions"]
    eventually(fn -> Repo.get!(Run, run.id).status == "succeeded" end, 500)
    assert Repo.get!(Run, run.id).attempt == next_epoch

    assert Repo.aggregate(
             from(m in Message, where: m.thread_id == ^thread.id and m.kind == "agent"),
             :count
           ) == 1

    Host.drain(replacement)
  end

  test "client tool validation bounds names and never exposes another author's tools" do
    assert {:error, :invalid_tools} =
             Clients.validate([
               %{"name" => "Bad", "description" => "bad", "parameters" => %{"type" => "object"}}
             ])

    {:ok, tools} =
      Clients.validate([
        %{
          "name" => "set_theme",
          "description" => "Set theme",
          "parameters" => %{"type" => "object"}
        }
      ])

    thread = Ecto.UUID.generate()
    assert {:ok, _} = Clients.join(thread, 11, tools)
    eventually(fn -> Clients.tools(thread, 11) == tools end)
    assert Clients.tools(thread, 12) == []
    assert {:error, _} = Clients.call(thread, 12, "set_theme", %{}, 1)
  end

  test "assembled tools reserve actual host and client tools before catalog fallback" do
    Req.Test.set_req_test_to_shared()
    start_supervised!({Task.Supervisor, name: Tasks})
    {thread, run, epoch} = queued_runner_run()
    stub_runtime(self())
    host = start_supervised!({Host, {thread.id, epoch}})
    assert_receive {:inference, baseline}, 5_000
    eventually(fn -> Repo.get!(Run, run.id).status == "succeeded" end, 500)
    Host.drain(host)
    reserved = length(baseline["tools"])

    for count <- [64 - reserved, 65 - reserved, 65] do
      {thread, run, epoch} = queued_runner_run()

      {:ok, client} =
        Clients.validate([
          %{
            "name" => "set_theme",
            "description" => "Set theme",
            "parameters" => %{"type" => "object"}
          }
        ])

      assert {:ok, _} = Clients.join(thread.id, 11, client)
      eventually(fn -> Clients.tools(thread.id, 11) == client end)
      stub_runtime(self(), false, count - 1)
      host = start_supervised!({Host, {thread.id, epoch}}, id: thread.id)
      assert_receive {:inference, request}, 5_000
      names = Enum.map(request["tools"], & &1["name"])
      assert length(names) <= 64
      assert "client_set_theme" in names

      if count + reserved <= 64 do
        assert length(names) == 64
        refute "mcp_search_tools" in names
      else
        assert "mcp_search_tools" in names
        assert "mcp_call_tool" in names
      end

      eventually(fn -> Repo.get!(Run, run.id).status == "succeeded" end, 500)
      Host.drain(host)
    end
  end

  defp queued_runner_run do
    {:ok, _, session} =
      Sessions.create(%{
        claims: %{"sub" => "11"},
        tokens: %{
          "access_token" => "owner-token",
          "refresh_token" => "refresh",
          "expires_in" => 3600
        }
      })

    runner =
      Repo.insert!(%Runner{
        user_id: 11,
        name: "Test runner",
        platform: "macos",
        token_hash: :crypto.strong_rand_bytes(32),
        capabilities: %{"new_project_folder" => "/shared", "terminal" => false}
      })

    Repo.insert!(%Binding{
      runner_id: runner.id,
      session_id: session.id
    })

    thread =
      Repo.insert!(%Thread{
        account_id: 21,
        account_handle: "team",
        owner_id: 11,
        owner_session_id: session.id,
        runner_id: runner.id,
        request_id: Ecto.UUID.generate(),
        request_hash: <<1>>,
        title: "Host test",
        goal: "hello",
        provider: "chatgpt",
        model: "test-model"
      })

    message =
      Repo.insert!(%Message{
        thread_id: thread.id,
        position: 1,
        kind: "human",
        author_id: 11,
        author_session_id: session.id,
        body: "hello"
      })

    run = Repo.insert!(%Run{thread_id: thread.id, message_id: message.id, status: "queued"})
    Lease.want(thread.id, "thread")
    [%{epoch: epoch}] = Lease.claim(Ecto.UUID.generate(), 1)
    {thread, run, epoch}
  end

  defp stub_runtime(test, block \\ false, catalog_size \\ 0, workspace \\ nil) do
    Req.Test.stub(LuftServer.Tuist, fn conn ->
      assert get_req_header(conn, "authorization") == ["Bearer owner-token"]

      case conn.request_path do
        "/api/accounts/team/luft-context" ->
          Req.Test.json(conn, %{
            user_id: 11,
            account_id: 21,
            organization_id: 21,
            can_create_threads: true,
            people: [%{id: 11, handle: "owner", active: true}]
          })

        "/api/me/mcp-servers/transport" ->
          Req.Test.json(conn, %{builtin_mcp_allowed: true, servers: []})

        "/api/accounts/team/workspace-capabilities" ->
          workspace.(conn)

        "/mcp" ->
          {:ok, body, conn} = read_body(conn)
          rpc = Jason.decode!(body)

          result =
            case rpc["method"] do
              "initialize" ->
                %{
                  protocolVersion: "2025-06-18",
                  capabilities: %{},
                  serverInfo: %{name: "test", version: "1"}
                }

              "notifications/initialized" ->
                %{}

              "tools/list" ->
                %{
                  tools:
                    for(
                      n <- Enum.take(1..100, catalog_size),
                      do: %{
                        name: "read_#{n}",
                        description: "Read #{n}",
                        inputSchema: %{type: "object"},
                        annotations: %{readOnlyHint: true}
                      }
                    )
                }
            end

          Req.Test.json(conn, %{jsonrpc: "2.0", id: rpc["id"], result: result})
      end
    end)

    LuftServer.FakeOpenAI.stub(
      respond: fn request ->
        send(test, {:inference, request})

        if block do
          send(test, {:blocked_inference, self()})

          receive do
            :release -> :ok
          end
        end

        Jason.encode!(%{reply: "durable hello", suggestions: []})
      end
    )
  end

  defp eventually(fun, tries \\ 100) do
    if fun.() do
      :ok
    else
      if tries == 0, do: flunk("condition never held")
      Process.sleep(10)
      eventually(fun, tries - 1)
    end
  end
end
