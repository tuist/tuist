defmodule TuistWeb.BazelRemoteActionLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Bazel
  alias Tuist.RemoteExecution.Actions
  alias Tuist.RemoteExecution.Scheduler
  alias Tuist.Storage
  alias Tuist.Utilities.ByteFormatter
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistWeb.Errors.NotFoundError

  @queued 1_793_157_000_000_000

  setup %{conn: conn} do
    stub(Storage, :get_object_as_string, fn _key, _actor -> nil end)
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, build_system: :bazel)
    invocation_id = Ecto.UUID.generate()
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

    Bazel.create_invocations([
      %{
        project_id: project.id,
        invocation_id: invocation_id,
        account_handle: user.account.name,
        project_handle: project.name,
        command: "build",
        status: "failure",
        exit_code: 1,
        started_at: now,
        finished_at: now,
        duration_ms: 500,
        target_patterns: [],
        cache_endpoint: ""
      }
    ])

    %{
      conn: log_in_user(conn, user),
      project: project,
      invocation_id: invocation_id,
      path: "/#{user.account.name}/#{project.name}/builds/invocations/#{invocation_id}"
    }
  end

  test "shows the details, errors and command on Overview, and the output on Logs", %{
    conn: conn,
    project: project,
    invocation_id: invocation_id,
    path: path
  } do
    id = Ecto.UUID.generate()

    {:ok, 1} =
      Actions.ingest(project, [
        %{
          "operation_id" => id,
          "action_hash" => String.duplicate("e", 64),
          "action_size" => 187,
          "invocation_id" => invocation_id,
          "mnemonic" => "GoCompile",
          "target" => "//svc:server",
          "execution_path" => "lease",
          "worker" => "worker-7",
          "memory_gb" => 8,
          "exit_code" => 2,
          "arguments" => ["go", "tool", "compile", "-o", "bazel-out/svc.a"],
          "environment" => [
            %{"name" => "GOOS", "value" => "linux"},
            %{"name" => "GH_TOKEN", "value" => "ghp_x"},
            %{"name" => "CARGO_PKG_AUTHORS", "value" => ""}
          ],
          "platform" => [%{"name" => "container-image", "value" => "docker://golang:1.25"}],
          "output_paths" => ["bazel-out/svc.a"],
          "stdout" => "compiling svc",
          "stderr" => "# svc\nsvc/main.go:3:2: undefined: Foo\nsvc/main.go:9:5: too many arguments",
          "stderr_size" => 40_000,
          "stderr_truncated" => true,
          "timestamps" => %{
            "queued" => @queued,
            "execution_start" => @queued + 500_000,
            "execution_completed" => @queued + 3_000_000,
            "worker_completed" => @queued + 3_200_000
          }
        }
      ])

    {:ok, view, _html} = live(conn, path <> "/remote-actions/" <> id)

    # Overview: the header carries the status tile, the details its badge.
    assert has_element?(view, "h1", "GoCompile")
    assert has_element?(view, "[data-part=badge-failure]")
    assert has_element?(view, "[data-part=status]", "Failed")
    assert has_element?(view, "[data-field=exit-code]", "2")
    assert has_element?(view, "[data-part=target]", "//svc:server")
    assert has_element?(view, "[data-part=metadata]", String.duplicate("e", 64) <> "/187")
    assert has_element?(view, "[data-phase=execution_ms]", "2.5s")
    assert has_element?(view, "[data-phase=queue_ms]", "Not recorded")
    assert has_element?(view, "[data-part=metadata]", "Leased worker")
    # Compiler errors group by file in the Errors card, as a build's issues do.
    assert has_element?(view, "[data-part=errors-card] .issue-card", "Failed compiling svc/main.go")
    assert has_element?(view, "[data-part=errors-card] [data-part=issue]", "undefined: Foo at svc/main.go:3:2")
    assert has_element?(view, "[data-part=errors-card] [data-part=issue]", "too many arguments at svc/main.go:9:5")
    # The Command card: one copyable command line, environment and platform collapsed.
    assert has_element?(view, "#remote-action-command-line", "go tool compile -o bazel-out/svc.a")

    assert has_element?(
             view,
             "#remote-action-command [data-part=command] #remote-action-command-copy[data-clipboard-value=\"go tool compile -o bazel-out/svc.a\"]"
           )

    assert has_element?(view, "#remote-action-command [data-field=outputs]", "bazel-out/svc.a")
    assert has_element?(view, "#remote-action-command [data-part=metadata]", "/workspace/action")
    assert has_element?(view, "#remote-action-environment [data-part=metadata]", "GOOS")
    # An empty value reads as empty, not as a missing one.
    assert has_element?(view, "#remote-action-environment dd[data-empty]", "Empty")
    refute render(view) =~ "ghp_x"
    assert has_element?(view, "#remote-action-platform [data-part=metadata]", "docker://golang:1.25")
    refute has_element?(view, "#remote-action-command-expand")
    refute has_element?(view, "[data-part=log-viewport]")

    render_patch(view, path <> "/remote-actions/" <> id <> "?tab=logs")
    # One log: stdout first, then stderr, numbered continuously.
    assert has_element?(view, "#remote-action-logs [data-part=log-line]:nth-child(1)", "compiling svc")
    assert has_element?(view, "#remote-action-logs [data-part=log-line]:nth-child(2)", "# svc")
    assert has_element?(view, "#remote-action-logs [data-part=log-line]:nth-child(3) [data-part=log-ln]", "3")
    assert has_element?(view, "#remote-action-logs [data-part=log-line][data-annotation=error]", "undefined: Foo")
    refute has_element?(view, "#remote-action-logs [data-part=log-line][data-annotation=error]", "# svc")
    # Without a stored copy, a marker ends the truncated stream.
    assert has_element?(
             view,
             "#remote-action-logs [data-part=log-truncated]:last-child",
             "Standard error: the remaining 39.9 KB is not available"
           )

    refute has_element?(view, "#remote-action-logs [data-part=log-truncated]", "Standard output")
    refute has_element?(view, "[data-part=errors-card]")
    refute has_element?(view, "#remote-action-command")
    assert has_element?(view, "[data-part=back-button][href$=\"?tab=remote-execution\"]")
  end

  test "a failure without recognised errors shows its exit code and the end of stderr", %{
    conn: conn,
    project: project,
    invocation_id: invocation_id,
    path: path
  } do
    id = Ecto.UUID.generate()
    hash = String.duplicate("e", 64)
    stderr = Enum.map_join(1..15, "\n", &"line #{&1}")

    record = %{
      "operation_id" => id,
      "action_hash" => hash,
      "invocation_id" => invocation_id,
      "exit_code" => 3,
      "stderr" => stderr
    }

    {:ok, 1} = Actions.ingest(project, [record])

    {:ok, view, _html} = live(conn, path <> "/remote-actions/" <> id)

    assert has_element?(view, "[data-part=errors-card] .issue-card", "The command exited with code 3")
    assert has_element?(view, "[data-part=errors-card] [data-part=issue]", "line 15")
    refute has_element?(view, "[data-part=errors-card] [data-part=issue]", "line 5\n")

    ok = Ecto.UUID.generate()
    {:ok, 1} = Actions.ingest(project, [%{record | "operation_id" => ok, "exit_code" => 0}])
    {:ok, view, _html} = live(conn, path <> "/remote-actions/" <> ok)
    refute has_element?(view, "[data-part=errors-card]")
  end

  test "a long output list starts at ten paths and says when the record cut it", %{
    conn: conn,
    project: project,
    invocation_id: invocation_id,
    path: path
  } do
    id = Ecto.UUID.generate()
    outputs = Enum.map(1..15, &"bazel-out/gen/file_#{&1}.h")

    {:ok, 1} =
      Actions.ingest(project, [
        %{
          "operation_id" => id,
          "action_hash" => String.duplicate("e", 64),
          "invocation_id" => invocation_id,
          "arguments" => ["protoc"],
          "output_paths" => outputs,
          "output_count" => 1200
        }
      ])

    {:ok, view, _html} = live(conn, path <> "/remote-actions/" <> id)

    assert has_element?(view, "#remote-action-outputs [data-part=note]", "Showing 15 of 1200 outputs")
    assert has_element?(view, "#remote-action-outputs li:not([hidden])", "bazel-out/gen/file_10.h")
    assert has_element?(view, "#remote-action-outputs li[hidden]", "bazel-out/gen/file_11.h")
    assert has_element?(view, "#remote-action-outputs-expand", "Show all 15 outputs")
  end

  test "a long log loads its stored end: errors there count, and the log opens at the end", %{
    conn: conn,
    project: project,
    invocation_id: invocation_id,
    path: path
  } do
    id = Ecto.UUID.generate()
    preview = Enum.map_join(1..100, "", &"early #{&1}\n")
    # The only recognisable error is past the preview, in the stored end.
    tail = Enum.map_join(1..1200, "", &"late #{&1}\n") <> "svc/late.go:7:1: undefined: Late\n"
    size = 1_000_000

    {:ok, 1} =
      Actions.ingest(project, [
        %{
          "operation_id" => id,
          "action_hash" => String.duplicate("e", 64),
          "invocation_id" => invocation_id,
          "exit_code" => 1,
          "stderr" => preview,
          "stderr_size" => size,
          "stderr_truncated" => true
        }
      ])

    stub(Storage, :get_object_as_string, fn key, _actor ->
      if String.ends_with?(key, "/runs/#{invocation_id}/remote-actions/#{id}/stderr.log"), do: tail
    end)

    {:ok, view, _html} = live(conn, path <> "/remote-actions/" <> id)
    # Parsing the stored end takes longer than the default 100 ms under a loaded test run.
    render_async(view, 5_000)
    assert has_element?(view, "[data-part=errors-card] [data-part=issue]", "undefined: Late at svc/late.go:7:1")

    render_patch(view, path <> "/remote-actions/" <> id <> "?tab=logs")
    # 100 preview lines, the gap, then 1201 stored lines numbered after them.
    assert has_element?(view, "#remote-action-log-rows [data-part=log-line]:last-child [data-part=log-ln]", "1301")
    assert has_element?(view, "#remote-action-log-rows [data-part=log-line][data-annotation=error]", "undefined: Late")
    refute has_element?(view, "#remote-action-log-rows [data-part=log-truncated]")
    refute has_element?(view, "#remote-action-log-rows [data-part=log-line]", "early 1\n")

    view |> element("[data-part=load-earlier]") |> render_click()

    assert has_element?(
             view,
             "#remote-action-log-rows [data-part=log-truncated]",
             "Standard error: " <>
               ByteFormatter.format_bytes(size - byte_size(preview) - byte_size(tail)) <> " skipped"
           )

    assert has_element?(view, "#remote-action-log-rows [data-part=log-line]:first-child", "early 1")
    refute has_element?(view, "[data-part=load-earlier]")
  end

  test "an action of another invocation is not found", %{conn: conn, project: project, path: path} do
    id = Ecto.UUID.generate()

    {:ok, 1} =
      Actions.ingest(project, [
        %{"operation_id" => id, "action_hash" => String.duplicate("e", 64), "invocation_id" => "another"}
      ])

    assert_raise NotFoundError, fn -> live(conn, path <> "/remote-actions/" <> id) end
  end

  test "a finished action of a still-running invocation is shown", %{conn: conn, project: project, path: path} do
    id = Ecto.UUID.generate()
    running = Ecto.UUID.generate()

    {:ok, 1} =
      Actions.ingest(project, [
        %{
          "operation_id" => id,
          "action_hash" => String.duplicate("e", 64),
          "invocation_id" => running,
          "mnemonic" => "GoLink"
        }
      ])

    running_path = String.replace(path, ~r{invocations/[^/]+$}, "invocations/" <> running)
    {:ok, view, _html} = live(conn, running_path <> "/remote-actions/" <> id)

    assert has_element?(view, "h1", "GoLink")
    assert has_element?(view, "[data-part=back-button][href$=\"/invocations/#{running}?tab=remote-execution\"]")
  end

  test "an action the scheduler still runs shows what it knows until its record arrives", %{
    conn: conn,
    project: project,
    path: path
  } do
    id = Ecto.UUID.generate()
    running = Ecto.UUID.generate()

    live_action = %{
      id: id,
      state: "running",
      action_digest: String.duplicate("e", 64) <> "/187",
      invocation_id: running,
      mnemonic: "GoLink",
      target: "//svc:server",
      memory_gb: 8,
      since: DateTime.add(DateTime.utc_now(), -5, :second)
    }

    # Another invocation's operation with the same ID is not this action.
    stub(Scheduler, :activity, fn _account_id, _project_id -> {:ok, [%{live_action | invocation_id: "another"}]} end)
    running_path = String.replace(path, ~r{invocations/[^/]+$}, "invocations/" <> running)
    action_path = running_path <> "/remote-actions/" <> id
    assert_raise NotFoundError, fn -> live(conn, action_path) end

    stub(Scheduler, :activity, fn _account_id, _project_id -> {:ok, [live_action]} end)
    {:ok, view, _html} = live(conn, action_path)

    assert has_element?(view, "h1", "GoLink")
    assert has_element?(view, "[data-part=badge-processing]")
    assert has_element?(view, "[data-part=status]", "Running")
    assert has_element?(view, "[data-part=metadata]", "4 vCPU · 8 GB")
    assert has_element?(view, "#remote-action-pending")

    # Gone from the scheduler, its record not here yet: finishing.
    stub(Scheduler, :activity, fn _account_id, _project_id -> {:ok, []} end)
    send(view.pid, :refresh_pending)
    render_async(view)
    assert has_element?(view, "[data-part=status]", "Finishing")

    {:ok, 1} =
      Actions.ingest(project, [
        %{
          "operation_id" => id,
          "action_hash" => String.duplicate("e", 64),
          "invocation_id" => running,
          "mnemonic" => "GoLink"
        }
      ])

    send(view.pid, :refresh_pending)
    assert_redirect(view, action_path, 1_000)
  end
end
