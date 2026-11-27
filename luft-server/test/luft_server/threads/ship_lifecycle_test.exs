defmodule LuftServer.Threads.ShipLifecycleTest do
  use LuftServerWeb.ConnCase, async: true

  import Ecto.Query

  alias Ecto.Changeset
  alias LuftServer.Agents.Lease
  alias LuftServer.Config
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServer.Threads
  alias LuftServer.Threads.Approval
  alias LuftServer.Threads.Message
  alias LuftServer.Threads.Participant
  alias LuftServer.Threads.Run
  alias LuftServer.Threads.ShipWorker
  alias LuftServer.Threads.Thread
  alias LuftServer.Tuist.Scope
  alias LuftServerWeb.Auth

  @base String.duplicate("a", 40)
  @head String.duplicate("b", 40)

  setup do
    {token, session} = session()

    thread =
      Repo.insert!(%Thread{
        account_id: 100,
        account_handle: "team",
        owner_id: 1,
        owner_session_id: session.id,
        request_id: Ecto.UUID.generate(),
        request_hash: <<1>>,
        title: "Ship",
        goal: "Change",
        provider: "chatgpt",
        model: "model",
        repository: "Org/Repo",
        base_branch: "main",
        branch: "reviewed",
        base_sha: @base,
        sandbox_id: Ecto.UUID.generate(),
        workspace_ready: true,
        agent_status: "idle"
      })

    scope = %Scope{
      user_id: 1,
      account_id: 100,
      organization_id: nil,
      can_create_threads: true,
      people: []
    }

    LuftServer.FakeOpenAI.connect(1)
    stub(thread)
    %{thread: thread, token: token, session: session, scope: scope}
  end

  test "real routes persist the review and exact consent, and an Oban job publishes only once",
       ctx do
    preview = preview(ctx)
    approval = Repo.get_by!(Approval, request_id: preview["request_id"])
    assert approval.status == :pending
    assert approval.diff == "reviewed diff"
    assert approval.approved_at == nil
    assert preview["jam_id"] == ctx.thread.id
    assert %{"status" => "shipping"} = ctx |> approve(preview) |> json_response(200)
    assert %{"status" => "shipping"} = ctx |> approve(preview) |> json_response(200)
    run = Repo.get_by!(Run, approval_id: approval.id)
    assert Repo.aggregate(Run, :count) == 1
    author = Repo.get!(Message, run.message_id)
    assert author.author_session_id == ctx.session.id

    assert Repo.aggregate(
             from(j in Oban.Job, where: j.worker == "LuftServer.Threads.ShipWorker"),
             :count
           ) == 1

    assert :ok = ShipWorker.perform(%Oban.Job{args: %{"run_id" => run.id}})
    assert_received {:published, request_id}
    assert request_id == approval.request_id
    assert Repo.get!(Run, run.id).status == "succeeded"
    assert Repo.get!(Approval, approval.id).status == :succeeded
    assert Repo.get!(Thread, ctx.thread.id).base_sha == @head
    assert :ok = ShipWorker.perform(%Oban.Job{args: %{"run_id" => run.id}})
    ctx |> approve(preview) |> json_response(200)
    refute_received {:published, _}
  end

  test "uncertain publication blocks new work, retains executing approval and only reconciles",
       ctx do
    preview = preview(ctx)
    ctx |> approve(preview) |> json_response(200)
    run = Repo.one!(Run)
    stub(ctx.thread, :uncertain)
    assert :ok = ShipWorker.perform(%Oban.Job{args: %{"run_id" => run.id}})
    assert_received {:published, _}
    assert Repo.get!(Run, run.id).status == "outcome_unknown"
    assert Repo.get!(Approval, run.approval_id).status == :executing
    assert Repo.get!(Thread, ctx.thread.id).base_sha == @base

    assert %{"code" => "shipping_uncertain"} =
             ctx.token
             |> request(ctx.thread, "/messages", %{
               request_id: Ecto.UUID.generate(),
               content: "Continue"
             })
             |> json_response(409)

    ctx |> approve(preview) |> json_response(200)
    assert :ok = ShipWorker.perform(%Oban.Job{args: %{"run_id" => run.id}})
    refute_received {:published, _}

    assert %{"status" => "idle"} =
             ctx.token
             |> request(ctx.thread, "/ship-reconcile", %{
               request_id: preview["request_id"]
             })
             |> json_response(200)

    assert_received {:reconciled, _}
    refute_received {:published, _}
    assert Repo.get!(Thread, ctx.thread.id).base_sha == @head
  end

  test "crash after dispatch is recovered to unknown, never a new execution", ctx do
    preview = preview(ctx)
    ctx |> approve(preview) |> json_response(200)
    run = Repo.one!(Run)
    [%{epoch: epoch}] = Lease.claim("crashed", 1)
    assert {:ok, {claimed, _, approval}} = Threads.claim_ship(run.id, epoch)
    assert approval.status == :executing
    assert Threads.owns_run?(claimed.id, epoch)
    # Simulate a vanished worker, including the authorization-before-write gap.
    Repo.query!(
      "UPDATE agent_sessions SET lease_expires_at=CURRENT_TIMESTAMP - interval '1 second' WHERE id=$1",
      [ctx.thread.id]
    )

    assert :ok = Threads.recover()
    assert Repo.get!(Run, run.id).status == "outcome_unknown"
    assert :ok = ShipWorker.perform(%Oban.Job{args: %{"run_id" => run.id}})
    refute_received {:published, _}

    assert {:error, :stale_run} =
             Threads.finish_ship(
               claimed,
               {:ok,
                %{request_id: approval.request_id, head_sha: @head, target_branch: "reviewed"}}
             )
  end

  test "queued worker retries cannot steal a live inference lease", ctx do
    preview = preview(ctx)
    ctx |> approve(preview) |> json_response(200)
    run = Repo.one!(Run)
    [%{epoch: epoch}] = Lease.claim("inference-host", 1)
    assert {:snooze, 5} = ShipWorker.perform(%Oban.Job{args: %{"run_id" => run.id}})
    assert Repo.get!(Run, run.id).status == "queued"
    Lease.release(ctx.thread.id, epoch)
    assert :ok = ShipWorker.perform(%Oban.Job{args: %{"run_id" => run.id}})
    assert_received {:published, _}
  end

  test "changed review fields, stale workspace, tenants and participants cannot approve", ctx do
    preview = preview(ctx)

    assert %{"code" => "shipping_approval_invalid"} =
             ctx |> approve(Map.put(preview, "head_sha", @base)) |> json_response(409)

    Repo.update!(Changeset.change(ctx.thread, base_sha: @head))
    assert %{"code" => "shipping_review_stale"} = ctx |> approve(preview) |> json_response(409)
    assert Repo.aggregate(Run, :count) == 0

    assert {:error, :not_found} =
             Threads.ship(%{ctx.scope | account_id: 101}, ctx.session, ctx.thread.id, preview)

    assert {:error, :not_found} =
             Threads.ship(%{ctx.scope | user_id: 2}, ctx.session, ctx.thread.id, preview)
  end

  test "revoking the actual consent session cannot be repaired by another owner session", ctx do
    preview = preview(ctx)
    {token, author} = session()
    token |> request(ctx.thread, "/ship", preview) |> json_response(200)
    run = Repo.one!(Run)
    _alternative = session()
    Repo.delete!(author)
    assert :ok = ShipWorker.perform(%Oban.Job{args: %{"run_id" => run.id}})
    assert Repo.get!(Run, run.id).status == "failed"
    refute_received {:published, _}
  end

  test "review-stale failure before publication allows a fresh review instead of unresolved consent",
       ctx do
    preview = preview(ctx)
    ctx |> approve(preview) |> json_response(200)
    stub(ctx.thread, :changed_workspace)
    run = Repo.one!(Run)
    assert :ok = ShipWorker.perform(%Oban.Job{args: %{"run_id" => run.id}})
    assert Repo.get!(Run, run.id).status == "failed"
    assert Repo.get!(Approval, run.approval_id).status == :failed
    refute_received {:published, _}
  end

  test "production Execution and real create route resolve repository/default branch", ctx do
    attrs = %{
      request_id: Ecto.UUID.generate(),
      content: "Change code",
      provider: "chatgpt",
      model: "model",
      repository: "org/repo"
    }

    conn =
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("origin", Config.public_url())
      |> put_req_cookie(Auth.cookie_name(), ctx.token)
      |> post("/api/accounts/team/threads", Jason.encode!(attrs))

    assert %{"id" => id, "repository" => "Org/Repo"} = json_response(conn, 200)
    assert Repo.get!(Thread, id).base_branch == "main"
  end

  test "participants may see history but cannot approve or obtain a Ship review", ctx do
    Repo.insert!(%Participant{thread_id: ctx.thread.id, user_id: 2, added_by_id: 1})
    member = %{ctx.scope | user_id: 2, organization_id: 10, can_create_threads: false}
    assert {:ok, _} = Threads.get(member, ctx.thread.id)
    assert {:error, :forbidden} = Threads.ship_preview(member, ctx.thread.id)
    assert {:error, :forbidden} = Threads.ship(member, ctx.session, ctx.thread.id, %{})
  end

  test "archive during publication retains unresolved consent and allows observation-only reconcile",
       ctx do
    preview = preview(ctx)
    ctx |> approve(preview) |> json_response(200)
    run = Repo.one!(Run)
    [%{epoch: epoch}] = Lease.claim("ship", 1)
    assert {:ok, {claimed, _, _}} = Threads.claim_ship(run.id, epoch)
    assert {:error, :stale_run} = Threads.claim_ship(run.id, epoch)
    assert {:ok, _} = Threads.archive(ctx.scope, ctx.thread.id, "archived")
    assert Repo.get!(Run, run.id).status == "outcome_unknown"
    assert Repo.get!(Approval, run.approval_id).status == :executing
    assert {:error, :stale_run} = Threads.execute_ship(claimed)

    assert %{"archive_status" => "archived"} =
             ctx.token
             |> request(ctx.thread, "/ship-reconcile", %{
               request_id: preview["request_id"]
             })
             |> json_response(200)

    assert_received {:reconciled, _}
    refute_received {:published, _}
  end

  test "recovery repairs a lost queued job, but never spends a live dispatch lease", ctx do
    preview = preview(ctx)
    ctx |> approve(preview) |> json_response(200)
    run = Repo.one!(Run)
    Repo.delete_all(from j in Oban.Job, where: j.worker == "LuftServer.Threads.ShipWorker")
    assert :ok = Threads.recover()

    assert Repo.aggregate(
             from(j in Oban.Job, where: j.worker == "LuftServer.Threads.ShipWorker"),
             :count
           ) == 1

    [%{epoch: epoch}] = Lease.claim("live", 1)
    assert {:ok, _} = Threads.claim_ship(run.id, epoch)
    assert :ok = Threads.recover()
    assert Repo.get!(Run, run.id).status == "running"
    refute_received {:published, _}
  end

  test "owner reauthorization is explicit and never authorizes historical queued commands", ctx do
    thread =
      Repo.update!(Changeset.change(ctx.thread, owner_session_id: nil, account_handle: nil))

    {_, consent} = session()
    assert {:ok, rebound} = Threads.reauthorize(ctx.scope, consent, thread.id, "team")
    assert rebound.owner_session_id == consent.id
    assert rebound.account_handle == "team"
    assert Repo.aggregate(Run, :count) == 0

    Repo.insert!(%Run{
      thread_id: thread.id,
      kind: "inference",
      heartbeat_at: DateTime.utc_now(:second)
    })

    assert {:error, :busy} = Threads.reauthorize(ctx.scope, ctx.session, thread.id, "team")
    assert Repo.get!(Thread, thread.id).owner_session_id == consent.id
  end

  test "terminal notification jobs roll back with their shipping transaction", ctx do
    preview = preview(ctx)
    ctx |> approve(preview) |> json_response(200)
    run = Repo.one!(Run)
    [%{epoch: epoch}] = Lease.claim("ship", 1)
    {:ok, {claimed, _, approval}} = Threads.claim_ship(run.id, epoch)
    result = {:ok, %{request_id: approval.request_id, head_sha: @head, target_branch: "reviewed"}}

    assert {:error, :proof_rollback} =
             Threads.with_attempt(claimed, fn _, _ ->
               assert {:ok, _} = Threads.finish_ship(claimed, result)

               assert Repo.exists?(
                        from j in Oban.Job,
                          where: j.worker == "LuftServer.Notifications.ThreadFinishedWorker"
                      )

               Repo.rollback(:proof_rollback)
             end)

    refute Repo.exists?(
             from j in Oban.Job,
               where: j.worker == "LuftServer.Notifications.ThreadFinishedWorker"
           )

    assert Repo.get!(Run, run.id).status == "running"
    assert Repo.get!(Thread, ctx.thread.id).base_sha == @base
    assert {:ok, _} = Threads.finish_ship(claimed, result)

    assert Repo.exists?(
             from j in Oban.Job,
               where:
                 j.worker == "LuftServer.Notifications.ThreadFinishedWorker" and
                   fragment("?->>'status' = 'idle'", j.args)
           )
  end

  test "ending only the matching timed snooze enqueues its reminder transactionally", ctx do
    until = :second |> DateTime.utc_now() |> DateTime.shift(hour: 1)
    Repo.update!(Changeset.change(ctx.thread, snoozed_until: until))
    assert {:ok, :ok} = Threads.wake_snoozed(ctx.thread.id, DateTime.shift(until, second: 1))

    refute Repo.exists?(
             from j in Oban.Job,
               where: j.worker == "LuftServer.Notifications.ThreadFinishedWorker"
           )

    assert {:ok, :woken} = Threads.wake_snoozed(ctx.thread.id, until)

    assert Repo.exists?(
             from j in Oban.Job,
               where:
                 j.worker == "LuftServer.Notifications.ThreadFinishedWorker" and
                   fragment("?->>'status' = 'snooze_ended'", j.args)
           )
  end

  defp preview(ctx),
    do: ctx.token |> request(ctx.thread, "/ship-preview", %{}) |> json_response(200)

  defp approve(ctx, preview), do: request(ctx.token, ctx.thread, "/ship", preview)

  defp request(token, thread, suffix, body) do
    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("origin", Config.public_url())
    |> put_req_cookie(Auth.cookie_name(), token)
    |> post("/api/accounts/team/threads/#{thread.id}#{suffix}", Jason.encode!(body))
  end

  defp session do
    {:ok, token, session} =
      Sessions.create(%{
        claims: %{"sub" => "1"},
        tokens: %{
          "access_token" => "owner-token",
          "refresh_token" => "refresh",
          "expires_in" => 3600
        }
      })

    {token, session}
  end

  defp stub(thread, mode \\ :success) do
    test = self()
    LuftServer.FakeOpenAI.stub(models: ["model"])

    Req.Test.stub(LuftServer.Tuist, fn conn ->
      assert get_req_header(conn, "authorization") == ["Bearer owner-token"]

      case conn.request_path do
        "/api/accounts/team/luft-context" ->
          Req.Test.json(conn, %{
            user_id: 1,
            account_id: 100,
            organization_id: nil,
            can_create_threads: true,
            people: []
          })

        "/api/accounts/team/workspace-capabilities" ->
          {:ok, raw, conn} = read_body(conn)
          body = Jason.decode!(raw)
          result = workspace_result(body, thread, mode, test)

          if body["operation"] == "repository_publish" and mode == :uncertain do
            conn |> put_status(409) |> Req.Test.json(%{code: "shipping_uncertain"})
          else
            Req.Test.json(conn, %{result: result})
          end
      end
    end)
  end

  defp workspace_result(body, thread, mode, test) do
    case body["operation"] do
      "repository_authorize" ->
        %{name: "Org/Repo", default_branch: "main", size: 1}

      op when op in ["show", "acquire"] ->
        %{id: thread.sandbox_id, account_id: 100, state: "running"}

      "release" ->
        %{}

      "exec" ->
        head = if mode == :changed_workspace, do: String.duplicate("c", 40), else: @head

        %{
          exit_code: 0,
          stdout: if(Enum.at(body["argv"], 2) =~ "commit-tree", do: head, else: "{}")
        }

      "repository_review" ->
        "reviewed diff"

      "repository_publish" ->
        approval = Repo.get_by!(Approval, request_id: body["request_id"])
        assert approval.status == :executing
        run = Repo.get_by!(Run, approval_id: approval.id)
        assert run.status == "running"
        assert Threads.owns_run?(run.id, run.attempt)
        assert body["diff"] == approval.diff
        send(test, {:published, body["request_id"]})
        %{head_sha: @head}

      "publication_reconcile" ->
        send(test, {:reconciled, body["request_id"]})
        %{request_id: body["request_id"], head_sha: @head, target_branch: "reviewed"}
    end
  end
end
