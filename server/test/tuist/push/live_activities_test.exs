defmodule Tuist.Push.LiveActivitiesTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Boruta.Ecto.Token
  alias Tuist.Environment
  alias Tuist.OAuth.Clients
  alias Tuist.OAuth.TokenGenerator
  alias Tuist.Push
  alias Tuist.Push.LiveActivities
  alias Tuist.Push.LiveActivity
  alias Tuist.Push.Workers.LiveActivityWorker
  alias Tuist.Repo
  alias Tuist.Threads.Message
  alias Tuist.Threads.Run
  alias Tuist.Threads.Thread
  alias Tuist.Threads.ToolCall
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup do
    jwk = JOSE.JWK.generate_key({:ec, "P-256"})
    {_, pem} = JOSE.JWK.to_pem(jwk)
    stub(Environment, :apns_key_id, fn -> "K#{System.unique_integer([:positive])}" end)
    stub(Environment, :apns_team_id, fn -> "TEAM123456" end)
    stub(Environment, :apns_private_key, fn -> pem end)

    user = AccountsFixtures.user_fixture()
    %{user: user, session: luft_session(user)}
  end

  describe "content/2" do
    test "maps each thread's run and tool calls to a phase, never their arguments", %{user: user} do
      editing = thread!(user, "Fix login redirect loop", "running", ago: 300)
      run = run!(editing, "running")
      call!(run, 1, "Read", "completed")
      call!(run, 2, "Ls", "completed")
      call!(run, 3, "Bash", "completed")
      call!(run, 4, "Edit", "executing")

      queued = thread!(user, "Add coverage trend chart", "queued", ago: 100)
      run!(queued, "queued")

      # A title still equal to the first message is conversation content.
      untitled = thread!(user, "Inspect the repository", "running", goal: "Inspect the repository", ago: 50)
      run!(untitled, "running")

      thread!(user, "Finished earlier", "idle")

      {document, working} = LiveActivities.content(user)

      assert document["v"] == 1
      assert document["summary"]["headline"] == "3 threads working"
      assert Enum.sort(working) == Enum.sort([editing.id, queued.id, untitled.id])

      assert [
               %{
                 "headline" => "Fix login redirect loop",
                 "phase" => "editing",
                 "detail" => "Editing · 3 steps",
                 "symbol" => "pencil",
                 "progress" => %{"kind" => "timer"},
                 "trail" => ["blue", "orange", "purple"],
                 "link" => "luft://app/threads/" <> _
               },
               %{"headline" => "Add coverage trend chart", "phase" => "waiting", "detail" => "Queued"},
               %{"headline" => "Your thread", "phase" => "thinking"}
             ] = document["threads"]

      refute JSON.encode!(document) =~ "command"
    end

    test "shows a thread that finished since the last push once, first and with its steps", %{user: user} do
      working = thread!(user, "Bump Kura to 0.9", "running", ago: 200)
      run!(working, "running")
      finished = thread!(user, "Fix login redirect loop", "idle", ago: 400)
      run = run!(finished, "succeeded")
      call!(run, 1, "Edit", "completed")
      call!(run, 2, "Bash", "completed")

      {document, working_ids} = LiveActivities.content(user, [working.id, finished.id])

      assert working_ids == [working.id]
      assert document["summary"]["headline"] == "1 thread working"

      assert [
               %{"phase" => "done", "detail" => "Finished in 2 steps", "progress" => %{"kind" => "steps", "done" => 2}},
               %{"phase" => "thinking"}
             ] = document["threads"]

      {document, _} = LiveActivities.content(user, working_ids)
      assert [%{"phase" => "thinking"}] = document["threads"]
    end

    test "leaves out threads the user can no longer read", %{user: user} do
      run!(thread!(user, "Fix login redirect loop", "running"), "running")
      stub(Tuist.FeatureFlags, :luft_enabled?, fn _ -> false end)

      assert {%{"threads" => []}, []} = LiveActivities.content(user)
    end
  end

  describe "register/4" do
    test "replaces the sign-in's previous activity and rejects retired and foreign IDs", %{user: user, session: session} do
      first = Ecto.UUID.generate()
      assert {:ok, _} = LiveActivities.register(user, session, first, params())
      second = Ecto.UUID.generate()
      assert {:ok, _} = LiveActivities.register(user, session, second, params())

      assert %LiveActivity{retired_reason: "replaced", user_id: nil, token: nil} = Repo.get!(LiveActivity, first)
      assert {:error, :retired} = LiveActivities.register(user, session, first, params())

      stranger = AccountsFixtures.user_fixture()
      assert {:error, :conflict} = LiveActivities.register(stranger, luft_session(stranger), second, params())

      assert :ok = LiveActivities.unregister(user, second)
      assert {:error, :retired} = LiveActivities.register(user, session, second, params())

      assert {:error, :invalid} = LiveActivities.register(user, session, Ecto.UUID.generate(), %{"token" => "zz"})
    end
  end

  describe "deliver/1" do
    test "pushes the document, skips unchanged updates and ends with the finished threads", %{
      user: user,
      session: session
    } do
      thread = thread!(user, "Fix login redirect loop", "running")
      run = run!(thread, "running")
      call!(run, 1, "Bash", "executing")
      token = token()
      id = Ecto.UUID.generate()
      {:ok, _} = LiveActivities.register(user, session, id, params(token))

      expect(Req, :post, fn url, opts ->
        assert url == "https://api.sandbox.push.apple.com/3/device/#{token}"
        headers = Map.new(opts[:headers])
        assert headers["apns-topic"] == "dev.tuist.code.push-type.liveactivity"
        assert headers["apns-push-type"] == "liveactivity"
        assert headers["apns-priority"] == "5"
        assert headers["apns-collapse-id"] == id

        assert %{"event" => "update", "content-state" => %{"threads" => [%{"phase" => "running"}]}} =
                 opts[:json]["aps"]

        {:ok, %Req.Response{status: 200, body: ""}}
      end)

      assert :continue = LiveActivities.deliver(id)

      # The same document a second later is not pushed again.
      backdate!(id, 1)
      stub(Req, :post, fn _url, _opts -> flunk("pushed an unchanged document") end)
      assert :continue = LiveActivities.deliver(id)

      Repo.update!(Ecto.Changeset.change(thread, agent_status: "idle"))
      Repo.update!(Ecto.Changeset.change(run, status: "succeeded"))

      expect(Req, :post, fn _url, opts ->
        assert Map.new(opts[:headers])["apns-priority"] == "10"
        aps = opts[:json]["aps"]
        assert %{"event" => "end", "content-state" => %{"threads" => [%{"phase" => "done"}]}} = aps
        assert aps["dismissal-date"] > aps["timestamp"]
        {:ok, %Req.Response{status: 200, body: ""}}
      end)

      assert :done = LiveActivities.deliver(id)
      assert %LiveActivity{retired_reason: "ended", token: nil} = Repo.get!(LiveActivity, id)
    end

    test "retires the registration once its sign-in ends", %{user: user, session: session} do
      run!(thread!(user, "Fix login redirect loop", "running"), "running")
      id = Ecto.UUID.generate()
      {:ok, _} = LiveActivities.register(user, session, id, params())
      Repo.update_all(Token, set: [revoked_at: DateTime.utc_now()])

      reject(&Req.post/2)
      assert :done = LiveActivities.deliver(id)
      assert %LiveActivity{retired_reason: "session_ended"} = Repo.get!(LiveActivity, id)
    end
  end

  test "a thread change wakes its owner's live registrations", %{user: user, session: session} do
    stub(Environment, :apns_configured?, fn -> true end)
    id = Ecto.UUID.generate()
    {:ok, _} = LiveActivities.register(user, session, id, params())
    Repo.delete_all(Oban.Job)

    LiveActivities.thread_changed(user.id)
    LiveActivities.thread_changed(user.id)

    assert [%Oban.Job{args: %{"registration_id" => ^id}}] = all_enqueued(worker: LiveActivityWorker)
  end

  defp luft_session(user) do
    bearer = TokenGenerator.generate(:access_token, %Token{sub: to_string(user.id), client_id: Clients.luft_client_id()})

    Repo.insert!(%Token{
      type: "access_token",
      value: bearer,
      refresh_token: Ecto.UUID.generate(),
      client_id: Clients.luft_client_id(),
      sub: to_string(user.id),
      scope: ""
    })

    {:ok, session} = Push.oauth_session(bearer, user, ["luft"])
    session
  end

  defp token, do: Base.encode16(:crypto.strong_rand_bytes(32), case: :lower)
  defp params(token \\ token()), do: %{"token" => token, "environment" => "sandbox"}

  defp backdate!(id, seconds) do
    Repo.update_all(from(a in LiveActivity, where: a.id == ^id),
      set: [last_sent_at: DateTime.utc_now() |> DateTime.add(-seconds) |> DateTime.truncate(:second)]
    )
  end

  defp thread!(user, title, agent_status, opts \\ []) do
    at = DateTime.utc_now() |> DateTime.add(-Keyword.get(opts, :ago, 0)) |> DateTime.truncate(:second)

    Repo.insert!(%Thread{
      account_id: user.account.id,
      owner_id: user.id,
      request_id: Ecto.UUID.generate(),
      request_hash: :crypto.hash(:sha256, title),
      title: title,
      goal: Keyword.get(opts, :goal, "Private prompt"),
      provider: "chatgpt",
      model: "selected-model",
      agent_status: agent_status,
      inserted_at: at,
      updated_at: at
    })
  end

  defp run!(thread, status), do: Repo.insert!(%Run{thread_id: thread.id, status: status, inserted_at: thread.inserted_at})

  defp call!(run, position, name, status) do
    message =
      Repo.insert!(%Message{thread_id: run.thread_id, position: position, kind: "tool", body: "make", tool_name: name})

    Repo.insert!(%ToolCall{
      run_id: run.id,
      message_id: message.id,
      fingerprint: :crypto.strong_rand_bytes(16),
      name: name,
      status: status,
      result: ~s({"command": "secret"})
    })
  end
end
