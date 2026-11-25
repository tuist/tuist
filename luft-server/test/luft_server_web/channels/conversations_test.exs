defmodule LuftServerWeb.ConversationsTest do
  use LuftServerWeb.ConnCase, async: false

  import Phoenix.ChannelTest
  import Phoenix.ConnTest, only: []

  alias LuftServer.Lounges.Presence
  alias LuftServer.NativeAuth
  alias LuftServer.Repo
  alias LuftServer.Threads
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
