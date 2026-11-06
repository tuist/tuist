defmodule Tuist.Threads.WorkerTest do
  # Condukt owns its session and tool processes. A shared SQL owner lets this
  # integration test exercise those real processes, not mock the agent loop.
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Accounts.AISubscriptions
  alias Tuist.Accounts.MCPServers
  alias Tuist.OAuth2.PinnedHTTP
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.Threads
  alias Tuist.Threads.Approval
  alias Tuist.Threads.Provider
  alias Tuist.Threads.Run
  alias Tuist.Threads.Shipping
  alias Tuist.Threads.ToolCall
  alias Tuist.Threads.Worker
  alias TuistTestSupport.Fixtures.AccountsFixtures

  # Supervised Condukt tool tasks do not retain the test's caller chain.
  # This suite already runs synchronously with the shared SQL sandbox.
  setup :set_mimic_global

  setup do
    stub(Provider, :validate_model, fn _, "chatgpt", "selected-model" -> :ok end)
    stub(MCPServers, :list, fn _ -> [] end)
    :ok
  end

  test "a durable job runs the real model/tool loop and persists its final reply" do
    user = AccountsFixtures.user_fixture()
    calls = start_supervised!({Agent, fn -> 0 end})
    server_id = Ecto.UUID.generate()
    stub(MCPServers, :list, fn _ -> [%{id: server_id, url: "https://mcp.example.com", connected: true}] end)

    stub(MCPServers, :credentials, fn _, ^server_id ->
      {:ok, %{url: "https://mcp.example.com", access_token: "secret"}}
    end)

    stub(SSRFGuard, :pin, fn _ -> {:ok, "https://93.184.216.34", "mcp.example.com"} end)

    stub(PinnedHTTP, :request, fn "POST", _, opts ->
      envelope = JSON.decode!(opts[:body])

      result =
        case envelope["method"] do
          "initialize" -> %{protocolVersion: "2025-06-18", capabilities: %{tools: %{}}}
          "notifications/initialized" -> %{}
          "tools/list" -> %{tools: [%{name: "lookup", inputSchema: %{type: "object"}}]}
          "tools/call" -> %{content: [%{type: "text", text: "Remote cache evidence"}]}
        end

      {:ok, %{status: 200, headers: [], body: JSON.encode!(%{jsonrpc: "2.0", id: envelope["id"], result: result})}}
    end)

    plug = fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      request = JSON.decode!(raw)
      turn = Agent.get_and_update(calls, &{&1, &1 + 1})

      message =
        case turn do
          0 ->
            assert Enum.any?(request["tools"], &(&1["function"]["name"] == "set_thread_name"))
            remote = Enum.find(request["tools"], &String.starts_with?(&1["function"]["name"], "mcp_"))

            %{
              role: "assistant",
              content: nil,
              reasoning_details: [
                %{format: "tuist-codex-v1", item: %{type: "reasoning", encrypted_content: "opaque-state"}}
              ],
              tool_calls: [
                %{
                  id: "name-call",
                  type: "function",
                  function: %{name: "set_thread_name", arguments: ~s({"name":"Understand the cache"})}
                },
                %{
                  id: "remote-call",
                  type: "function",
                  function: %{name: remote["function"]["name"], arguments: "{}"}
                }
              ]
            }

          1 ->
            assert Enum.any?(request["messages"], &(&1["role"] == "tool" and &1["tool_call_id"] == "name-call"))
            assert Enum.any?(request["messages"], &(&1["role"] == "tool" and &1["content"] =~ "Remote cache evidence"))

            assert Enum.any?(request["messages"], fn message ->
                     Enum.any?(message["reasoning_details"] || [], fn detail ->
                       detail["format"] == "tuist-codex-v1" and
                         detail["item"] == %{"type" => "reasoning", "encrypted_content" => "opaque-state"}
                     end)
                   end)

            %{
              role: "assistant",
              content: JSON.encode!(%{reply: "Here is the explanation.", suggestions: ["Explain invalidation"]})
            }
        end

      response = %{
        id: "completion-#{turn}",
        object: "chat.completion",
        created: 0,
        model: Provider.default_model(:chatgpt),
        choices: [%{index: 0, message: message, finish_reason: if(turn == 0, do: "tool_calls", else: "stop")}],
        usage: %{prompt_tokens: 10, completion_tokens: 10, total_tokens: 20}
      }

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, JSON.encode!(response))
    end

    stub(AISubscriptions, :list, fn _ -> [%{provider: :chatgpt, connected: true}] end)
    {:ok, opts} = Provider.client_opts(user, %{provider: "chatgpt", model: "selected-model"})

    stub(Provider, :client_opts, fn _, thread ->
      assert thread.model == "selected-model"
      {:ok, Keyword.put(opts, :llm_request_options, req_http_options: [plug: plug])}
    end)

    assert {:ok, thread} =
             Threads.create(user, user.account, request("Explain caching"))

    run = Repo.one!(Run)
    assert :ok = Worker.perform(%Oban.Job{args: %{"run_id" => run.id}})
    assert {:ok, fresh} = Threads.get(user, user.account, thread.id)
    assert fresh.title == "Understand the cache"
    assert fresh.agent_status == "idle"
    assert List.last(fresh.messages).body == "Here is the explanation."
    assert List.last(fresh.messages).suggestions == ["Explain invalidation"]
    assert Repo.reload!(run).status == "succeeded"
    assert Repo.reload!(run).checkpoint == nil
    assert %{status: "completed", result: result} = Repo.one!(ToolCall)
    assert result =~ "Remote cache evidence"
    assert Agent.get(calls, & &1) == 2
  end

  test "an unreadable checkpoint never silently starts a fresh model conversation" do
    user = AccountsFixtures.user_fixture()
    stub(Provider, :client_opts, fn _, _ -> {:ok, []} end)

    assert {:ok, thread} =
             Threads.create(user, user.account, request("Continue work"))

    run = Repo.one!(Run)
    Repo.update!(Ecto.Changeset.change(run, checkpoint: "unreadable snapshot"))
    reject(Provider, :client_opts, 2)

    assert :ok = Worker.perform(%Oban.Job{args: %{"run_id" => run.id}})
    assert Repo.reload!(run).status == "failed"
    assert {:ok, fresh} = Threads.get(user, user.account, thread.id)
    assert fresh.agent_status == "failed"
    refute Enum.any?(fresh.messages, &(&1.kind == "agent"))
  end

  test "each model dispatch refreshes only the bound provider and never falls back" do
    user = AccountsFixtures.user_fixture()
    {:ok, _} = Threads.create(user, user.account, request("Inspect"))
    {:ok, {run, _}} = Threads.claim(Repo.one!(Run).id)

    conn = fn ->
      :post
      |> Plug.Test.conn("/chat/completions", JSON.encode!(%{"model" => "forged-model", "messages" => []}))
      |> Plug.Conn.put_private(:thread_model_fence, {run.id, run.attempt, self()})
    end

    first_token =
      "e30." <>
        Base.url_encode64(JSON.encode!(%{"https://api.openai.com/auth" => %{"chatgpt_account_id" => "personal"}}),
          padding: false
        ) <> ".sig"

    second_token = first_token <> "2"

    expect(AISubscriptions, :credentials, fn actor, :chatgpt ->
      assert actor.id == user.id
      {:ok, %{access_token: first_token}}
    end)

    expect(Req, :post, fn opts ->
      assert {"authorization", "Bearer " <> first_token} in opts[:headers]
      assert opts[:json]["model"] == "selected-model"
      {:ok, %{status: 429, body: %{}}}
    end)

    assert %{status: 429} = Provider.call(conn.(), user_id: user.id, model: "selected-model")

    expect(AISubscriptions, :credentials, fn _, :chatgpt -> {:ok, %{access_token: second_token}} end)

    expect(Req, :post, fn opts ->
      assert {"authorization", "Bearer " <> second_token} in opts[:headers]
      assert opts[:json]["model"] == "selected-model"

      {:ok,
       %{
         status: 200,
         body: "data: " <> JSON.encode!(%{type: "response.completed", response: %{id: "done", output: []}}) <> "\n\n"
       }}
    end)

    assert %{status: 200} = Provider.call(conn.(), user_id: user.id, model: "selected-model")
  end

  test "ownership revoked during credential refresh prevents upstream inference" do
    user = AccountsFixtures.user_fixture()
    {:ok, thread} = Threads.create(user, user.account, request("Inspect"))
    {:ok, {run, _}} = Threads.claim(Repo.one!(Run).id)

    conn =
      :post
      |> Plug.Test.conn("/chat/completions", JSON.encode!(%{"messages" => []}))
      |> Plug.Conn.put_private(:thread_model_fence, {run.id, run.attempt, self()})

    expect(AISubscriptions, :credentials, fn _, :chatgpt ->
      {:ok, _} = Threads.archive(user, user.account, thread.id, "archived")
      {:ok, %{access_token: "never-dispatched"}}
    end)

    reject(Provider, :complete, 3)
    assert %{status: 409} = Provider.call(conn, user_id: user.id, model: "selected-model")
  end

  test "model-process notifications cannot postpone the lease heartbeat" do
    user = AccountsFixtures.user_fixture()
    stub(Provider, :client_opts, fn _, _ -> {:ok, []} end)
    {:ok, _} = Threads.create(user, user.account, request("Keep working"))
    run = Repo.one!(Run)
    test = self()
    old_heartbeat = DateTime.add(DateTime.utc_now(:second), -30)

    stub(Provider, :client_opts, fn _, _ ->
      Repo.update!(Ecto.Changeset.change(Repo.get!(Run, run.id), heartbeat_at: old_heartbeat))
      send(test, {:model_waiting, self()})

      receive do
        :complete -> {:error, :disconnected}
      end
    end)

    stub(Threads, :heartbeat, fn current ->
      result = Mimic.call_original(Threads, :heartbeat, [current])
      send(test, {:heartbeat, result, Repo.reload!(current).heartbeat_at})
      result
    end)

    model = spawn(fn -> receive do: (:stop -> :ok) end)
    worker = Task.async(fn -> Worker.perform(%Oban.Job{args: %{"run_id" => run.id}}) end)
    {:ok, timer} = :timer.send_interval(100, worker.pid, {:thread_model_process, model})

    try do
      assert_receive {:model_waiting, inference}, 5_000
      # The old receive-after implementation never reaches renewal while these
      # notifications keep arriving, even though the model remains active.
      assert_receive {:heartbeat, :ok, renewed}, 10_000
      assert DateTime.after?(renewed, old_heartbeat)
      assert Threads.owns_run?(run.id, 1)
      send(inference, :complete)
      assert :ok = Task.await(worker, 5_000)
      assert Repo.reload!(run).status == "failed"
      refute Process.alive?(model)
    after
      :timer.cancel(timer)
      Task.shutdown(worker, :brutal_kill)
      Process.exit(model, :kill)
    end
  end

  test "Ship receives the claimed attempt and an uncertain result is never replayed" do
    user = AccountsFixtures.user_fixture()
    stub(Provider, :client_opts, fn _, _ -> {:ok, []} end)
    {:ok, thread} = Threads.create(user, user.account, request("Ship the review"))

    approval =
      Repo.insert!(%Approval{
        thread_id: thread.id,
        account_id: user.account.id,
        request_id: Ecto.UUID.generate(),
        repository: "example/repo",
        head_sha: String.duplicate("a", 40),
        diff: "+ reviewed",
        target_branch: "threads/example",
        mode: :branch,
        status: :approved,
        approved_by_id: user.id,
        approved_at: DateTime.utc_now(:second)
      })

    run = Repo.update!(Ecto.Changeset.change(Repo.one!(Run), kind: "ship", approval_id: approval.id))
    test = self()

    expect(Shipping, :execute, fn bound_thread, bound_approval, bound_run ->
      send(test, {:ship_attempt, bound_thread.id, bound_approval, bound_run})
      {:error, :shipping_uncertain}
    end)

    assert :ok = Worker.perform(%Oban.Job{args: %{"run_id" => run.id}})
    assert_receive {:ship_attempt, thread_id, bound_approval, bound_run}
    assert thread_id == thread.id
    assert bound_approval.id == approval.id
    assert bound_approval.status == :executing
    assert bound_run.id == run.id
    assert bound_run.attempt == 1
    assert bound_run.status == "running"
    assert Repo.reload!(run).status == "outcome_unknown"
    assert :ok = Threads.recover()
    assert :ok = Worker.perform(%Oban.Job{args: %{"run_id" => run.id}})
    refute_receive {:ship_attempt, _, _, _}
    assert Repo.reload!(run).status == "outcome_unknown"
  end

  defp request(body),
    do: %{"content" => body, "request_id" => Ecto.UUID.generate(), "provider" => "chatgpt", "model" => "selected-model"}
end
