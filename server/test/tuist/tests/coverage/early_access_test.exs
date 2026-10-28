defmodule Tuist.Tests.Coverage.EarlyAccessTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Tests.Coverage.Commits
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.CoverageFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  @attrs %{
    coverage_evidence: %{
      paths: ["Sources/A.swift"],
      scopes: [%{kind: "test", module: "AppTests", suite: "ATests", name: "testA()", files: [0]}]
    }
  }

  @files [CoverageFixtures.file("Sources/A.swift", [1, 0])]

  setup do
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    %{account: account, project: ProjectsFixtures.project_fixture(account_id: account.id)}
  end

  # Production, where the `:xcode_coverage` flag decides, for an account that
  # doesn't have it.
  defp without_flag do
    stub(Environment, :env, fn -> :prod end)

    stub(FunWithFlags, :enabled?, fn
      :xcode_coverage, _opts -> false
      flag, opts -> Mimic.call_original(FunWithFlags, :enabled?, [flag, opts])
    end)
  end

  defp mix_run(project, account, files) do
    CoverageFixtures.run_with_coverage(project, account, [], %{
      build_system: "mix",
      xcode_coverage: nil,
      coverage: %{tool: "cover", tool_version: "OTP 28/Elixir 1.19.5", partial: false, files: files}
    })
  end

  test "a run of an account without the flag leaves nothing of coverage or test selection behind", %{
    account: account,
    project: project
  } do
    without_flag()
    run = CoverageFixtures.run_with_coverage(project, account, @files, Map.put(@attrs, :recompute, false))

    refute FeatureFlags.coverage_enabled?(account, project)
    # Read back with the flag on: what matters is that nothing was stored.
    stub(FunWithFlags, :enabled?, fn _flag, _opts -> true end)

    assert run.git_repository_id == 0
    assert CoverageFixtures.run_summary(project.id, run.id) == nil
    assert CoverageFixtures.evidence_rows(run) == []
  end

  test "the same run is kept in full once the account has it", %{account: account, project: project} do
    run = CoverageFixtures.run_with_coverage(project, account, @files, Map.put(@attrs, :recompute, false))

    assert run.git_repository_id > 0
    assert %{covered_lines: 1} = CoverageFixtures.run_summary(project.id, run.id)
    assert [%{scope_kind: "test", path: "Sources/A.swift"}] = CoverageFixtures.evidence_rows(run)
  end

  test "a Mix project has coverage without the flag", %{account: account} do
    project = ProjectsFixtures.project_fixture(account_id: account.id, build_system: :mix)
    without_flag()

    run = mix_run(project, account, [CoverageFixtures.file("lib/app.ex", [1, 0], targets: ["app"])])

    assert FeatureFlags.coverage_enabled?(account, project)
    assert run.git_repository_id > 0
    assert %{covered_lines: 1, executable_lines: 2} = CoverageFixtures.run_summary(project.id, run.id)
    assert %{covered_lines: 1} = Commits.summary(project.id, run.git_commit_sha)
  end

  test "an Xcode project of an account with a Mix project stays behind the flag", %{account: account, project: project} do
    _mix_project = ProjectsFixtures.project_fixture(account_id: account.id, build_system: :mix)
    without_flag()

    run = CoverageFixtures.run_with_coverage(project, account, @files)

    refute FeatureFlags.coverage_enabled?(account, project)
    assert run.git_repository_id == 0
    assert CoverageFixtures.run_summary(project.id, run.id) == nil
    assert Commits.summary(project.id, run.git_commit_sha) == nil
  end
end
