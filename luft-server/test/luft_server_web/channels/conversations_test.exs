defmodule LuftServerWeb.ConversationsTest do
  use LuftServerWeb.ConnCase, async: false

  import Ecto.Query
  import Phoenix.ChannelTest
  import Phoenix.ConnTest, only: []

  alias LuftServer.Lounges.Presence
  alias LuftServer.NativeAuth
  alias LuftServer.Repo
  alias LuftServer.Threads
  alias LuftServer.Threads.Message
  alias LuftServer.Threads.Thread
  alias LuftServerWeb.ConversationsSocket

  setup do
    Req.Test.set_req_test_to_shared()
    bearer = bearer()
    session = NativeAuth.resolve_bearer(bearer)
    stub_scope()
    %{bearer: bearer, session: session}
  end

  test "only the bearer subprotocol authenticates a native socket", %{bearer: bearer} do
    assert {:ok, _socket} = connect(ConversationsSocket, %{}, connect_info: %{auth_token: bearer})
    assert :error = connect(ConversationsSocket, %{token: bearer})
    assert :error = connect(ConversationsSocket, %{}, connect_info: %{auth_token: "invalid"})
  end

  test "commits push private thread hints without polling or conversation content", %{
    bearer: bearer,
    session: session
  } do
    thread = thread(session)
    {:ok, socket} = connect(ConversationsSocket, %{}, connect_info: %{auth_token: bearer})

    assert {:ok, %{revision: 0, agent_status: "queued", activity: nil}, joined} =
             subscribe_and_join(socket, "threads:team:#{thread.id}")

    Repo.update!(Ecto.Changeset.change(thread, revision: 7, agent_status: "running"))
    Phoenix.PubSub.broadcast(LuftServer.PubSub, Threads.topic(1, 100), :threads_changed)
    assert_push "snapshot", %{revision: 7, agent_status: "running", activity: nil} = snapshot
    assert Enum.sort(Map.keys(snapshot)) == [:activity, :agent_status, :revision]

    # Unchanged notifications produce no repeated snapshot.
    Phoenix.PubSub.broadcast(LuftServer.PubSub, Threads.topic(1, 100), :threads_changed)
    refute_push "snapshot", _

    other = thread(session, owner_id: 2)

    assert {:error, %{reason: "not_found"}} =
             subscribe_and_join(socket, "threads:team:#{other.id}")

    assert {:error, %{reason: "not_found"}} =
             subscribe_and_join(socket, "threads:other:#{thread.id}")

    Process.unlink(joined.channel_pid)
    monitor = Process.monitor(joined.channel_pid)
    Repo.delete!(session)
    Phoenix.PubSub.broadcast(LuftServer.PubSub, Threads.topic(1, 100), :threads_changed)
    assert_receive {:DOWN, ^monitor, :process, _pid, :normal}
    refute_push "snapshot", _
  end

  test "a syncing client receives the latest page, then only the rows each commit changed", %{
    bearer: bearer,
    session: session
  } do
    thread = thread(session)
    commit(thread, fn -> message(thread, 1, "first") end)
    commit(thread, fn -> message(thread, 2, "second") end)
    {:ok, socket} = connect(ConversationsSocket, %{}, connect_info: %{auth_token: bearer})

    assert {:ok, %{revision: 2}, _joined} =
             subscribe_and_join(socket, "threads:team:#{thread.id}", %{
               "sync" => true,
               "since" => nil
             })

    assert_push "diff", %{reset: true, cursor: 2, thread: mounted}
    assert Enum.map(mounted.messages, & &1.content) == ["first", "second"]
    assert Map.has_key?(mounted, :has_more)

    # An edit to an older row and an append in one commit: only those come.
    commit(thread, fn ->
      Repo.update!(
        Ecto.Changeset.change(Repo.get_by!(Message, body: "first"), tool_state: "done")
      )

      message(thread, 3, "third")
    end)

    Phoenix.PubSub.broadcast(LuftServer.PubSub, Threads.topic(1, 100), :threads_changed)
    Phoenix.PubSub.broadcast(LuftServer.PubSub, Threads.topic(1, 100), :threads_changed)
    assert_push "diff", %{reset: false, cursor: 3, thread: delta}

    assert Enum.map(delta.messages, &{&1.content, &1.toolStatus}) == [
             {"first", "done"},
             {"third", nil}
           ]

    refute Map.has_key?(delta, :has_more)
    # Both notifications folded into that one read.
    refute_push "diff", _

    # A client returning with its cursor gets only what it missed.
    {:ok, again} = connect(ConversationsSocket, %{}, connect_info: %{auth_token: bearer})
    commit(thread, fn -> message(thread, 4, "while away") end)

    assert {:ok, _, _} =
             subscribe_and_join(again, "threads:team:#{thread.id}", %{
               "sync" => true,
               "since" => 3
             })

    assert_push "diff", %{
      reset: false,
      cursor: 4,
      thread: %{messages: [%{content: "while away"}]}
    }

    {:ok, current} = connect(ConversationsSocket, %{}, connect_info: %{auth_token: bearer})

    assert {:ok, _, _} =
             subscribe_and_join(current, "threads:team:#{thread.id}", %{
               "sync" => true,
               "since" => 4
             })

    refute_push "diff", _

    # Ending a session clears it from its messages without resending them.
    versions = fn -> Repo.all(from m in Message, order_by: m.position, select: m.version) end
    before = versions.()
    Repo.update_all(Message, set: [author_session_id: nil])
    assert versions.() == before

    # A client too far behind for one delta receives the latest page instead.
    commit(thread, fn -> Enum.each(10..210, &message(thread, &1, "bulk #{&1}")) end)
    {:ok, behind} = connect(ConversationsSocket, %{}, connect_info: %{auth_token: bearer})

    assert {:ok, _, _} =
             subscribe_and_join(behind, "threads:team:#{thread.id}", %{
               "sync" => true,
               "since" => 4
             })

    assert_push "diff", %{reset: true, cursor: 5, thread: %{has_more: true}}
  end

  test "presence is Luft-local and membership revocation closes the channel", %{bearer: bearer} do
    {:ok, socket} = connect(ConversationsSocket, %{}, connect_info: %{auth_token: bearer})
    assert {:ok, %{}, joined} = subscribe_and_join(socket, "presence:team")
    assert_push "presence_state", %{"1" => %{metas: [%{handle: "one"}]}}
    assert %{"1" => _} = Presence.list("lounges_presence:100")

    Req.Test.stub(LuftServer.Tuist, fn conn ->
      conn |> put_status(404) |> Req.Test.json(%{message: "Not found."})
    end)

    Process.unlink(joined.channel_pid)
    monitor = Process.monitor(joined.channel_pid)
    send(joined.channel_pid, :recheck_authority)
    assert_receive {:DOWN, ^monitor, :process, _pid, :normal}
  end

  defp stub_scope do
    Req.Test.stub(LuftServer.Tuist, fn conn ->
      assert conn.method == "GET"
      assert get_req_header(conn, "authorization") == ["Bearer upstream-secret"]

      assert conn.request_path in [
               "/api/accounts/team/luft-context",
               "/api/accounts/other/luft-context"
             ]

      Req.Test.json(conn, %{
        user_id: 1,
        account_id: if(conn.request_path =~ "/team/", do: 100, else: 101),
        organization_id: 10,
        can_create_threads: true,
        people: [%{id: 1, handle: "one", active: true}, %{id: 2, handle: "two", active: true}]
      })
    end)
  end

  # A thread write as the context makes it: the thread's revision goes up in
  # the same transaction as the rows it changes.
  defp commit(thread, fun) do
    Repo.transaction(fn ->
      fun.()
      fresh = Repo.reload!(thread)
      Repo.update!(Ecto.Changeset.change(fresh, revision: fresh.revision + 1))
    end)
  end

  defp message(thread, position, body),
    do:
      Repo.insert!(%Message{thread_id: thread.id, position: position, kind: "agent", body: body})

  defp thread(session, attrs \\ []) do
    %Thread{
      account_id: 100,
      account_handle: "team",
      owner_id: 1,
      owner_session_id: session.id,
      request_id: Ecto.UUID.generate(),
      request_hash: "fingerprint",
      title: "Private title",
      goal: "Private prompt",
      provider: "chatgpt",
      model: "test-model"
    }
    |> struct!(attrs)
    |> Repo.insert!()
  end

  defp bearer do
    verifier = String.duplicate("v", 43)

    request = %{
      "client_id" => NativeAuth.client_id(),
      "response_type" => "code",
      "redirect_uri" => "luft://oauth-callback",
      "state" => "state",
      "code_challenge_method" => "S256",
      "code_challenge" => :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)
    }

    {:ok, callback, _session} =
      NativeAuth.complete(
        %{
          claims: %{"sub" => "1", "preferred_username" => "one"},
          tokens: %{
            "access_token" => "upstream-secret",
            "refresh_token" => "refresh",
            "expires_in" => 3600
          }
        },
        request
      )

    params = callback |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    {:ok, credentials} =
      NativeAuth.exchange(%{
        "grant_type" => "authorization_code",
        "client_id" => NativeAuth.client_id(),
        "redirect_uri" => "luft://oauth-callback",
        "code" => params["code"],
        "code_verifier" => verifier
      })

    credentials.access_token
  end
end
