defmodule TuistWeb.RunnerJobLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.Jobs
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Errors.NotFoundError

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "test-runner-job-org-#{System.unique_integer([:positive])}",
        creator: user,
        preload: [:account]
      )

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, account: account}
  end

  test "renders metadata for a queued job", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_001,
        account_id: account.id,
        fleet_name: "macos-xcode-26.4",
        repository: "tuist/tuist",
        workflow_run_id: 310_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Docker build",
        head_branch: "main",
        head_sha: "abcdef1234567890"
      })

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/310010/jobs/31001")

    assert html =~ "Server · Docker build"
    assert html =~ "tuist/tuist"
    assert html =~ "macOS"
    assert html =~ "Queued"
    # short_sha takes the first 7 chars
    assert html =~ "abcdef1"
  end

  test "renders timeline durations once a job has run", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_101,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/cli",
        workflow_run_id: 311_010,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Unit Tests",
        head_branch: "main",
        head_sha: "1234567"
      })

    {:ok, candidate} = Jobs.pick_queued("linux-amd64", [])
    :ok = Jobs.record_claimed(candidate, "pod-x", DateTime.utc_now())
    :ok = Jobs.record_running(31_101, "tuist-runner-x")
    {:ok, _completed} = Jobs.complete(31_101, "success")

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/311010/jobs/31101")

    assert html =~ "CLI · Unit Tests"
    assert html =~ "Linux"
    # status_badge_props maps conclusion=success → "Passed"
    assert html =~ "Passed"
  end

  test "renders the captured steps for a completed job", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_401,
        account_id: account.id,
        fleet_name: "macos-xcode-26.4",
        repository: "tuist/tuist",
        workflow_run_id: 314_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abcdef1"
      })

    {:ok, candidate} = Jobs.pick_queued("macos-xcode-26.4", [])
    :ok = Jobs.record_claimed(candidate, "pod-x", DateTime.utc_now())
    :ok = Jobs.record_running(31_401, "tuist-runner-x")

    steps =
      JSON.encode!([
        %{
          "name" => "Set up job",
          "status" => "completed",
          "conclusion" => "success",
          "number" => 1,
          "started_at" => "2026-05-28T10:00:00Z",
          "completed_at" => "2026-05-28T10:00:05Z"
        },
        %{
          "name" => "Run tests",
          "status" => "completed",
          "conclusion" => "failure",
          "number" => 2,
          "started_at" => "2026-05-28T10:00:05Z",
          "completed_at" => "2026-05-28T10:00:35Z"
        }
      ])

    {:ok, _completed} = Jobs.complete(31_401, "failure", steps)

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/314010/jobs/31401")

    assert html =~ "Steps"
    assert html =~ "Set up job"
    assert html =~ "Run tests"
    # 30-second duration badge for the failing step
    assert html =~ "30.0s"
  end

  test "renders the steps empty state for a job without captured steps", %{
    conn: conn,
    account: account
  } do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_501,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/cli",
        workflow_run_id: 315_010,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Lint",
        head_branch: "main",
        head_sha: "1234567"
      })

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/runners/runs/315010/jobs/31501")

    assert html =~ "No steps have been recorded"
  end

  test "renders captured logs and live-appends streamed lines", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_601,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: 316_010,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abc"
      })

    :ok =
      JobLogs.append([
        %{
          workflow_job_id: 31_601,
          account_id: account.id,
          line_number: 1,
          ts: ~U[2026-05-28 12:00:00.000000Z],
          message: "compiling project"
        }
      ])

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/runners/runs/316010/jobs/31601")

    assert html =~ "Logs"
    assert html =~ "compiling project"

    send(
      lv.pid,
      {:runner_job_log_lines,
       %{lines: [%{line_number: 2, ts: ~U[2026-05-28 12:00:01.000000Z], message: "linking binary"}]}}
    )

    assert render(lv) =~ "linking binary"
  end

  test "expanding a step reveals only that step's logs", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_602,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: 316_020,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abc"
      })

    {:ok, candidate} = Jobs.pick_queued("linux-amd64", [])
    :ok = Jobs.record_claimed(candidate, "pod-x", DateTime.utc_now())
    :ok = Jobs.record_running(31_602, "runner-x")

    steps =
      JSON.encode!([
        %{
          "name" => "Build",
          "status" => "completed",
          "conclusion" => "success",
          "number" => 1,
          "started_at" => "2026-05-28T12:00:00Z",
          "completed_at" => "2026-05-28T12:01:00Z"
        }
      ])

    {:ok, _} = Jobs.complete(31_602, "success", steps)

    :ok =
      JobLogs.append([
        %{
          workflow_job_id: 31_602,
          account_id: account.id,
          line_number: 1,
          ts: ~U[2026-05-28 12:00:30.000000Z],
          message: "inside the build step"
        },
        %{
          workflow_job_id: 31_602,
          account_id: account.id,
          line_number: 2,
          ts: ~U[2026-05-28 12:05:00.000000Z],
          message: "after the build step"
        }
      ])

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/runners/runs/316020/jobs/31602")

    lv |> element(~s{[data-part="step-header"]}) |> render_click()
    panel = lv |> element(~s{[data-part="step-logs"]}) |> render()

    assert panel =~ "inside the build step"
    refute panel =~ "after the build step"
  end

  test "defaults to the Overview tab and selects Logs via ?tab=logs", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_701,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: 317_010,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abc"
      })

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/runners/runs/317010/jobs/31701")
    assert has_element?(lv, ~s{.noora-tab-menu-horizontal-item[data-selected]}, "Overview")
    refute has_element?(lv, ~s{.noora-tab-menu-horizontal-item[data-selected]}, "Logs")

    {:ok, lv2, _html} = live(conn, ~p"/#{account.name}/runners/runs/317010/jobs/31701?tab=logs")
    assert has_element?(lv2, ~s{.noora-tab-menu-horizontal-item[data-selected]}, "Logs")
    refute has_element?(lv2, ~s{.noora-tab-menu-horizontal-item[data-selected]}, "Overview")
  end

  test "loads only the tail and pages older logs on demand", %{conn: conn, account: account} do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_801,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: 318_010,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abc"
      })

    # More than one page (page size is 200), so the oldest line is not
    # in the initial tail.
    :ok =
      JobLogs.append(
        for n <- 1..250 do
          %{
            workflow_job_id: 31_801,
            account_id: account.id,
            line_number: n,
            ts: DateTime.add(~U[2026-05-28 12:00:00.000000Z], n, :second),
            message: if(n == 1, do: "FIRST_LINE_MARKER", else: "line #{n}")
          }
        end
      )

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/runners/runs/318010/jobs/31801?tab=logs")

    refute html =~ "FIRST_LINE_MARKER"
    assert has_element?(lv, ~s{[phx-click="load_older"]})

    html_after = lv |> element(~s{[phx-click="load_older"]}) |> render_click()

    assert html_after =~ "FIRST_LINE_MARKER"
    refute has_element?(lv, ~s{[phx-click="load_older"]})
  end

  test "raises 404 when the workflow_job_id belongs to another account", %{
    conn: conn,
    account: account
  } do
    other = AccountsFixtures.user_fixture().account

    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_201,
        account_id: other.id,
        fleet_name: "fleet-x",
        repository: "evil/corp",
        workflow_run_id: 312_010,
        workflow_name: "Evil",
        run_attempt: 1,
        job_name: "hidden",
        head_branch: "main",
        head_sha: "dead"
      })

    assert_raise NotFoundError, fn ->
      live(conn, ~p"/#{account.name}/runners/runs/312010/jobs/31201")
    end
  end

  test "raises 404 when the workflow_run_id in the URL doesn't match the job's run", %{
    conn: conn,
    account: account
  } do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 31_301,
        account_id: account.id,
        fleet_name: "fleet-y",
        repository: "tuist/tuist",
        workflow_run_id: 313_010,
        workflow_name: "Server",
        run_attempt: 1,
        job_name: "build",
        head_branch: "main",
        head_sha: "deadbeef"
      })

    assert_raise NotFoundError, fn ->
      # Job exists under run 313010, URL claims 999999 — 404 the
      # same way GitHub would.
      live(conn, ~p"/#{account.name}/runners/runs/999999/jobs/31301")
    end
  end

  test "raises 404 for a non-integer workflow_job_id", %{conn: conn, account: account} do
    assert_raise NotFoundError, fn ->
      live(conn, ~p"/#{account.name}/runners/runs/312010/jobs/notanumber")
    end
  end
end
