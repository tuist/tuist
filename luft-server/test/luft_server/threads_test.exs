defmodule LuftServer.ThreadsTest do
  use ExUnit.Case, async: true

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias LuftServer.Agents.Lease
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServer.Threads
  alias LuftServer.Threads.Message
  alias LuftServer.Threads.Run
  alias LuftServer.Threads.Thread
  alias LuftServer.Threads.ToolCall
  alias LuftServer.Tuist.Scope

  defmodule Admission do
    @moduledoc false
    def admit(scope, owner, author, selection) do
      send(self(), {:admitted, scope.user_id, owner.id, author.id, selection})
      :ok
    end
  end

  defmodule NormalizingAdmission do
    @moduledoc false
    def admit(_, _, _, selection),
      do:
        {:ok,
         Map.merge(selection, %{
           repository: "Org/Repo",
           base_branch: "main",
           account_handle: "untrusted"
         })}
  end

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    Req.Test.stub(LuftServer.Tuist, fn conn ->
      assert conn.request_path == "/api/accounts/team/luft-context"
      ["Bearer upstream-" <> subject] = Plug.Conn.get_req_header(conn, "authorization")

      Req.Test.json(conn, %{
        user_id: String.to_integer(subject),
        account_id: 100,
        organization_id: 10,
        can_create_threads: true,
        people: people()
      })
    end)

    %{scope: scope(), session: session(1)}
  end

  test "creation is fail closed without an execution adapter and binds explicit delegation",
       ctx do
    attrs = attrs(%{"repository" => "owner/repo", "base_branch" => "main"})

    assert {:error, :execution_unavailable} =
             Threads.create(ctx.scope, ctx.session, "team", attrs)

    assert Repo.aggregate(Thread, :count) == 0
    assert {:ok, thread} = create(ctx, attrs)
    assert thread.owner_session_id == ctx.session.id
    assert thread.account_handle == "team"
    assert thread.repository == "owner/repo"
    assert thread.base_branch == "main"
    assert [%{author_session_id: id, author_id: 1}] = thread.messages
    assert id == ctx.session.id
    assert Repo.aggregate(Run, :count) == 1
    assert_receive {:admitted, 1, ^id, ^id, %{repository: "owner/repo"}}

    assert %{rows: [[true]]} =
             Repo.query!("SELECT wanted FROM agent_sessions WHERE id=$1", [thread.id])
  end

  test "request replay returns the same history without re-delegating or redispatching", ctx do
    attrs = attrs()
    {:ok, thread} = create(ctx, attrs)
    other = session(1)
    assert {:ok, replay} = Threads.create(ctx.scope, other, "team", attrs)
    assert replay.id == thread.id
    assert replay.owner_session_id == ctx.session.id
    assert {:error, :request_conflict} = create(ctx, %{attrs | "content" => "different"})
    assert Repo.aggregate(Thread, :count) == 1
    assert Repo.aggregate(Run, :count) == 1
    assert {:error, :unauthorized} = Threads.create(ctx.scope, session(2), "team", attrs)
  end

  test "admission persists canonical selections but cannot replace the trusted account handle",
       ctx do
    attrs = attrs(%{"repository" => "org/repo", "account_handle" => "wrong"})

    assert {:ok, thread} =
             Threads.create(ctx.scope, ctx.session, "team", attrs,
               execution: NormalizingAdmission
             )

    assert thread.repository == "Org/Repo"
    assert thread.base_branch == "main"
    assert thread.account_handle == "team"
    assert {:ok, replay} = Threads.create(ctx.scope, ctx.session, "team", attrs)
    assert replay.id == thread.id
  end

  test "private owners, mentioned members and ordinary members have distinct permissions", ctx do
    {:ok, thread} = create(ctx, attrs(%{"content" => "Hello @TWO @disabled user@example.com"}))
    member = scope(2, false)
    outsider = scope(3, true)
    assert thread.participant_ids == [2]
    assert {:ok, _} = Threads.get(member, thread.id)
    assert {:error, :not_found} = Threads.get(outsider, thread.id)
    assert {:error, :not_found} = Threads.get(%{ctx.scope | account_id: 101}, thread.id)
    assert {:error, :forbidden} = Threads.get(%{ctx.scope | can_create_threads: false}, thread.id)
    assert {:error, :forbidden} = Threads.archive(member, thread.id, "archived")
    assert {:error, :forbidden} = Threads.create(member, session(2), "team", attrs())
    assert {:ok, %{threads: [shared]}} = Threads.list(member)
    assert shared.id == thread.id
    assert {:ok, %{threads: []}} = Threads.list(outsider)
    assert Threads.mentions("a@two.com (@Two), @two @other-name") == ["two", "other-name"]
  end

  test "messages enforce busy state, replay content and author, and preserve originating session",
       ctx do
    {:ok, thread} = create(ctx, attrs(%{"content" => "Hello @two"}))
    attrs = %{"request_id" => Ecto.UUID.generate(), "content" => "Follow up"}

    assert {:error, :busy} =
             Threads.message(ctx.scope, ctx.session, thread.id, attrs, execution: Admission)

    complete_runs(thread)
    author = session(2)

    assert {:ok, sent} =
             Threads.message(scope(2, false), author, thread.id, attrs, execution: Admission)

    assert List.last(sent.messages).author_session_id == author.id
    assert {:ok, _} = Threads.message(scope(2, false), author, thread.id, attrs)
    assert {:error, :request_conflict} = Threads.message(ctx.scope, ctx.session, thread.id, attrs)

    assert {:error, :request_conflict} =
             Threads.message(scope(2, false), author, thread.id, %{attrs | "content" => "changed"})

    assert Repo.aggregate(Run, :count) == 2
    assert Repo.aggregate(Message, :count) == 2
    Repo.delete!(ctx.session)

    assert {:error, :delegation_required} =
             Threads.message(
               scope(2, false),
               author,
               thread.id,
               Map.put(attrs, "request_id", Ecto.UUID.generate()),
               execution: Admission
             )
  end

  test "history and inbox cursor pagination are bounded and stable", ctx do
    for n <- 1..27, do: create(ctx, attrs(%{"content" => "Thread #{n}"}))
    {:ok, first} = Threads.list(ctx.scope)
    assert length(first.threads) == 25
    {:ok, second} = Threads.list(ctx.scope, first.next_cursor)
    assert length(second.threads) == 2
    assert second.next_cursor == nil

    assert MapSet.disjoint?(
             MapSet.new(first.threads, & &1.id),
             MapSet.new(second.threads, & &1.id)
           )

    assert {:error, :invalid_arguments} = Threads.list(ctx.scope, "bad cursor")
    thread = hd(first.threads)

    for position <- 3..60 do
      Repo.insert!(%Message{
        thread_id: thread.id,
        position: position,
        kind: "notice",
        body: "#{position}"
      })
    end

    {:ok, page} = Threads.get(ctx.scope, thread.id)
    assert length(page.messages) == 50
    assert page.has_more
    {:ok, older} = Threads.get(ctx.scope, thread.id, before: to_string(page.next_before))
    assert length(older.messages) == 9
    refute older.has_more
    assert {:error, :invalid_arguments} = Threads.get(ctx.scope, thread.id, before: "0")
  end

  test "snooze validates bounds, archive cancels runs, and restores are idempotent", ctx do
    {:ok, thread} = create(ctx)
    assert {:ok, snoozed} = Threads.snooze(ctx.scope, thread.id, %{"until_needed" => true})
    assert snoozed.snoozed_until_needed
    until = :second |> DateTime.utc_now() |> DateTime.shift(hour: 1) |> DateTime.to_iso8601()
    assert {:ok, snoozed} = Threads.snooze(ctx.scope, thread.id, %{"until" => until})
    assert DateTime.to_iso8601(snoozed.snoozed_until) == until

    assert {:error, :invalid_arguments} =
             Threads.snooze(ctx.scope, thread.id, %{"until" => "2020-01-01T00:00:00Z"})

    {:ok, archived} = Threads.archive(ctx.scope, thread.id, "archived")
    assert archived.status == :archived
    assert Repo.one!(from r in Run, where: r.thread_id == ^thread.id).status == "cancelled"
    assert {:ok, again} = Threads.archive(ctx.scope, thread.id, "archived")
    assert again.revision == archived.revision

    assert {:error, :not_working} =
             Threads.snooze(ctx.scope, thread.id, %{"until_needed" => true})

    assert {:ok, %{status: :active}} = Threads.archive(ctx.scope, thread.id, "active")
  end

  test "snapshots expose only revision/status/tool name and notify only authorized inboxes",
       ctx do
    account_id = System.unique_integer([:positive])
    ctx = %{ctx | scope: %{ctx.scope | account_id: account_id}}
    Phoenix.PubSub.subscribe(LuftServer.PubSub, Threads.topic(1, account_id))
    {:ok, thread} = create(ctx, attrs(%{"content" => "@two"}))
    assert_receive :threads_changed
    {:ok, inbox} = Threads.snapshot(ctx.scope, :inbox)
    assert inbox.revision > 0
    assert inbox |> Map.keys() |> Enum.sort() == [:activity, :agent_status, :revision]
    assert {:ok, %{revision: 0}} = Threads.snapshot(scope(3, false), :inbox)
    assert {:error, :not_found} = Threads.snapshot(scope(3, false), thread.id)

    assert {:ok, %{activity: nil}} =
             Threads.snapshot(%{scope(2, false) | account_id: account_id}, thread.id)

    attrs = attrs(%{"request_id" => thread.request_id, "content" => "conflict"})
    assert {:error, :request_conflict} = create(ctx, attrs)
    refute_receive :threads_changed
  end

  test "lease takeover fences every former attempt and refuses absent delegation", ctx do
    {run, thread, epoch} = claimed(ctx)
    assert Threads.owns_run?(run.id, epoch)
    assert {:error, :stale_run} = Threads.claim(run.id, epoch)
    assert Threads.next_run(thread.id) == run.id
    Lease.release(thread.id, epoch)
    [%{epoch: next}] = Lease.claim("replacement", 1)
    assert {:ok, {fresh, _}} = Threads.claim(run.id, next)
    refute Threads.owns_run?(run.id, epoch)
    assert {:error, :stale_run} = Threads.finish(run, {:ok, "late"})
    assert :ok = Threads.keep_alive(fresh)
    Repo.delete!(ctx.session)
    refute Threads.owns_run?(fresh.id, next)
  end

  test "tool reservations replay confirmed results and retain uncertainty across runs", ctx do
    {run, thread, _} = claimed(ctx)
    assert :ok = Threads.begin_tool_call(run, "call", "Bash", %{}, ["Bash"])
    assert :ok = Threads.begin_tool_call(run, "call", "Bash", %{}, ["Bash"])
    assert Repo.aggregate(ToolCall, :count) == 1
    assert :ok = Threads.complete_tool_call(run, "call", "Bash", %{}, {:ok, "result"})
    assert {:block, text} = Threads.begin_tool_call(run, "call", "Bash", %{}, ["Bash"])
    assert text =~ "result"

    assert {:ok, "external"} =
             Threads.call_external_tool(run, "external", "mcp", %{}, fn -> {:ok, "external"} end)

    assert {:ok, "external"} =
             Threads.call_external_tool(run, "external", "mcp", %{}, fn ->
               flunk("replayed effect")
             end)

    assert {:error, :tool_outcome_unknown} =
             Threads.call_external_tool(run, "unknown", "mcp", %{}, fn -> {:error, :timeout} end)

    assert {:ok, finished} = Threads.finish(run, {:ok, "not a success"})
    assert finished.agent_status == "outcome_unknown"
    assert Repo.get!(Run, run.id).status == "outcome_unknown"
    assert {:ok, _} = Threads.get(ctx.scope, thread.id)
  end

  test "an MCP discovery failure points to MCP servers, not the AI account", ctx do
    {run, thread, _} = claimed(ctx)

    assert {:ok, finished} = Threads.finish(run, {:error, :mcp_discovery_failed})
    assert finished.agent_status == "failed"
    {:ok, %{messages: messages}} = Threads.get(ctx.scope, thread.id)
    notice = List.last(messages)
    assert notice.kind == "notice"
    assert notice.body =~ "MCP servers"
    refute notice.body =~ "AI account"
  end

  test "ask-user answers requeue the same run exactly once and bind the answer author", ctx do
    {run, thread, _} = claimed(ctx)

    question = %{
      "question" => "Continue?",
      "options" => [%{"id" => "yes", "label" => "Yes"}],
      "allow_other" => false
    }

    request_id = Ecto.UUID.generate()
    assert {:ok, pending} = Threads.ask_user(run, request_id, question, "card")
    assert Threads.user_question(run, request_id).id == pending.id
    assert Threads.next_run(thread.id) == nil

    attrs = %{
      "request_id" => Ecto.UUID.generate(),
      "content" => "Yes",
      "question_id" => pending.id,
      "option_id" => "yes"
    }

    assert {:ok, answered} =
             Threads.message(ctx.scope, ctx.session, thread.id, attrs, execution: Admission)

    assert {:ok, _} = Threads.message(ctx.scope, ctx.session, thread.id, attrs)
    assert Repo.aggregate(Run, :count) == 1
    assert Repo.get!(Run, run.id).status == "queued"

    assert Repo.get!(Message, pending.id).decision["answer"] == %{
             "option_id" => "yes",
             "text" => "Yes"
           }

    assert List.last(answered.messages).author_session_id == ctx.session.id

    assert {:error, :request_conflict} =
             Threads.message(ctx.scope, ctx.session, thread.id, Map.put(attrs, "cancel", true))

    assert {:error, :question_answered} =
             Threads.message(
               ctx.scope,
               ctx.session,
               thread.id,
               Map.put(attrs, "request_id", Ecto.UUID.generate()),
               execution: Admission
             )
  end

  test "progress replaces in place; finish decodes suggestions and clears snooze until needed",
       ctx do
    {run, thread, _} = claimed(ctx)

    assert {:ok, _} =
             Threads.update_progress(run, [%{"title" => "Test", "status" => "in_progress"}])

    assert {:ok, _} =
             Threads.update_progress(run, [%{"title" => "Test", "status" => "completed"}])

    assert Repo.aggregate(from(m in Message, where: m.kind == "progress"), :count) == 1
    assert {:error, :invalid_arguments} = Threads.update_progress(run, [])
    assert {:ok, _} = Threads.snooze(ctx.scope, thread.id, %{"until_needed" => true})

    assert {:ok, done} =
             Threads.finish(
               run,
               {:ok, ~s({"reply":"Done","suggestions":[{"text":"Test again","icon":"test"}]})}
             )

    refute done.snoozed_until_needed
    {:ok, loaded} = Threads.get(ctx.scope, thread.id)
    value = Threads.serialize(loaded)
    assert List.last(value.messages).suggestion_icons == %{"Test again" => "test"}
    refute Map.has_key?(value, :owner_session_id)
    refute Map.has_key?(hd(value.messages), :author_session_id)
  end

  test "runtime never substitutes another session for the originating human author", ctx do
    {:ok, thread} = create(ctx, attrs(%{"content" => "@two"}))
    complete_runs(thread)
    author = session(2)

    assert {:ok, _} =
             Threads.message(
               scope(2, false),
               author,
               thread.id,
               %{"request_id" => Ecto.UUID.generate(), "content" => "Use my tools"},
               execution: Admission
             )

    [%{epoch: epoch}] = Lease.claim("host", 1)
    run_id = Threads.next_run(thread.id)
    assert {:ok, {run, _}} = Threads.claim(run_id, epoch)
    assert Threads.owns_run?(run.id, epoch)
    _alternate = session(2)
    Repo.delete!(author)
    refute Threads.owns_run?(run.id, epoch)

    assert {:error, :stale_run} =
             Threads.update_progress(run, [%{"title" => "No authority", "status" => "pending"}])
  end

  test "transient upstream outages do not terminalize queued work", ctx do
    {:ok, thread} = create(ctx)
    [%{epoch: epoch}] = Lease.claim("host", 1)
    run_id = Threads.next_run(thread.id)
    Req.Test.stub(LuftServer.Tuist, fn conn -> Plug.Conn.send_resp(conn, 503, "unavailable") end)
    assert {:error, :tuist_unavailable} = Threads.claim(run_id, epoch)
    assert Repo.get!(Run, run_id).status == "queued"
    assert Repo.get!(Thread, thread.id).agent_status == "queued"
  end

  test "database-clock lifetime budget accounts for waited time and persists expiry", ctx do
    {:ok, thread} = create(ctx)
    [%{epoch: epoch}] = Lease.claim("host", 1)
    run_id = Threads.next_run(thread.id)

    Repo.query!(
      "UPDATE thread_runs SET inserted_at=CURRENT_TIMESTAMP - interval '4 hours' WHERE id=$1",
      [Ecto.UUID.dump!(run_id)]
    )

    assert {:error, :expired} = Threads.claim(run_id, epoch)
    assert Repo.get!(Run, run_id).status == "failed"
    assert Repo.get!(Thread, thread.id).agent_status == "failed"
  end

  test "tool snapshots are private and build progress is bounded and throttled", ctx do
    {run, thread, _} = claimed(ctx)
    assert :ok = Threads.begin_tool_call(run, "build", "Bash", %{"secret" => "hidden"}, ["Bash"])
    assert {:ok, %{activity: "Bash"} = snapshot} = Threads.snapshot(ctx.scope, thread.id)
    assert Enum.sort(Map.keys(snapshot)) == [:activity, :agent_status, :revision]

    progress = %{
      "v" => 1,
      "command" => "test",
      "state" => "running",
      "target" => "\u202EApp",
      "planned" => 10,
      "done" => 1
    }

    assert :ok = Threads.record_build_progress(run, "build", progress)
    call = Repo.get_by!(ToolCall, run_id: run.id, invocation_id: "build")
    message = Repo.get!(Message, call.message_id)
    assert message.progress["target"] == "App"
    revision = Repo.get!(Thread, thread.id).revision
    assert :ok = Threads.record_build_progress(run, "build", Map.put(progress, "done", 2))
    assert Repo.get!(Thread, thread.id).revision == revision

    assert :ok =
             Threads.complete_tool_call(
               run,
               "build",
               "Bash",
               %{"secret" => "hidden"},
               {:ok, "done"}
             )

    assert {:ok, %{activity: nil}} = Threads.snapshot(ctx.scope, thread.id)
  end

  test "unsupported selections and malformed attachments cannot enqueue work", ctx do
    for extra <- [
          %{"runner_id" => "bad"},
          %{"runner_id" => Ecto.UUID.generate(), "repository" => "repo"},
          %{
            "attachments" => [
              %{"name" => "../secret", "mime_type" => "text/plain", "data_base64" => "YQ=="}
            ]
          },
          %{"content" => ""},
          %{"request_id" => "invalid"}
        ] do
      assert {:error, :invalid_arguments} = create(ctx, attrs(extra))
    end

    assert Repo.aggregate(Run, :count) == 0
  end

  test "context rejects externally nested writes rather than publishing before commit", ctx do
    account_id = System.unique_integer([:positive])
    ctx = %{ctx | scope: %{ctx.scope | account_id: account_id}}
    Phoenix.PubSub.subscribe(LuftServer.PubSub, Threads.topic(1, account_id))

    assert_raise ArgumentError, ~r/outer transaction/, fn ->
      Repo.transaction(fn -> create(ctx) end)
    end

    assert Repo.aggregate(Thread, :count) == 0
    refute_receive :threads_changed
  end

  defp claimed(ctx) do
    {:ok, thread} = create(ctx)
    [%{epoch: epoch}] = Lease.claim("test-host", 1)
    run = Repo.one!(from r in Run, where: r.thread_id == ^thread.id)
    assert {:ok, {run, thread}} = Threads.claim(run.id, epoch)
    {run, thread, epoch}
  end

  defp create(ctx, attrs \\ attrs()),
    do: Threads.create(ctx.scope, ctx.session, "team", attrs, execution: Admission)

  defp complete_runs(thread),
    do:
      Repo.update_all(from(r in Run, where: r.thread_id == ^thread.id),
        set: [status: "succeeded"]
      )

  defp attrs(extra \\ %{}),
    do:
      Map.merge(
        %{
          "request_id" => Ecto.UUID.generate(),
          "content" => "Hello",
          "provider" => "chatgpt",
          "model" => "test-model"
        },
        extra
      )

  defp scope(id \\ 1, create \\ true),
    do: %Scope{
      user_id: id,
      account_id: 100,
      organization_id: 10,
      people: Enum.map(people(), &%{id: &1.id, handle: &1.handle, active: &1.active}),
      can_create_threads: create
    }

  defp people,
    do: [
      %{id: 1, handle: "one", active: true},
      %{id: 2, handle: "two", active: true},
      %{id: 3, handle: "three", active: true},
      %{id: 4, handle: "disabled", active: false}
    ]

  defp session(id) do
    {:ok, _, session} =
      Sessions.create(%{
        claims: %{"sub" => to_string(id)},
        tokens: %{
          "access_token" => "upstream-#{id}",
          "refresh_token" => "refresh",
          "expires_in" => 3600
        }
      })

    session
  end
end
