defmodule Atlas.Push.OrbitLiveActivityTest do
  use Atlas.DataCase, async: true
  use Oban.Testing, repo: Atlas.Repo
  use Mimic

  import Atlas.OrbitFixtures, only: [user_fixture: 0]
  import Atlas.PushFixtures

  alias Atlas.Orbit
  alias Atlas.Orbit.Agent
  alias Atlas.Orbit.Notifier
  alias Atlas.Orbit.Progress
  alias Atlas.Orbit.Run
  alias Atlas.Orbit.Runs
  alias Atlas.Push
  alias Atlas.Push.Config
  alias Atlas.Push.LiveActivity
  alias Atlas.Push.OrbitLiveActivity
  alias Atlas.Push.Workers.Deliver
  alias Atlas.Push.Workers.UpdateLiveActivity
  alias Boruta.Ecto.Token

  setup do
    test_pid = self()
    apns = apns_config()
    now = DateTime.utc_now()
    stub(DateTime, :utc_now, fn -> now end)
    stub(Config, :apns, fn -> {:ok, apns} end)
    stub(Config, :available?, fn "ios", _ -> true end)
    stub(Config, :capabilities, fn -> %{"ios" => true, "android" => false} end)

    stub(Config, :req_options, fn ->
      [
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(test_pid, {:apns, conn.host, conn.request_path, Map.new(conn.req_headers), JSON.decode!(body)})
          Req.Test.json(conn, %{})
        end
      ]
    end)

    user = user_fixture()
    client_id = native_client_id(user)
    id = Ecto.UUID.generate()
    params = %{"token" => ios_token(), "environment" => "sandbox"}
    :ok = OrbitLiveActivity.register(user, client_id, id, params)
    %{user: user, id: id, client_id: client_id, now: now, params: params}
  end

  test "queued -> tools -> compaction -> completion is truthful, silent, ordered and fenced", ctx do
    %{user: user, id: id, now: now, params: params} = ctx
    {thread, run} = run(user, "queued", "Cash flow forecast")
    assert :ok = deliver(id)
    assert_received {:apns, "api.sandbox.push.apple.com", path, headers, %{"aps" => aps}}
    assert path == "/3/device/" <> params["token"]
    assert headers["apns-topic"] == "dev.tuist.atlas.push-type.liveactivity"
    assert headers["apns-push-type"] == "liveactivity"
    assert headers["apns-priority"] == "5"
    assert headers["apns-collapse-id"] == id
    assert String.starts_with?(headers["authorization"], "bearer ")
    assert String.to_integer(headers["apns-expiration"]) == DateTime.to_unix(now) + 120
    assert aps["event"] == "update"
    assert aps["stale-date"] == aps["timestamp"] + 120

    assert aps["content-state"] == %{
             "active_count" => 1,
             "updated_at" => DateTime.to_unix(now),
             "conversations" => [
               %{
                 "id" => thread.id,
                 "title" => "Cash flow forecast",
                 "status" => "queued",
                 "started_at" => DateTime.to_unix(run.inserted_at),
                 "completed_steps" => 0
               }
             ]
           }

    assert byte_size(JSON.encode!(%{"aps" => aps})) < 4096
    refute Map.has_key?(aps, "alert")
    refute Map.has_key?(aps, "sound")

    assert :ok = deliver(id)
    refute_received {:apns, _, _, _, _}
    run = Repo.update!(Ecto.Changeset.change(run, status: "running", started_at: now, session_id: Ecto.UUID.generate()))
    Repo.update!(Ecto.Changeset.change(thread, title: "  Revised\n\u200B\u202E\u0001 forecast\t "))

    tool =
      Repo.transaction(fn ->
        Orbit.append!(thread, %{
          kind: "tool",
          run_id: run.id,
          tool_name: "never-send-this-name",
          tool_status: "running",
          tool_input: "private argument",
          tool_output: "private output"
        })
      end)
      |> elem(1)

    assert {:snooze, 1} = deliver(id)
    refute_received {:apns, _, _, _, _}
    at(now, 1)
    assert :ok = deliver(id)

    assert_received {:apns, _, _, _,
                     %{
                       "aps" => %{
                         "content-state" => %{
                           "conversations" => [
                             %{"title" => "Revised forecast", "status" => "using_tools", "completed_steps" => 0}
                           ]
                         }
                       }
                     }}

    Repo.transaction(fn -> Orbit.touch!(tool, %{tool_status: "succeeded"}) end)
    Progress.handle_event([:condukt, :compact, :start], %{}, %{agent: Agent, session_id: run.session_id}, nil)
    at(now, 2)
    assert :ok = deliver(id)

    assert_received {:apns, _, _, _,
                     %{
                       "aps" => %{
                         "content-state" => %{"conversations" => [%{"status" => "compacting", "completed_steps" => 1}]}
                       }
                     }}

    Progress.handle_event(
      [:condukt, :compact, :stop],
      %{},
      %{agent: Agent, session_id: run.session_id, changed: false},
      nil
    )

    at(now, 3)
    assert :ok = deliver(id)

    assert_received {:apns, _, _, _,
                     %{
                       "aps" => %{
                         "content-state" => %{"conversations" => [%{"status" => "running", "completed_steps" => 1}]}
                       }
                     }}

    assert :ok = Runs.complete(run.id, 0, {:ok, "Private final reply"})
    at(now, 4)
    assert :ok = deliver(id)
    assert_received {:apns, _, _, _, %{"aps" => ending}}
    assert ending["event"] == "end"
    assert ending["dismissal-date"] == ending["timestamp"]

    assert ending["content-state"] == %{
             "active_count" => 0,
             "conversations" => [],
             "updated_at" => DateTime.to_unix(now) + 4
           }

    assert Repo.get!(LiveActivity, id).token == nil
    assert :stale = Runs.complete(run.id, 0, {:ok, "Stale final reply"})
    Progress.handle_event([:condukt, :compact, :start], %{}, %{agent: Agent, session_id: run.session_id}, nil)
    assert :ok = deliver(id)
    assert {:error, :retired} = OrbitLiveActivity.register(user, ctx.client_id, id, params)
    refute_received {:apns, _, _, _, _}
  end

  test "aggregate retains concurrent work after one run ends and never shows another actor's run", ctx do
    {first, a} = run(ctx.user, "running", "Cash flow forecast")
    {second, b} = run(ctx.user, "running", "Berlin team holiday plan")
    other = user_fixture()
    {:ok, shared} = Orbit.create_shared(ctx.user, %{"title" => "Secret", "participant_ids" => [other.id]})
    Repo.insert!(%Run{thread_id: shared.id, acting_user_id: other.id, trigger_seq: 0})
    assert :ok = deliver(ctx.id)
    assert_received {:apns, _, _, _, %{"aps" => %{"content-state" => content}}}
    assert content["active_count"] == 2
    assert Enum.map(content["conversations"], & &1["id"]) == Enum.map(Enum.sort_by([a, b], & &1.id), & &1.thread_id)

    assert Map.new(content["conversations"], &{&1["id"], &1["title"]}) ==
             %{first.id => "Cash flow forecast", second.id => "Berlin team holiday plan"}

    refute JSON.encode!(content) =~ "Secret"
    Repo.update!(Ecto.Changeset.change(second, title: " \t\u200B\u202E\u0001 "))
    assert :ok = Runs.complete(a.id, 0, {:ok, "Done"})
    at(ctx.now, 1)
    assert :ok = deliver(ctx.id)

    assert_received {:apns, _, _, _,
                     %{
                       "aps" => %{
                         "event" => "update",
                         "content-state" => %{
                           "active_count" => 1,
                           "conversations" => [%{"id" => id, "title" => "Conversation"}]
                         }
                       }
                     }}

    assert id == second.id
    assert :ok = Runs.complete(b.id, 0, {:ok, "Done"})
    at(ctx.now, 2)
    assert :ok = deliver(ctx.id)
    assert_received {:apns, _, _, _, %{"aps" => %{"event" => "end"}}}
  end

  for boundary <- [:archive, :cancel, :signout, :access_loss, :membership_loss, :expiry, :delete, :user_deleted] do
    test "#{boundary} ends with empty state and drops token even if the wakeup was lost", ctx do
      {thread, run} = run(ctx.user, "running", "Authorized title before revocation")
      assert :ok = deliver(ctx.id)

      assert_received {:apns, _, _, _,
                       %{
                         "aps" => %{
                           "content-state" => %{"conversations" => [%{"title" => "Authorized title before revocation"}]}
                         }
                       }}

      case unquote(boundary) do
        :archive ->
          assert {:ok, _} = Orbit.set_status(ctx.user, thread, "archived")

        :cancel ->
          assert {:ok, _} = Orbit.cancel_run(ctx.user, thread, run.id)

        :signout ->
          Repo.update_all(from(t in Token, where: t.client_id == ^ctx.client_id),
            set: [refresh_token_revoked_at: NaiveDateTime.utc_now()]
          )

        :access_loss ->
          Repo.update!(Ecto.Changeset.change(thread, required_scopes: ["finance:read"]))

        :membership_loss ->
          Repo.delete_all(from p in Orbit.Participant, where: p.thread_id == ^thread.id and p.user_id == ^ctx.user.id)

        :expiry ->
          at(ctx.now, 28_801)

        :delete ->
          assert :ok = OrbitLiveActivity.unregister(ctx.user, ctx.client_id, ctx.id)

        :user_deleted ->
          Repo.delete!(ctx.user)
      end

      if unquote(boundary) != :expiry, do: at(ctx.now, 1)
      assert {:ok, 1} = OrbitLiveActivity.reconcile()
      assert :ok = deliver(ctx.id)

      assert_received {:apns, _, _, _,
                       %{"aps" => %{"event" => "end", "content-state" => %{"active_count" => 0, "conversations" => []}}}}

      assert %{token: nil, user_id: nil, retired_at: %DateTime{}} = Repo.get!(LiveActivity, ctx.id)
      assert :ok = deliver(ctx.id)
      refute_received {:apns, _, _, _, _}
    end
  end

  test "provider retry recomputes state; invalidation cannot be revived by delayed registration", ctx do
    {_thread, run} = run(ctx.user)
    respond(429, %{}, [{"retry-after", "12"}])
    assert {:snooze, 12} = deliver(ctx.id)
    assert_received {:apns, _}
    assert :ok = Runs.complete(run.id, 0, {:ok, "Finished while waiting"})
    respond(200)
    assert :ok = deliver(ctx.id)
    assert_received {:apns, 200}
    assert Repo.get!(LiveActivity, ctx.id).token == nil

    fresh_id = Ecto.UUID.generate()
    assert :ok = OrbitLiveActivity.register(ctx.user, ctx.client_id, fresh_id, ctx.params)
    run(ctx.user)
    respond(410, %{"timestamp" => DateTime.to_unix(ctx.now, :millisecond)})
    assert {:cancel, :token_invalidated} = deliver(fresh_id)
    assert_received {:apns, 410}
    assert {:error, :retired} = OrbitLiveActivity.register(ctx.user, ctx.client_id, fresh_id, ctx.params)
  end

  test "permanent configuration errors keep live tokens; end retries have a bounded cleanup", ctx do
    {_thread, run} = run(ctx.user)
    respond(403, %{"reason" => "TopicDisallowed"})
    assert {:cancel, :apns_credentials_rejected} = deliver(ctx.id)
    assert Repo.get!(LiveActivity, ctx.id).token != nil
    Runs.complete(run.id, 0, {:ok, "Done"})
    respond(503)
    assert {:error, :provider_unavailable} = deliver(ctx.id)
    at(ctx.now, 121)
    assert {:cancel, :end_expired} = deliver(ctx.id)
    assert Repo.get!(LiveActivity, ctx.id).token == nil
  end

  test "provider update expiry and stale-date never extend the registration lifetime", ctx do
    run(ctx.user)
    expires_at = DateTime.add(ctx.now, 30)
    LiveActivity |> Repo.get!(ctx.id) |> Ecto.Changeset.change(expires_at: expires_at) |> Repo.update!()
    assert :ok = deliver(ctx.id)
    assert_received {:apns, _, _, headers, %{"aps" => aps}}
    assert String.to_integer(headers["apns-expiration"]) == DateTime.to_unix(expires_at)
    assert aps["stale-date"] == DateTime.to_unix(expires_at)
    at(ctx.now, 31)
    assert :ok = deliver(ctx.id)
    assert_received {:apns, _, _, _, %{"aps" => %{"event" => "end", "content-state" => %{"active_count" => 0}}}}
  end

  test "terminal end retries clear tokens on their last attempt", ctx do
    respond(503)

    assert {:cancel, :end_expired} =
             UpdateLiveActivity.perform(%Oban.Job{
               args: %{"registration_id" => ctx.id},
               attempt: 5,
               max_attempts: 5
             })

    assert %{token: nil, token_hash: nil, user_id: nil, retired_at: %DateTime{}} = Repo.get!(LiveActivity, ctx.id)
  end

  test "normal refresh rotation keeps delivery authorized; expired refresh grants end it", ctx do
    run(ctx.user)
    rotate_refresh_grant(ctx.client_id, ctx.user)
    assert :ok = deliver(ctx.id)
    assert_received {:apns, _, _, _, _}
    Repo.update_all(from(t in Token, where: t.client_id == ^ctx.client_id), set: [inserted_at: ~N[2000-01-01 00:00:00]])
    at(ctx.now, 1)
    assert :ok = deliver(ctx.id)
    assert_received {:apns, _, _, _, %{"aps" => %{"event" => "end"}}}
  end

  test "id-only notifier invalidations coalesce jobs, and sweep refreshes stale-date without progress inflation", ctx do
    {thread, _run} = run(ctx.user)

    assert {:noreply, %{sweeps: 0}} =
             Notifier.handle_info({:notification, :atlas_orbit, %{"thread_id" => thread.id}}, %{sweeps: 0})

    OrbitLiveActivity.thread_changed(thread.id)
    assert [%{args: %{"registration_id" => id}}] = all_enqueued(worker: UpdateLiveActivity)
    assert id == ctx.id
    assert :ok = deliver(id)
    assert_received {:apns, _, _, _, %{"aps" => %{"timestamp" => first}}}
    at(ctx.now, 61)
    assert {:ok, 1} = OrbitLiveActivity.reconcile()
    assert :ok = deliver(id)

    assert_received {:apns, _, _, _,
                     %{
                       "aps" => %{
                         "timestamp" => second,
                         "content-state" => %{"conversations" => [%{"completed_steps" => 0}]}
                       }
                     }}

    assert second > first
  end

  test "Live Activities neither enqueue a second completion alert nor suppress the existing opted-in alert", ctx do
    {thread, run} = run(ctx.user)
    {:ok, _installation} = Push.register(ctx.user, ctx.client_id, Ecto.UUID.generate(), ios_device())
    assert :ok = Runs.complete(run.id, 0, {:ok, "Authorized reply"})
    assert [%{args: %{"kind" => "orbit_completed", "record_id" => id}}] = all_enqueued(worker: Deliver)
    assert id == thread.id
    assert :ok = deliver(ctx.id)
    assert length(all_enqueued(worker: Deliver)) == 1
  end

  test "registration and queued delivery roll back together", ctx do
    id = Ecto.UUID.generate()

    assert {:error, :abort} =
             Repo.transaction(fn ->
               :ok =
                 OrbitLiveActivity.register(ctx.user, ctx.client_id, id, %{
                   "token" => ios_token(),
                   "environment" => "production"
                 })

               Repo.rollback(:abort)
             end)

    refute Repo.get(LiveActivity, id)
    refute_enqueued(worker: UpdateLiveActivity, args: %{registration_id: id})
    assert Repo.get!(LiveActivity, ctx.id).retired_at == nil
  end

  test "new aggregate replaces only the same binding, and a stale PUT cannot reclaim its token", ctx do
    run(ctx.user)
    id = Ecto.UUID.generate()
    params = %{"token" => ios_token(), "environment" => "production"}
    assert :ok = OrbitLiveActivity.register(ctx.user, ctx.client_id, id, params)
    assert Repo.get!(LiveActivity, ctx.id).retired_at
    assert {:error, :retired} = OrbitLiveActivity.register(ctx.user, ctx.client_id, ctx.id, ctx.params)
    assert :ok = deliver(ctx.id)
    assert_received {:apns, _, _, _, %{"aps" => %{"event" => "end", "content-state" => %{"conversations" => []}}}}
    assert :ok = deliver(id)
    assert_received {:apns, "api.push.apple.com", _, _, %{"aps" => %{"event" => "update"}}}
    other = user_fixture()

    assert {:error, :conflict} =
             OrbitLiveActivity.register(other, native_client_id(other), Ecto.UUID.generate(), params)

    assert Repo.get!(LiveActivity, id).token == params["token"]
  end

  test "the user cap rejects another binding but allows refresh and replacement at the cap", ctx do
    for _ <- 1..9 do
      assert :ok =
               OrbitLiveActivity.register(ctx.user, native_client_id(ctx.user), Ecto.UUID.generate(), %{
                 "token" => ios_token(),
                 "environment" => "production"
               })
    end

    assert :ok = OrbitLiveActivity.register(ctx.user, ctx.client_id, ctx.id, ctx.params)
    replacement = Ecto.UUID.generate()

    assert :ok =
             OrbitLiveActivity.register(ctx.user, ctx.client_id, replacement, %{
               "token" => ios_token(),
               "environment" => "production"
             })

    assert Repo.get!(LiveActivity, ctx.id).retired_at

    assert {:error, :conflict} =
             OrbitLiveActivity.register(ctx.user, native_client_id(ctx.user), Ecto.UUID.generate(), %{
               "token" => ios_token(),
               "environment" => "production"
             })

    assert Repo.aggregate(from(r in LiveActivity, where: is_nil(r.retired_at)), :count) == 10
  end

  test "bounded reconciliation rotates through a larger registry, and pruning keeps recent tombstones", ctx do
    old = DateTime.add(ctx.now, -1, :day)
    Repo.update_all(LiveActivity, set: [reconciled_at: old])

    for _ <- 1..100 do
      token = ios_token()

      Repo.insert!(%LiveActivity{
        user_id: ctx.user.id,
        oauth_client_id: Ecto.UUID.generate(),
        token: token,
        token_hash: :crypto.hash(:sha256, token),
        environment: "production",
        expires_at: DateTime.add(ctx.now, 100),
        reconciled_at: old
      })
    end

    assert {:ok, 100} = OrbitLiveActivity.reconcile()
    assert Repo.aggregate(from(r in LiveActivity, where: r.reconciled_at == ^old), :count) == 1
    assert {:ok, 100} = OrbitLiveActivity.reconcile()
    assert Repo.aggregate(from(r in LiveActivity, where: r.reconciled_at == ^old), :count) == 0

    recent_id = Ecto.UUID.generate()
    old_id = Ecto.UUID.generate()
    assert :ok = OrbitLiveActivity.unregister(ctx.user, ctx.client_id, recent_id)
    assert :ok = OrbitLiveActivity.unregister(ctx.user, ctx.client_id, old_id)

    Repo.update_all(from(r in LiveActivity, where: r.id == ^old_id),
      set: [retired_at: DateTime.add(ctx.now, -181, :day)]
    )

    assert :ok = OrbitLiveActivity.prune()
    refute Repo.get(LiveActivity, old_id)
    assert Repo.get!(LiveActivity, recent_id).retired_at
  end

  test "failed and succeeded tools count as finished, while running and cancelled calls never inflate progress", ctx do
    {thread, run} = run(ctx.user, "running", String.duplicate("😀", 81))
    {second, _} = run(ctx.user, "running", String.duplicate("🚀", 81))
    {third, _} = run(ctx.user, "running", String.duplicate("🌍", 81))

    Repo.transaction(fn ->
      Enum.each(~w(succeeded failed cancelled running), fn status ->
        Orbit.append!(thread, %{kind: "tool", run_id: run.id, tool_status: status, tool_name: "private"})
      end)
    end)

    assert :ok = deliver(ctx.id)

    assert_received {:apns, _, _, _, %{"aps" => %{"content-state" => content}} = payload}
    assert content["active_count"] == 3

    assert Map.new(content["conversations"], &{&1["id"], &1["title"]}) ==
             %{
               thread.id => String.duplicate("😀", 80),
               second.id => String.duplicate("🚀", 80),
               third.id => String.duplicate("🌍", 80)
             }

    assert Enum.find(content["conversations"], &(&1["id"] == thread.id)) == %{
             "id" => thread.id,
             "title" => String.duplicate("😀", 80),
             "completed_steps" => 2,
             "status" => "using_tools",
             "started_at" => DateTime.to_unix(run.started_at)
           }

    assert byte_size(JSON.encode!(payload)) < 4096
    refute JSON.encode!(payload) =~ "private"
  end

  defp run(user, status \\ "running", title \\ "New conversation") do
    {:ok, thread, :created} = Orbit.create_private(user, %{"request_id" => Ecto.UUID.generate()})
    thread = thread |> Ecto.Changeset.change(title: title) |> Repo.update!()

    run =
      Repo.insert!(%Run{
        thread_id: thread.id,
        acting_user_id: user.id,
        initiator_id: user.id,
        status: status,
        trigger_seq: 0,
        started_at: if(status == "running", do: DateTime.utc_now())
      })

    {thread, run}
  end

  defp deliver(id), do: perform_job(UpdateLiveActivity, %{"registration_id" => id})
  defp at(now, seconds), do: stub(DateTime, :utc_now, fn -> DateTime.add(now, seconds) end)

  defp respond(status, body \\ %{}, headers \\ []) do
    test_pid = self()

    stub(Config, :req_options, fn ->
      [
        plug: fn conn ->
          send(test_pid, {:apns, status})
          conn = Enum.reduce(headers, conn, fn {k, v}, conn -> Plug.Conn.put_resp_header(conn, k, v) end)
          Req.Test.json(Plug.Conn.put_status(conn, status), body)
        end
      ]
    end)
  end
end
