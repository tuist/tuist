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
  alias Tuist.Push.LiveActivityStarter
  alias Tuist.Push.Workers.LiveActivityStartWorker
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

    test "leaves out snoozed threads and offers to snooze the working ones", %{user: user} do
      working = thread!(user, "Bump Kura to 0.9", "running")
      run!(working, "running")
      until_needed = thread!(user, "Fix login redirect loop", "running")
      run!(until_needed, "running")
      Repo.update!(Ecto.Changeset.change(until_needed, snoozed_until_needed: true))
      later = thread!(user, "Add coverage trend chart", "running")
      run!(later, "running")
      snoozed_until = DateTime.utc_now() |> DateTime.add(1, :hour) |> DateTime.truncate(:second)
      Repo.update!(Ecto.Changeset.change(later, snoozed_until: snoozed_until))

      {document, working_ids} = LiveActivities.content(user, [until_needed.id])

      assert working_ids == [working.id]
      assert [%{"snooze_link" => snooze_link, "link" => link}] = document["threads"]
      assert snooze_link == String.replace(link, "/threads/#{working.id}?", "/threads/#{working.id}/snooze?")
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
    test "pushes the document, skips unchanged updates, hurries phase changes and ends with the finished threads", %{
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
        # The first phase the activity shows is news.
        assert headers["apns-priority"] == "10"
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

      # Thinking between two tool calls isn't news either.
      Repo.update_all(ToolCall, set: [status: "completed"])
      backdate!(id, 1)

      expect(Req, :post, fn _url, opts ->
        assert Map.new(opts[:headers])["apns-priority"] == "5"
        assert %{"threads" => [%{"phase" => "thinking"}]} = opts[:json]["aps"]["content-state"]
        {:ok, %Req.Response{status: 200, body: ""}}
      end)

      assert :continue = LiveActivities.deliver(id)

      # Another command in the same phase only changes the step count: not urgent.
      call!(run, 2, "Bash", "executing")
      backdate!(id, 1)

      expect(Req, :post, fn _url, opts ->
        assert Map.new(opts[:headers])["apns-priority"] == "5"

        assert %{"threads" => [%{"phase" => "running", "detail" => "Running commands · 1 step"}]} =
                 opts[:json]["aps"]["content-state"]

        {:ok, %Req.Response{status: 200, body: ""}}
      end)

      assert :continue = LiveActivities.deliver(id)

      # Moving on to editing is.
      Repo.update_all(ToolCall, set: [status: "completed"])
      call!(run, 3, "Edit", "executing")
      backdate!(id, 1)

      expect(Req, :post, fn _url, opts ->
        assert Map.new(opts[:headers])["apns-priority"] == "10"
        assert %{"threads" => [%{"phase" => "editing"}]} = opts[:json]["aps"]["content-state"]
        {:ok, %Req.Response{status: 200, body: ""}}
      end)

      assert :continue = LiveActivities.deliver(id)
      backdate!(id, 1)

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

  describe "start/1" do
    test "starts the activity on the device of a sign-in without one, which then registers it", %{
      user: user,
      session: session
    } do
      stub(Environment, :apns_configured?, fn -> true end)
      run!(thread!(user, "Fix login redirect loop", "running"), "running")
      start_token = token()
      :ok = LiveActivities.register_starter(user, session, starter_params(start_token))
      starter = Repo.one!(LiveActivityStarter)

      LiveActivities.thread_changed(user.id)
      assert [%Oban.Job{args: %{"starter_id" => starter_id}}] = all_enqueued(worker: LiveActivityStartWorker)
      assert starter_id == starter.id

      test_pid = self()

      expect(Req, :post, fn url, opts ->
        assert url == "https://api.sandbox.push.apple.com/3/device/#{start_token}"
        headers = Map.new(opts[:headers])
        assert headers["apns-topic"] == "dev.tuist.code.push-type.liveactivity"
        assert headers["apns-priority"] == "10"
        aps = opts[:json]["aps"]

        assert %{
                 "event" => "start",
                 "attributes-type" => "LuftActivityAttributes",
                 "attributes" => %{"registrationID" => id, "profileID" => "profile_1"},
                 "input-push-token" => 1,
                 "alert" => %{"title" => "1 thread working"},
                 "content-state" => %{"threads" => [%{"headline" => "Fix login redirect loop"}]}
               } = aps

        send(test_pid, {:started, id})
        {:ok, %Req.Response{status: 200, body: ""}}
      end)

      assert :ok = LiveActivities.start(starter.id)
      assert_received {:started, id}
      assert %LiveActivity{token: nil, retired_at: nil} = Repo.get!(LiveActivity, id)

      # The pending registration counts as live: no second start.
      Repo.delete_all(Oban.Job)
      LiveActivities.thread_changed(user.id)
      assert [] = all_enqueued(worker: LiveActivityStartWorker)
      reject(&Req.post/2)
      assert :ok = LiveActivities.start(starter.id)

      # The app registers the started activity's update token under the server's ID,
      # and the document the start carried isn't pushed again.
      assert {:ok, %LiveActivity{expires_at: expires_at}} = LiveActivities.register(user, session, id, params())
      assert DateTime.diff(expires_at, DateTime.utc_now()) > 7 * 60 * 60
      assert :continue = LiveActivities.deliver(id)
    end

    test "waits an hour after a start the device never registered", %{user: user, session: session} do
      run!(thread!(user, "Fix login redirect loop", "running"), "running")
      :ok = LiveActivities.register_starter(user, session, starter_params(token()))
      starter = Repo.one!(LiveActivityStarter)
      test_pid = self()

      stub(Req, :post, fn _url, _opts ->
        send(test_pid, :pushed)
        {:ok, %Req.Response{status: 200, body: ""}}
      end)

      assert :ok = LiveActivities.start(starter.id)
      assert_received :pushed
      [%LiveActivity{id: pending}] = Repo.all(LiveActivity)

      # Ten minutes later the device still hasn't registered it.
      Repo.update_all(from(a in LiveActivity, where: a.id == ^pending), set: [expires_at: ago(1)])
      assert :ok = LiveActivities.start(starter.id)
      refute_received :pushed

      # Registering it now is too late: the server may have started another.
      assert {:error, :retired} = LiveActivities.register(user, session, pending, params())

      # Pruned as expired, it still holds off the next start until the hour is up.
      LiveActivities.prune()
      assert %LiveActivity{retired_reason: "expired"} = Repo.get!(LiveActivity, pending)
      assert :ok = LiveActivities.start(starter.id)
      refute_received :pushed

      Repo.update_all(LiveActivityStarter, set: [last_started_at: ago(61 * 60)])
      assert :ok = LiveActivities.start(starter.id)
      assert_received :pushed
      assert 2 = Repo.aggregate(LiveActivity, :count)
    end

    test "a start the device registered doesn't hold off the next", %{user: user, session: session} do
      thread = thread!(user, "Fix login redirect loop", "running")
      run!(thread, "running")
      :ok = LiveActivities.register_starter(user, session, starter_params(token()))
      starter = Repo.one!(LiveActivityStarter)

      expect(Req, :post, fn _url, _opts -> {:ok, %Req.Response{status: 200, body: ""}} end)
      assert :ok = LiveActivities.start(starter.id)
      [%LiveActivity{id: started}] = Repo.all(LiveActivity)
      {:ok, _} = LiveActivities.register(user, session, started, params())
      :ok = LiveActivities.unregister(user, started)

      expect(Req, :post, fn _url, _opts -> {:ok, %Req.Response{status: 200, body: ""}} end)
      assert :ok = LiveActivities.start(starter.id)
      assert 2 = Repo.aggregate(LiveActivity, :count)
    end

    test "an activity the app starts itself replaces a pending one", %{user: user, session: session} do
      run!(thread!(user, "Fix login redirect loop", "running"), "running")
      :ok = LiveActivities.register_starter(user, session, starter_params(token()))

      expect(Req, :post, fn _url, _opts -> {:ok, %Req.Response{status: 200, body: ""}} end)
      assert :ok = LiveActivities.start(Repo.one!(LiveActivityStarter).id)
      [%LiveActivity{id: pending}] = Repo.all(LiveActivity)

      local = Ecto.UUID.generate()
      {:ok, _} = LiveActivities.register(user, session, local, params())
      assert %LiveActivity{retired_reason: "replaced"} = Repo.get!(LiveActivity, pending)
      assert {:error, :retired} = LiveActivities.register(user, session, pending, params())
    end

    test "rolls back the pending registration when APNs asks to retry, and retires it when rejected", %{
      user: user,
      session: session
    } do
      run!(thread!(user, "Fix login redirect loop", "running"), "running")
      :ok = LiveActivities.register_starter(user, session, starter_params(token()))
      starter = Repo.one!(LiveActivityStarter)

      expect(Req, :post, fn _url, _opts ->
        {:ok, %Req.Response{status: 503, body: ~s({"reason":"ServiceUnavailable"})}}
      end)

      assert {:retry, "ServiceUnavailable"} = LiveActivities.start(starter.id)
      assert [] = Repo.all(LiveActivity)
      assert %LiveActivityStarter{last_start_id: nil} = Repo.get!(LiveActivityStarter, starter.id)

      expect(Req, :post, fn _url, _opts -> {:ok, %Req.Response{status: 400, body: ~s({"reason":"BadPriority"})}} end)
      assert {:cancel, "BadPriority"} = LiveActivities.start(starter.id)
      assert [%LiveActivity{retired_reason: "rejected"}] = Repo.all(LiveActivity)

      # A rejected start isn't the device's fault: the next one goes ahead.
      expect(Req, :post, fn _url, _opts -> {:ok, %Req.Response{status: 200, body: ""}} end)
      assert :ok = LiveActivities.start(starter.id)
    end

    test "forgets the token once its sign-in ends or APNs rejects it", %{user: user, session: session} do
      run!(thread!(user, "Fix login redirect loop", "running"), "running")
      :ok = LiveActivities.register_starter(user, session, starter_params(token()))
      starter = Repo.one!(LiveActivityStarter)

      expect(Req, :post, fn _url, _opts -> {:ok, %Req.Response{status: 410, body: ~s({"reason":"Unregistered"})}} end)
      assert :ok = LiveActivities.start(starter.id)
      assert [] = Repo.all(LiveActivityStarter)
      assert [%LiveActivity{retired_reason: "invalid_token"}] = Repo.all(LiveActivity)

      :ok = LiveActivities.register_starter(user, session, starter_params(token()))
      Repo.update_all(Token, set: [revoked_at: DateTime.utc_now()])
      reject(&Req.post/2)
      assert :ok = LiveActivities.start(Repo.one!(LiveActivityStarter).id)
      assert [] = Repo.all(LiveActivityStarter)
    end

    test "a thread change only wakes starters while threads are working", %{user: user, session: session} do
      stub(Environment, :apns_configured?, fn -> true end)
      thread = thread!(user, "Fix login redirect loop", "idle")
      :ok = LiveActivities.register_starter(user, session, starter_params(token()))

      LiveActivities.thread_changed(user.id)
      assert [] = all_enqueued(worker: LiveActivityStartWorker)

      Repo.update!(Ecto.Changeset.change(thread, agent_status: "queued"))
      LiveActivities.thread_changed(user.id)
      assert [_] = all_enqueued(worker: LiveActivityStartWorker)
    end

    test "prune forgets tokens no app registered for 60 days", %{user: user, session: session} do
      :ok = LiveActivities.register_starter(user, session, starter_params(token()))
      other = AccountsFixtures.user_fixture()
      :ok = LiveActivities.register_starter(other, luft_session(other), starter_params(token()))
      Repo.update_all(from(s in LiveActivityStarter, where: s.user_id == ^user.id), set: [updated_at: ago(61 * 86_400)])

      assert %{starters: 1} = LiveActivities.prune()
      assert [%LiveActivityStarter{user_id: user_id}] = Repo.all(LiveActivityStarter)
      assert user_id == other.id
    end

    test "doesn't start one while nothing is working", %{user: user, session: session} do
      thread!(user, "Fix login redirect loop", "idle")
      :ok = LiveActivities.register_starter(user, session, starter_params(token()))

      reject(&Req.post/2)
      assert :ok = LiveActivities.start(Repo.one!(LiveActivityStarter).id)
      assert [] = Repo.all(LiveActivity)
    end

    test "a token moves with the profile its device signs in as", %{user: user, session: session} do
      start_token = token()
      :ok = LiveActivities.register_starter(user, session, starter_params(start_token))
      other = AccountsFixtures.user_fixture()
      :ok = LiveActivities.register_starter(other, luft_session(other), starter_params(start_token))

      assert [%LiveActivityStarter{user_id: user_id}] = Repo.all(LiveActivityStarter)
      assert user_id == other.id

      assert {:error, :invalid} =
               LiveActivities.register_starter(user, session, %{starter_params(token()) | "profile_id" => "../x"})
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
  defp starter_params(token), do: Map.put(params(token), "profile_id", "profile_1")

  defp ago(seconds), do: DateTime.utc_now() |> DateTime.add(-seconds) |> DateTime.truncate(:second)

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
