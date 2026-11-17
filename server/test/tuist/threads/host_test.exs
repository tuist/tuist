defmodule Tuist.Threads.HostTest do
  # Condukt owns its session and tool processes. A shared SQL owner lets this
  # integration test exercise those real processes, not mock the agent loop.
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Accounts.AISubscriptions
  alias Tuist.Accounts.MCPServers
  alias Tuist.Agents.Kind
  alias Tuist.Agents.Lease
  alias Tuist.Agents.SessionStore
  alias Tuist.OAuth2.PinnedHTTP
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.Threads
  alias Tuist.Threads.Cards
  alias Tuist.Threads.Host
  alias Tuist.Threads.Provider
  alias Tuist.Threads.Run
  alias Tuist.Threads.ToolCall
  alias TuistTestSupport.Fixtures.AccountsFixtures

  defmodule UnreachableBucket do
    @moduledoc false
    @behaviour Condukt.SessionStore.ObjectStore.Bucket

    @impl true
    def create(_config, _key, _body), do: {:error, :econnrefused}
    @impl true
    def get(_config, _key), do: {:error, :econnrefused}
    @impl true
    def list(_config, _prefix, _start_after), do: {:error, :econnrefused}
    @impl true
    def delete(_config, _key), do: {:error, :econnrefused}
  end

  # Supervised Condukt tool tasks do not retain the test's caller chain.
  # This suite already runs synchronously with the shared SQL sandbox.
  setup :set_mimic_global

  setup do
    stub(Provider, :validate_model, fn _, "chatgpt", "selected-model" -> :ok end)
    stub(MCPServers, :list, fn _ -> [] end)
    # Whether `show_ui` is offered depends on the machine having NSH.
    stub(Cards, :available?, fn -> false end)
    :ok
  end

  test "a card the model writes is checked, refused with what to fix, then shown before the reply" do
    user = AccountsFixtures.user_fixture()
    calls = start_supervised!({Agent, fn -> 0 end})
    stub(Cards, :available?, fn -> true end)

    stub(Cards, :build, fn
      "<Card wide />", "medium" ->
        {:error, "The card's content is 300 points tall at 320 points wide, but its frame is 240."}

      "<Card />", "medium" ->
        {:ok, "compiled card"}
    end)

    show = fn id, tsx ->
      %{
        id: id,
        type: "function",
        function: %{
          name: "show_ui",
          arguments: JSON.encode!(%{tsx: tsx, size: "medium", summary: "TuistKit is slowest."})
        }
      }
    end

    plug = fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      request = JSON.decode!(raw)
      turn = Agent.get_and_update(calls, &{&1, &1 + 1})
      result = fn id -> Enum.find(request["messages"], &(&1["tool_call_id"] == id))["content"] end

      message =
        case turn do
          0 ->
            assert Enum.any?(request["tools"], &(&1["function"]["name"] == "show_ui"))
            %{role: "assistant", content: nil, tool_calls: [show.("too-tall", "<Card wide />")]}

          1 ->
            assert result.("too-tall") =~ "its frame is 240"
            %{role: "assistant", content: nil, tool_calls: [show.("fits", "<Card />")]}

          2 ->
            assert result.("fits") =~ "shown in the conversation"
            %{role: "assistant", content: JSON.encode!(%{reply: "TuistKit misses the cache most.", suggestions: []})}
        end

      response = %{
        id: "completion-#{turn}",
        object: "chat.completion",
        created: 0,
        model: Provider.default_model(:chatgpt),
        choices: [%{index: 0, message: message, finish_reason: if(turn < 2, do: "tool_calls", else: "stop")}],
        usage: %{prompt_tokens: 10, completion_tokens: 10, total_tokens: 20}
      }

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, JSON.encode!(response))
    end

    stub(AISubscriptions, :list, fn _ -> [%{provider: :chatgpt, connected: true}] end)
    {:ok, opts} = Provider.client_opts(user, %{provider: "chatgpt", model: "selected-model"})

    stub(Provider, :client_opts, fn _, _ ->
      {:ok, Keyword.put(opts, :llm_request_options, req_http_options: [plug: plug])}
    end)

    assert {:ok, thread} = Threads.create(user, user.account, request("Which targets are slowest?"))
    host_until_idle(thread.id)
    assert {:ok, fresh} = Threads.get(user, user.account, thread.id)

    assert [card, reply] =
             fresh |> Threads.serialize() |> Map.fetch!(:messages) |> Enum.filter(&(&1.role == "assistant"))

    assert card.content == "TuistKit is slowest."
    assert card.ui == %{size: "medium", source: "compiled card"}
    assert reply.content == "TuistKit misses the cache most."
    refute Map.has_key?(reply, :ui)
  end

  test "a hosted thread searches a large MCP catalog, calls its tool and persists its final reply" do
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
          "initialize" ->
            %{protocolVersion: "2025-06-18", capabilities: %{tools: %{}}}

          "notifications/initialized" ->
            %{}

          "tools/list" ->
            %{
              tools:
                for index <- 1..630 do
                  %{name: "lookup_#{index}", inputSchema: %{type: "object"}}
                end
            }

          "tools/call" ->
            %{content: [%{type: "text", text: "Remote cache evidence"}]}
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
            assert length(request["tools"]) == 3

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
                  id: "search-call",
                  type: "function",
                  function: %{name: "mcp_search_tools", arguments: ~s({"query":"lookup_630"})}
                }
              ]
            }

          1 ->
            assert Enum.any?(request["messages"], &(&1["role"] == "tool" and &1["tool_call_id"] == "name-call"))
            result = Enum.find(request["messages"], &(&1["tool_call_id"] == "search-call"))
            %{"tools" => [found], "next_offset" => nil} = JSON.decode!(result["content"])
            assert found["description"] =~ "lookup_630"

            %{
              role: "assistant",
              content: nil,
              tool_calls: [
                %{
                  id: "remote-call",
                  type: "function",
                  function: %{name: "mcp_call_tool", arguments: JSON.encode!(%{name: found["name"], arguments: %{}})}
                }
              ]
            }

          2 ->
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
        choices: [%{index: 0, message: message, finish_reason: if(turn < 2, do: "tool_calls", else: "stop")}],
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
    host_until_idle(thread.id)
    assert {:ok, fresh} = Threads.get(user, user.account, thread.id)
    assert fresh.title == "Understand the cache"
    assert fresh.agent_status == "idle"
    assert List.last(fresh.messages).body == "Here is the explanation."
    assert List.last(fresh.messages).suggestions == ["Explain invalidation"]
    assert Repo.reload!(run).status == "succeeded"
    assert %{status: "completed", result: result} = Repo.one!(ToolCall)
    assert result =~ "Remote cache evidence"
    assert Agent.get(calls, & &1) == 3
  end

  test "an unavailable profile MCP server does not fail an otherwise independent run" do
    user = AccountsFixtures.user_fixture()
    server_id = Ecto.UUID.generate()

    stub(MCPServers, :list, fn _ -> [%{id: server_id, url: "https://mcp.example.com", connected: true}] end)

    stub(MCPServers, :credentials, fn _, ^server_id ->
      {:ok, %{url: "https://mcp.example.com", access_token: "secret"}}
    end)

    stub(SSRFGuard, :pin, fn _ -> {:error, :unavailable} end)

    plug = fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      request = JSON.decode!(raw)
      refute Enum.any?(request["tools"], &String.starts_with?(&1["function"]["name"], "mcp_"))

      response = %{
        id: "completion",
        object: "chat.completion",
        created: 0,
        model: Provider.default_model(:chatgpt),
        choices: [
          %{
            index: 0,
            message: %{role: "assistant", content: JSON.encode!(%{reply: "Still available.", suggestions: []})},
            finish_reason: "stop"
          }
        ],
        usage: %{prompt_tokens: 10, completion_tokens: 10, total_tokens: 20}
      }

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, JSON.encode!(response))
    end

    stub(AISubscriptions, :list, fn _ -> [%{provider: :chatgpt, connected: true}] end)
    {:ok, opts} = Provider.client_opts(user, %{provider: "chatgpt", model: "selected-model"})

    stub(Provider, :client_opts, fn _, _ ->
      {:ok, Keyword.put(opts, :llm_request_options, req_http_options: [plug: plug])}
    end)

    assert {:ok, thread} = Threads.create(user, user.account, request("Reply without MCP"))
    run = Repo.one!(Run)
    host_until_idle(thread.id)
    assert {:ok, fresh} = Threads.get(user, user.account, thread.id)
    assert List.last(fresh.messages).body == "Still available."
    assert Repo.reload!(run).status == "succeeded"
  end

  test "a stale MCP discovery does not dispatch inference" do
    user = AccountsFixtures.user_fixture()
    assert {:ok, thread} = Threads.create(user, user.account, request("Do not continue"))
    run = Repo.one!(Run)

    stub(Provider, :client_opts, fn _, _ ->
      assert {:ok, _} = Threads.archive(user, user.account, thread.id, "archived")
      {:ok, []}
    end)

    reject(MCPServers, :list, 1)
    host_until_idle(thread.id)
    assert {:ok, fresh} = Threads.get(user, user.account, thread.id)
    assert fresh.status == :archived
    assert Repo.reload!(run).status == "cancelled"
    refute Enum.any?(fresh.messages, &(&1.kind == "agent"))
  end

  test "each model dispatch refreshes only the bound provider and never falls back" do
    user = AccountsFixtures.user_fixture()
    {:ok, _} = Threads.create(user, user.account, request("Inspect"))
    {:ok, {run, _}} = claim(Repo.one!(Run))

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
    {:ok, {run, _}} = claim(Repo.one!(Run))

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

  test "a run drained mid tool call resumes on the next host without repeating its stored steps" do
    user = AccountsFixtures.user_fixture()
    requests = start_supervised!({Agent, fn -> 0 end}, id: :requests)
    renames = start_supervised!({Agent, fn -> 0 end}, id: :renames)
    test = self()

    plug = fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      request = JSON.decode!(raw)
      turn = Agent.get_and_update(requests, &{&1, &1 + 1})

      {message, finish} =
        case turn do
          0 ->
            {%{
               role: "assistant",
               content: nil,
               tool_calls: [
                 %{
                   id: "name-call",
                   type: "function",
                   function: %{name: "set_thread_name", arguments: ~s({"name":"Resumed"})}
                 }
               ]
             }, "tool_calls"}

          1 ->
            assert Enum.any?(request["messages"], &(&1["role"] == "tool" and &1["tool_call_id"] == "name-call"))

            {%{role: "assistant", content: JSON.encode!(%{reply: "Finished after the handoff.", suggestions: []})},
             "stop"}
        end

      response = %{
        id: "completion-#{turn}",
        object: "chat.completion",
        created: 0,
        model: Provider.default_model(:chatgpt),
        choices: [%{index: 0, message: message, finish_reason: finish}],
        usage: %{prompt_tokens: 10, completion_tokens: 10, total_tokens: 20}
      }

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, JSON.encode!(response))
    end

    stub(AISubscriptions, :list, fn _ -> [%{provider: :chatgpt, connected: true}] end)
    {:ok, opts} = Provider.client_opts(user, %{provider: "chatgpt", model: "selected-model"})

    stub(Provider, :client_opts, fn _, _ ->
      {:ok, Keyword.put(opts, :llm_request_options, req_http_options: [plug: plug])}
    end)

    # The first host's call hangs until it is drained, as a deploy would.
    stub(Threads, :rename, fn run, name ->
      if Agent.get_and_update(renames, &{&1, &1 + 1}) == 0 do
        send(test, :renaming)
        receive do: (:never -> :ok), after: (10_000 -> :ok)
      end

      Mimic.call_original(Threads, :rename, [run, name])
    end)

    {:ok, thread} = Threads.create(user, user.account, request("Name this thread"))
    run = Repo.one!(Run)

    first = host(thread.id)
    assert_receive :renaming, 5_000
    drain(first)
    assert Repo.reload!(run).status == "running"

    # The drained host's lease lapses; the next host takes the thread over.
    lapse(thread.id)
    host_until_idle(thread.id)

    run = Repo.reload!(run)
    assert run.status == "succeeded"
    assert run.attempt == 2
    assert {:ok, fresh} = Threads.get(user, user.account, thread.id)
    assert fresh.title == "Resumed"
    assert [%{body: "Finished after the handoff."}] = Enum.filter(fresh.messages, &(&1.kind == "agent"))
    # The stored model response was not requested again; the replay-safe call ran again.
    assert Agent.get(requests, & &1) == 2
    assert Agent.get(renames, & &1) == 2
  end

  test "a run whose process crashes ends interrupted instead of crashing the next host" do
    user = AccountsFixtures.user_fixture()
    stub(Provider, :client_opts, fn _, _ -> raise "boom" end)
    {:ok, thread} = Threads.create(user, user.account, request("Crash"))
    run = Repo.one!(Run)

    host_until_idle(thread.id)

    assert Repo.reload!(run).status == "interrupted"
    assert {:ok, fresh} = Threads.get(user, user.account, thread.id)
    assert fresh.agent_status == "interrupted"
    assert Threads.next_run(thread.id) == nil
  end

  test "a host whose run is fenced mid-run exits, and the next claim ends the run" do
    user = AccountsFixtures.user_fixture()
    test = self()

    # The owner loses access while the model is called; the run's writes are
    # fenced from then on.
    stub(Provider, :client_opts, fn _, _ ->
      Repo.update!(Ecto.Changeset.change(Repo.reload!(user), active: false))
      send(test, :revoked)
      {:error, :not_connected}
    end)

    {:ok, thread} = Threads.create(user, user.account, request("Revoke"))
    run = Repo.one!(Run)
    pid = host(thread.id)
    ref = Process.monitor(pid)

    assert_receive :revoked, 5_000
    assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, :stale}}, 5_000
    assert Repo.reload!(run).status == "running"

    lapse(thread.id)
    [%{epoch: epoch}] = Enum.filter(Lease.claim("test-host", 100), &(&1.id == thread.id))
    assert {:error, :forbidden} = Threads.claim(run.id, epoch)
    assert Repo.reload!(run).status == "interrupted"
  end

  # An object storage outage: the session cannot load, so the host hands the
  # thread back with its run still running, and a later host finishes it.
  test "a host that cannot reach the session store leaves the run for a later host" do
    user = AccountsFixtures.user_fixture()

    answer_with(user, reply_plug("Back online."))

    stub(SessionStore, :store, fn kind, id, epoch ->
      {module, store} = Mimic.call_original(SessionStore, :store, [kind, id, epoch])
      {module, Keyword.put(store, :bucket, {UnreachableBucket, []})}
    end)

    {:ok, thread} = Threads.create(user, user.account, request("Answer when you can"))
    run = Repo.one!(Run)
    pid = host(thread.id)
    ref = Process.monitor(pid)

    assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, :unavailable}}, 5_000
    assert Repo.reload!(run).status == "running"

    stub(SessionStore, :store, &Mimic.call_original(SessionStore, :store, [&1, &2, &3]))
    lapse(thread.id)
    host_until_idle(thread.id)

    assert %{status: "succeeded", attempt: 2} = Repo.reload!(run)
    assert {:ok, fresh} = Threads.get(user, user.account, thread.id)
    assert [%{body: "Back online."}] = Enum.filter(fresh.messages, &(&1.kind == "agent"))
  end

  # A stored session that cannot be read stays that way, so retrying it after
  # a backoff would never end; the run fails and the host stays usable.
  test "a session the store cannot read fails its run instead of being retried" do
    user = AccountsFixtures.user_fixture()
    answer_with(user, reply_plug("First answer."))

    {:ok, thread} = Threads.create(user, user.account, request("First"))
    host_until_idle(thread.id)

    stub(SessionStore, :store, fn kind, id, epoch ->
      {module, store} = Mimic.call_original(SessionStore, :store, [kind, id, epoch])
      {module, Keyword.put(store, :decrypt, fn _ -> raise "bad key" end)}
    end)

    {:ok, _thread} = Threads.message(user, user.account, thread.id, request("Second"))
    run = Repo.one!(from(r in Run, where: r.thread_id == ^thread.id and r.status != "succeeded"))
    lapse(thread.id)
    host_until_idle(thread.id)

    assert Repo.reload!(run).status == "failed"
  end

  # A message whose wake never reached the host is found when the runner next
  # asks the host to stop if idle, instead of the host stopping with it.
  test "a host asked to stop with work it was not woken for runs it" do
    user = AccountsFixtures.user_fixture()
    answer_with(user, reply_plug("Done."))

    {:ok, thread} = Threads.create(user, user.account, request("First"))
    host_until_idle(thread.id)

    # The host has looked for work and found none.
    lapse(thread.id)
    pid = host(thread.id)
    :sys.get_state(pid)
    stub(Lease, :wake, fn _id -> :ok end)

    {:ok, _thread} = Threads.message(user, user.account, thread.id, request("Second"))
    refute idle?(pid)

    eventually(fn -> Repo.aggregate(from(r in Run, where: r.status == "succeeded"), :count) == 2 end)
    assert idle?(pid)
  end

  defp answer_with(user, plug) do
    stub(AISubscriptions, :list, fn _ -> [%{provider: :chatgpt, connected: true}] end)
    {:ok, opts} = Provider.client_opts(user, %{provider: "chatgpt", model: "selected-model"})

    stub(Provider, :client_opts, fn _, _ ->
      {:ok, Keyword.put(opts, :llm_request_options, req_http_options: [plug: plug])}
    end)
  end

  defp reply_plug(reply) do
    fn conn ->
      response = %{
        id: "completion",
        object: "chat.completion",
        created: 0,
        model: Provider.default_model(:chatgpt),
        choices: [
          %{
            index: 0,
            message: %{role: "assistant", content: JSON.encode!(%{reply: reply, suggestions: []})},
            finish_reason: "stop"
          }
        ],
        usage: %{prompt_tokens: 10, completion_tokens: 10, total_tokens: 20}
      }

      conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.send_resp(200, JSON.encode!(response))
    end
  end

  # Whether the host stops when asked to if idle. A host that does is gone,
  # so callers ask only while they expect it to stay.
  defp idle?(pid) do
    Host.stop_if_idle(pid, self(), :probe)

    receive do
      {Kind, :idle, ^pid, :probe} -> true
    after
      100 -> false
    end
  end

  # Takes the thread's session lease as an agents runner does and hosts it.
  defp host(thread_id) do
    [%{epoch: epoch}] = Enum.filter(Lease.claim("test-host", 100), &(&1.id == thread_id))
    {:ok, pid} = Host.start(thread_id, epoch)
    pid
  end

  # Asks the host to stop once idle, as the runner does after each renewal,
  # until it does.
  defp host_until_idle(thread_id) do
    pid = host(thread_id)
    ref = Process.monitor(pid)

    eventually(fn ->
      Host.stop_if_idle(pid, self(), :token)

      receive do
        {Kind, :idle, ^pid, :token} -> true
      after
        50 -> false
      end
    end)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000
  end

  defp drain(pid) do
    ref = Process.monitor(pid)
    Host.drain(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, :drain}}, 10_000
  end

  defp claim(run) do
    [%{epoch: epoch}] = Enum.filter(Lease.claim("test-host", 100), &(&1.id == run.thread_id))
    Threads.claim(run.id, epoch)
  end

  defp lapse(thread_id) do
    Repo.update_all(from(s in "agent_sessions", where: s.id == ^thread_id),
      set: [lease_expires_at: DateTime.add(DateTime.utc_now(), -1)]
    )
  end

  defp eventually(fun, attempts \\ 300) do
    cond do
      fun.() -> :ok
      attempts == 0 -> flunk("condition never held")
      true -> Process.sleep(50) && eventually(fun, attempts - 1)
    end
  end

  defp request(body),
    do: %{"content" => body, "request_id" => Ecto.UUID.generate(), "provider" => "chatgpt", "model" => "selected-model"}
end
