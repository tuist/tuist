defmodule LuftServer.NotificationsTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: LuftServer.Repo

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias LuftServer.Notifications
  alias LuftServer.Notifications.Delegation
  alias LuftServer.Notifications.LiveActivities
  alias LuftServer.Notifications.LiveActivity
  alias LuftServer.Notifications.LiveActivityStarter
  alias LuftServer.Notifications.LiveActivityWorker
  alias LuftServer.Notifications.ThreadFinishedWorker
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServer.Threads.Message
  alias LuftServer.Threads.Run
  alias LuftServer.Threads.Thread
  alias LuftServer.Threads.ToolCall

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)
    upstream()
    session = session(1)
    %{session: session, actor: Delegation.actor(session.id, 1), grant: grant(session)}
  end

  test "projects local runs and tool phases without prompts, targets or tool arguments", ctx do
    thread = thread(ctx.session, "running")
    run = Repo.insert!(%Run{thread_id: thread.id, status: "running"})
    call(run, 1, "Read", "completed")

    call(run, 2, "Bash", "executing", %{
      "command" => "build",
      "state" => "running",
      "planned" => 40,
      "done" => 12,
      "target" => "secret-target"
    })

    {document, [id]} = LiveActivities.content(ctx.actor)
    assert id == thread.id

    assert [
             %{
               "phase" => "building",
               "detail" => "Building · 12 of 40 targets",
               "progress" => %{"done" => 12, "total" => 40},
               "trail" => ["blue", "orange"],
               "snooze_link" => snooze,
               "link" => link
             }
           ] = document["threads"]

    assert String.starts_with?(link, "luft://app/threads/#{thread.id}?")
    assert URI.decode_query(URI.parse(link).query)["server"] == "https://luft.test"
    assert snooze =~ "/snooze?"

    for secret <- ["private prompt", "secret-target", "tool-secret"],
        do: refute(JSON.encode!(document) =~ secret)
  end

  test "initial titles never expose the first prompt", ctx do
    thread = thread(ctx.session, "running")
    Repo.update!(Ecto.Changeset.change(thread, title: thread.goal))
    {document, _} = LiveActivities.content(ctx.actor)
    assert [%{"headline" => "Your thread"}] = document["threads"]
  end

  test "shows just-finished rows once and excludes snoozed work", ctx do
    working = thread(ctx.session, "compacting")
    finished = thread(ctx.session, "idle")
    snoozed = thread(ctx.session, "running")
    Repo.update!(Ecto.Changeset.change(snoozed, snoozed_until_needed: true))
    {document, ids} = LiveActivities.content(ctx.actor, [finished.id, snoozed.id])
    assert ids == [working.id]
    assert [%{"phase" => "done"}, %{"phase" => "thinking"}] = document["threads"]
    assert {%{"threads" => [_]}, [_]} = LiveActivities.content(ctx.actor, ids)
  end

  test "requires original exact delegation even when another owner session remains", ctx do
    thread(ctx.session, "running")
    other = session(1)
    Repo.delete!(ctx.session)
    assert {%{"threads" => []}, []} = LiveActivities.content(Delegation.actor(other.id, 1))
  end

  test "authoritative account loss hides conversations, while transient errors retry", ctx do
    thread(ctx.session, "running")
    Req.Test.stub(LuftServer.Tuist, fn conn -> Plug.Conn.send_resp(conn, 403, "") end)
    assert {%{"threads" => []}, []} = LiveActivities.content(ctx.actor)
    Req.Test.stub(LuftServer.Tuist, fn conn -> Plug.Conn.send_resp(conn, 503, "") end)

    assert_raise RuntimeError, ~r/temporarily unavailable/, fn ->
      LiveActivities.content(ctx.actor)
    end
  end

  test "registration IDs are monotonic and cannot move to another sign-in", ctx do
    id = Ecto.UUID.generate()
    assert {:ok, _} = LiveActivities.register(ctx.actor, ctx.grant, id, params())
    other = session(1)

    assert {:error, :conflict} =
             LiveActivities.register(Delegation.actor(other.id, 1), grant(other), id, params())

    assert :ok = LiveActivities.unregister(ctx.actor, id)
    assert {:error, :retired} = LiveActivities.register(ctx.actor, ctx.grant, id, params())
    late = Ecto.UUID.generate()
    :ok = LiveActivities.unregister(ctx.actor, late)
    assert {:error, :retired} = LiveActivities.register(ctx.actor, ctx.grant, late, params())
  end

  test "new local activity replaces the old one and token supersession is monotonic", ctx do
    first = Ecto.UUID.generate()
    assert {:ok, _} = LiveActivities.register(ctx.actor, ctx.grant, first, params())

    assert {:ok, _} =
             LiveActivities.register(ctx.actor, ctx.grant, Ecto.UUID.generate(), params())

    assert Repo.get!(LiveActivity, first).retired_reason == "replaced"
    assert {:error, :retired} = LiveActivities.register(ctx.actor, ctx.grant, first, params())
  end

  test "delivery dedupes, maintains heartbeat priority and ends with finished state", ctx do
    thread = thread(ctx.session, "running")
    id = Ecto.UUID.generate()
    {:ok, _} = LiveActivities.register(ctx.actor, ctx.grant, id, params())
    assert :continue = LiveActivities.deliver(id)

    assert_receive {:dispatch,
                    %{
                      "options" => %{"priority" => 10},
                      "payload" => %{"aps" => %{"event" => "update"}}
                    }}

    backdate(id, 1)
    assert :continue = LiveActivities.deliver(id)
    refute_receive {:dispatch, _}
    backdate(id, 61)
    assert :continue = LiveActivities.deliver(id)
    assert_receive {:dispatch, %{"options" => %{"priority" => 5}}}
    backdate(id, 1)
    Repo.update!(Ecto.Changeset.change(thread, agent_status: "idle"))
    assert :done = LiveActivities.deliver(id)

    assert_receive {:dispatch,
                    %{
                      "options" => %{"priority" => 10},
                      "payload" => %{"aps" => %{"event" => "end", "dismissal-date" => _}}
                    }}

    assert Repo.get!(LiveActivity, id).retired_reason == "ended"
    assert Repo.get!(LiveActivity, id).token == nil
  end

  test "expired or deleted sessions retire their activities without finding a replacement", ctx do
    id = Ecto.UUID.generate()
    {:ok, _} = LiveActivities.register(ctx.actor, ctx.grant, id, params())
    session(1)
    Repo.delete!(ctx.session)
    assert :done = LiveActivities.deliver(id)
    assert Repo.get!(LiveActivity, id).retired_reason == "session_ended"
    refute_receive {:dispatch, _}
  end

  test "upstream revocation stops delivery", ctx do
    thread(ctx.session, "running")
    id = Ecto.UUID.generate()
    {:ok, _} = LiveActivities.register(ctx.actor, ctx.grant, id, params())
    upstream(403)
    assert :done = LiveActivities.deliver(id)
    assert Repo.get!(LiveActivity, id).retired_reason == "invalid_token"
  end

  test "push-to-start retains profile and Luft origin then accepts the update token", ctx do
    thread(ctx.session, "running")

    :ok =
      LiveActivities.register_starter(
        ctx.actor,
        ctx.grant,
        Map.put(params(), "profile_id", "profile_1")
      )

    starter = Repo.one!(LiveActivityStarter)
    assert :ok = LiveActivities.start(starter.id)

    assert_receive {:dispatch,
                    %{
                      "payload" => %{
                        "aps" => %{
                          "event" => "start",
                          "input-push-token" => 1,
                          "attributes" => %{
                            "server" => "https://luft.test",
                            "profileID" => "profile_1",
                            "registrationID" => id
                          }
                        }
                      }
                    }}

    assert :ok = LiveActivities.start(starter.id)
    refute_receive {:dispatch, _}
    assert {:ok, row} = LiveActivities.register(ctx.actor, ctx.grant, id, params())
    assert DateTime.diff(row.expires_at, DateTime.utc_now()) > 7 * 3600
    assert :continue = LiveActivities.deliver(id)
    refute_receive {:dispatch, _}
  end

  test "unregistered pushed starts back off for an hour and reject late tokens", ctx do
    thread(ctx.session, "running")

    :ok =
      LiveActivities.register_starter(
        ctx.actor,
        ctx.grant,
        Map.put(params(), "profile_id", "profile_1")
      )

    starter = Repo.one!(LiveActivityStarter)
    :ok = LiveActivities.start(starter.id)
    assert_receive {:dispatch, _}
    pending = Repo.one!(LiveActivity)
    Repo.update!(Ecto.Changeset.change(pending, expires_at: ago(1)))
    assert :ok = LiveActivities.start(starter.id)
    refute_receive {:dispatch, _}

    assert {:error, :retired} =
             LiveActivities.register(ctx.actor, ctx.grant, pending.id, params())

    LiveActivities.prune()
    assert :ok = LiveActivities.start(starter.id)
    refute_receive {:dispatch, _}
    Repo.update!(Ecto.Changeset.change(starter, last_started_at: ago(3660)))
    assert :ok = LiveActivities.start(starter.id)
    assert_receive {:dispatch, _}
  end

  test "transient push failure rolls back pending start; invalid token deletes starter", ctx do
    thread(ctx.session, "running")

    :ok =
      LiveActivities.register_starter(
        ctx.actor,
        ctx.grant,
        Map.put(params(), "profile_id", "profile_1")
      )

    starter = Repo.one!(LiveActivityStarter)
    upstream(503)
    assert {:retry, :tuist_unavailable} = LiveActivities.start(starter.id)
    assert [] = Repo.all(LiveActivity)
    assert Repo.reload!(starter).last_start_id == nil
    upstream(410)
    assert :ok = LiveActivities.start(starter.id)
    assert [] = Repo.all(LiveActivityStarter)
    assert Repo.one!(LiveActivity).retired_reason == "invalid_token"
  end

  test "transaction hooks commit jobs with state and dedupe repeated changes", ctx do
    thread = thread(ctx.session, "running")
    {:ok, _} = LiveActivities.register(ctx.actor, ctx.grant, Ecto.UUID.generate(), params())
    Repo.delete_all(Oban.Job)

    assert {:error, :abort} =
             Repo.transaction(fn ->
               Notifications.notify_thread_finished(thread, "idle")
               Repo.rollback(:abort)
             end)

    assert [] = all_enqueued()

    assert {:ok, :ok} =
             Repo.transaction(fn ->
               Notifications.thread_changed(thread)
               Notifications.notify_thread_finished(thread, "idle")
             end)

    Notifications.notify_thread_finished(thread, "idle")
    assert [_] = all_enqueued(worker: LiveActivityWorker)
    assert [_] = all_enqueued(worker: ThreadFinishedWorker)
  end

  test "completion alerts suppress timed snoozes and preserve safe native fields", ctx do
    thread = thread(ctx.session, "idle")

    thread =
      Repo.update!(
        Ecto.Changeset.change(thread,
          snoozed_until: DateTime.shift(DateTime.utc_now(:second), hour: 1)
        )
      )

    args = %{"thread_id" => thread.id, "revision" => 1, "status" => "idle"}
    assert :ok = perform_job(ThreadFinishedWorker, args)
    refute_receive {:dispatch, _}
    assert :ok = perform_job(ThreadFinishedWorker, %{args | "status" => "snooze_ended"})

    assert_receive {:dispatch,
                    %{
                      "kind" => "alert",
                      "payload" => %{
                        "account" => "team",
                        "user" => "one",
                        "thread_id" => id,
                        "aps" => %{
                          "alert" => %{"body" => "Your snooze is over. Tap to pick it up."}
                        }
                      }
                    }}

    assert id == thread.id
  end

  defp upstream(status \\ 204) do
    pid = self()

    Req.Test.stub(LuftServer.Tuist, fn conn ->
      case conn.request_path do
        "/api/accounts/team/luft-context" ->
          Req.Test.json(conn, %{
            user_id: 1,
            account_id: 100,
            organization_id: 10,
            can_create_threads: true,
            people: [%{id: 1, handle: "one", active: true}]
          })

        "/api/me/luft-notifications" ->
          assert ["Bearer upstream-1"] = Plug.Conn.get_req_header(conn, "authorization")
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(pid, {:dispatch, JSON.decode!(body)})
          Plug.Conn.send_resp(conn, status, "")
      end
    end)
  end

  defp session(id) do
    {:ok, _, session} =
      Sessions.create(%{
        claims: %{"sub" => to_string(id), "preferred_username" => "one"},
        tokens: %{
          "access_token" => "upstream-#{id}",
          "refresh_token" => "refresh",
          "expires_in" => 3600
        }
      })

    session
  end

  defp grant(session), do: %{app: "luft", oauth_grant_id: session.id}

  defp params,
    do: %{"token" => Base.encode16(:crypto.strong_rand_bytes(32)), "environment" => "sandbox"}

  defp thread(session, status) do
    Repo.insert!(%Thread{
      account_id: 100,
      account_handle: "team",
      owner_id: 1,
      owner_session_id: session.id,
      request_id: Ecto.UUID.generate(),
      request_hash: :crypto.strong_rand_bytes(32),
      title: "Fix login",
      goal: "private prompt",
      provider: "chatgpt",
      model: "selected",
      agent_status: status
    })
  end

  defp call(run, position, name, status, progress \\ nil) do
    message =
      Repo.insert!(%Message{
        thread_id: run.thread_id,
        position: position,
        kind: "tool",
        body: "tool-secret",
        progress: progress
      })

    Repo.insert!(%ToolCall{
      run_id: run.id,
      message_id: message.id,
      fingerprint: :crypto.strong_rand_bytes(32),
      name: name,
      status: status,
      result: "tool-secret"
    })
  end

  defp ago(seconds), do: DateTime.shift(DateTime.utc_now(:second), second: -seconds)

  defp backdate(id, seconds),
    do:
      Repo.update_all(from(a in LiveActivity, where: a.id == ^id),
        set: [last_sent_at: ago(seconds)]
      )
end
