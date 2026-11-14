defmodule Tuist.MCP.SideQuestsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.MCP.Components.Tools.GetGradleBuild
  alias Tuist.MCP.Components.Tools.GetProject
  alias Tuist.MCP.Components.Tools.GetTestRun
  alias Tuist.MCP.Components.Tools.GetXcodeBuild
  alias Tuist.Repo
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Tests.Analytics
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AutomationsFixtures
  alias TuistTestSupport.Fixtures.GradleFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.RunsFixtures
  alias TuistTestSupport.Fixtures.ShardsFixtures

  setup do
    stub(Tuist.Environment, :tuist_hosted?, fn -> true end)
    user = AccountsFixtures.user_fixture(preload: [:account])
    %{user: user, account: user.account}
  end

  defp conn_for(subject, assigns \\ %{}), do: %Plug.Conn{assigns: Map.put(assigns, :current_subject, subject)}

  # What reaches the tools on `/mcp`: an OAuth session or `mcp` token, for the
  # account it was issued for, with or without the user behind it.
  defp mcp_subject(account, issued_by),
    do: %AuthenticatedAccount{account: account, scopes: ["mcp"], all_projects: true, issued_by: issued_by}

  defp side_quests(%{"structuredContent" => content}), do: Map.get(content, "side_quests")

  defp ids(result), do: Enum.map(side_quests(result) || [], & &1["id"])

  defp quest(result, id), do: result |> side_quests() |> Enum.find(&(&1["id"] == id))

  defp xcode_build(project, attrs) do
    {:ok, build} = RunsFixtures.build_fixture(attrs ++ [project_id: project.id, user_id: project.account_id])
    build
  end

  defp test_run(project, attrs) do
    {:ok, run} = RunsFixtures.test_fixture(attrs ++ [project_id: project.id, account_id: project.account_id])
    run
  end

  defp gradle_build(project, tasks),
    do: GradleFixtures.build_fixture(project_id: project.id, account_id: project.account_id, tasks: tasks)

  defp uncached_github_build(project),
    do:
      xcode_build(project,
        xcode_version: "26.1",
        category: "clean",
        cacheable_tasks_count: 0,
        is_ci: true,
        ci_provider: "github"
      )

  describe "who gets side quests" do
    test "members of the project's account, through a user session or an MCP token", %{user: user, account: account} do
      build = account.id |> then(&ProjectsFixtures.project_fixture(account_id: &1)) |> uncached_github_build()
      expected = ["xcode_compilation_cache", "tuist_runners", "pull_request_comments"]

      for subject <- [user, mcp_subject(account, user), mcp_subject(account, nil)] do
        assert ids(GetXcodeBuild.call(conn_for(subject), %{"build_run_id" => build.id})) == expected
      end
    end

    test "nobody outside the account, even when its project is public", %{account: account} do
      project = ProjectsFixtures.project_fixture(account_id: account.id, visibility: :public)
      build = uncached_github_build(project)
      outsider = AccountsFixtures.user_fixture(preload: [:account])

      for subject <- [outsider, mcp_subject(outsider.account, outsider), mcp_subject(outsider.account, nil)] do
        result = GetXcodeBuild.call(conn_for(subject), %{"build_run_id" => build.id})

        assert result["structuredContent"]["id"] == build.id
        refute Map.has_key?(result["structuredContent"], "side_quests")
      end
    end

    test "no Tuist operator reading through Atlas", %{user: user, account: account} do
      build = account.id |> then(&ProjectsFixtures.project_fixture(account_id: &1)) |> uncached_github_build()
      conn = conn_for(user, %{atlas_operator: AccountsFixtures.user_fixture()})

      refute Map.has_key?(GetXcodeBuild.call(conn, %{"build_run_id" => build.id})["structuredContent"], "side_quests")
    end
  end

  describe "get_xcode_build" do
    test "suggests runners with the provider's one-line switch", %{user: user, account: account} do
      build = account.id |> then(&ProjectsFixtures.project_fixture(account_id: &1)) |> uncached_github_build()

      result = GetXcodeBuild.call(conn_for(user), %{"build_run_id" => build.id})

      assert quest(result, "tuist_runners")["tip"] =~ "set the job's `runs-on` to `tuist-macos`"
      assert quest(result, "tuist_runners")["docs"] =~ "/runners/ci-providers/github-actions"
    end

    test "only suggests the compilation cache for processed clean builds", %{user: user, account: account} do
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      base = [xcode_version: "26.1", category: "clean", cacheable_tasks_count: 0]

      for attrs <- [
            [status: "processing"],
            [status: "failed_processing"],
            [category: "incremental"],
            [xcode_version: "16.4"],
            [cacheable_tasks_count: 12]
          ] do
        build = xcode_build(project, Keyword.merge(base, attrs))
        refute "xcode_compilation_cache" in ids(GetXcodeBuild.call(conn_for(user), %{"build_run_id" => build.id}))
      end

      build = xcode_build(project, Keyword.put(base, :status, "failure"))
      assert "xcode_compilation_cache" in ids(GetXcodeBuild.call(conn_for(user), %{"build_run_id" => build.id}))
    end

    test "leaves out what the account already uses", %{user: user, account: account} do
      project =
        ProjectsFixtures.project_fixture(account_id: account.id, vcs_connection: [repository_full_handle: "acme/app"])

      Repo.insert!(%WorkflowJob{
        workflow_job_id: System.unique_integer([:positive]),
        account_id: account.id,
        fleet_name: "tuist-macos",
        status: "completed",
        enqueued_at: DateTime.utc_now()
      })

      build = xcode_build(project, xcode_version: "26.1", cacheable_tasks_count: 12, is_ci: true, ci_provider: "github")

      refute Map.has_key?(
               GetXcodeBuild.call(conn_for(user), %{"build_run_id" => build.id})["structuredContent"],
               "side_quests"
             )
    end

    test "points Bitrise runs at the Bitrise guide and invites accounts without runners", %{
      user: user,
      account: account
    } do
      stub(Tuist.FeatureFlags, :runners_enabled?, fn _account -> false end)
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      build = xcode_build(project, is_ci: true, ci_provider: "bitrise")

      result = GetXcodeBuild.call(conn_for(user), %{"build_run_id" => build.id})

      assert ids(result) == ["tuist_runners"]
      assert quest(result, "tuist_runners")["tip"] =~ "This CI run used Bitrise machines"
      assert quest(result, "tuist_runners")["tip"] =~ "invite-only"
      assert quest(result, "tuist_runners")["tip"] =~ "contact@tuist.dev"
      assert quest(result, "tuist_runners")["docs"] =~ "/runners/ci-providers/bitrise"
    end

    test "does not suggest runners on a self-hosted server or for providers they don't support", %{
      user: user,
      account: account
    } do
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      circleci = xcode_build(project, is_ci: true, ci_provider: "circleci")
      github = xcode_build(project, is_ci: true, ci_provider: "github")

      refute "tuist_runners" in ids(GetXcodeBuild.call(conn_for(user), %{"build_run_id" => circleci.id}))

      stub(Tuist.Environment, :tuist_hosted?, fn -> false end)
      refute "tuist_runners" in ids(GetXcodeBuild.call(conn_for(user), %{"build_run_id" => github.id}))
    end
  end

  describe "get_test_run" do
    test "suggests quarantining flaky tests until an enabled automation mutes or skips them", %{
      user: user,
      account: account
    } do
      stub(Analytics, :get_test_run_metrics, fn _run ->
        %{total_count: 10, failed_count: 0, flaky_count: 2, avg_duration: 100}
      end)

      # Every project starts with an automation that only labels flaky tests.
      project =
        ProjectsFixtures.project_fixture(account_id: account.id, build_system: :gradle, with_default_alert: true)

      run = test_run(project, build_system: "gradle")

      AutomationsFixtures.automation_alert_fixture(
        project: project,
        enabled: false,
        trigger_actions: [%{"type" => "change_state", "state" => "muted"}]
      )

      result = GetTestRun.call(conn_for(user), %{"test_run_id" => run.id})

      assert quest(result, "flaky_test_quarantine")["tip"] =~ "2 flaky tests ran here"
      assert quest(result, "flaky_test_quarantine")["docs"] =~ "/flaky-tests/gradle"

      AutomationsFixtures.automation_alert_fixture(
        project: project,
        trigger_actions: [%{"type" => "change_state", "state" => "skipped"}]
      )

      refute "flaky_test_quarantine" in ids(GetTestRun.call(conn_for(user), %{"test_run_id" => run.id}))
    end

    test "does not suggest quarantine to Once projects, which can't quarantine", %{user: user, account: account} do
      stub(Analytics, :get_test_run_metrics, fn _run ->
        %{total_count: 10, failed_count: 0, flaky_count: 2, avg_duration: 100}
      end)

      project = ProjectsFixtures.project_fixture(account_id: account.id, build_system: :once)
      run = test_run(project, build_system: "once")

      refute "flaky_test_quarantine" in ids(GetTestRun.call(conn_for(user), %{"test_run_id" => run.id}))
    end

    test "suggests runners and pull request comments for GitHub Actions runs", %{user: user, account: account} do
      project = ProjectsFixtures.project_fixture(account_id: account.id, build_system: :gradle)
      run = test_run(project, build_system: "gradle", is_ci: true, ci_provider: "github")

      result = GetTestRun.call(conn_for(user), %{"test_run_id" => run.id})

      assert ids(result) == ["tuist_runners", "pull_request_comments"]
      assert quest(result, "tuist_runners")["tip"] =~ "`tuist-linux`"
    end

    test "suggests sharding a slow CI run, noting what selective testing already skipped", %{
      user: user,
      account: account
    } do
      project = ProjectsFixtures.project_fixture(account_id: account.id)
      slow = test_run(project, is_ci: true, duration: to_timeout(minute: 14))

      RunsFixtures.run_selection_fixture(
        project_id: project.id,
        test_run_id: slow.id,
        ran_at: slow.ran_at,
        avoided_tests: 320,
        scope_tests: 900
      )

      result = GetTestRun.call(conn_for(user), %{"test_run_id" => slow.id})

      assert quest(result, "test_sharding")["tip"] =~
               "took 14 minutes on a single job even though selective testing already skipped 320 of its 900 tests."

      assert quest(result, "test_sharding")["docs"] =~ "/test-sharding/xcode"

      unselected = test_run(project, is_ci: true, duration: to_timeout(minute: 10))

      assert quest(GetTestRun.call(conn_for(user), %{"test_run_id" => unselected.id}), "test_sharding")["tip"] =~
               "took 10 minutes on a single job. "

      for attrs <- [
            [is_ci: true, duration: to_timeout(minute: 9)],
            [is_ci: false, duration: to_timeout(minute: 14)],
            [
              is_ci: true,
              duration: to_timeout(minute: 14),
              shard_plan_id: ShardsFixtures.shard_plan_fixture(project_id: project.id, shard_count: 1).id,
              shard_index: 0
            ]
          ] do
        run = test_run(project, attrs)
        refute "test_sharding" in ids(GetTestRun.call(conn_for(user), %{"test_run_id" => run.id}))
      end
    end
  end

  describe "get_gradle_build" do
    test "suggests the build cache only when Gradle never consulted it", %{user: user, account: account} do
      project = ProjectsFixtures.project_fixture(account_id: account.id, build_system: :gradle)
      compile = %{task_path: ":app:compileKotlin", cacheable: true, duration_ms: 2000}

      cache_off = gradle_build(project, [Map.put(compile, :outcome, "executed")])

      assert ids(GetGradleBuild.call(conn_for(user), %{"build_run_id" => cache_off})) == ["gradle_build_cache"]

      # A read-only build whose lookups all missed has the cache on.
      read_only_miss =
        gradle_build(project, [Map.merge(compile, %{outcome: "executed", cache_key: "abc", remote_cache_miss: true})])

      cached = gradle_build(project, [Map.merge(compile, %{outcome: "remote_hit", cache_artifact_size: 10})])

      for build_id <- [read_only_miss, cached] do
        refute "gradle_build_cache" in ids(GetGradleBuild.call(conn_for(user), %{"build_run_id" => build_id}))
      end
    end
  end

  describe "get_project" do
    test "suggests the build systems the account doesn't use yet", %{user: user, account: account} do
      ProjectsFixtures.project_fixture(account_id: account.id, name: "app")
      ProjectsFixtures.project_fixture(account_id: account.id, build_system: :gradle)

      result = GetProject.call(conn_for(user), %{"account_handle" => account.name, "project_handle" => "app"})

      tip = quest(result, "other_build_systems")["tip"]
      assert tip =~ "only uses Tuist with Xcode and Gradle projects"
      assert tip =~ "Bazel (`MODULE.bazel`"
      assert tip =~ "Rust (`Cargo.toml`; its cache is experimental)"
      refute tip =~ "Gradle (`"
      refute tip =~ "Once"
    end

    test "has nothing to suggest once the account uses every build system", %{user: user, account: account} do
      ProjectsFixtures.project_fixture(account_id: account.id, name: "app")

      for build_system <- [:gradle, :bazel, :mix, :cargo],
          do: ProjectsFixtures.project_fixture(account_id: account.id, build_system: build_system)

      result = GetProject.call(conn_for(user), %{"account_handle" => account.name, "project_handle" => "app"})

      refute Map.has_key?(result["structuredContent"], "side_quests")
    end
  end
end
