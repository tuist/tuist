defmodule Tuist.Tests.Coverage.BuildSystemsTest do
  use TuistTestSupport.Cases.DataCase, async: false
  use Mimic

  import Ecto.Query

  alias Tuist.Environment
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage
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

  # Production, where coverage once needed an account flag: no account has
  # any coverage flag here.
  setup do
    stub(Environment, :env, fn -> :prod end)
    account = AccountsFixtures.user_fixture(preload: [:account]).account
    %{account: account, project: ProjectsFixtures.project_fixture(account_id: account.id)}
  end

  defp mix_run(project, account, files) do
    CoverageFixtures.run_with_coverage(project, account, [], %{
      build_system: "mix",
      xcode_coverage: nil,
      coverage: %{tool: "cover", tool_version: "OTP 28/Elixir 1.19.5", partial: false, files: files}
    })
  end

  # A `tuist cargo` run: nextest's carries each test's own evidence, plain
  # `cargo test`'s its binaries' and the tests that shared their processes.
  defp cargo_run(project, account, evidence) do
    CoverageFixtures.run_with_coverage(project, account, [], %{
      build_system: "cargo",
      scheme: "",
      xcode_coverage: nil,
      test_modules: [
        %{
          name: "cov-fixture::api",
          status: "success",
          duration: 10,
          test_cases: [
            %{name: "grows", test_suite_name: "", status: "success", duration: 5},
            %{name: "applies", test_suite_name: "", status: "success", duration: 5}
          ]
        }
      ],
      coverage: %{
        tool: "llvm-cov",
        tool_version: "rustc 1.99.1/LLVM 21.1.8",
        platform: "aarch64-apple-darwin",
        partial: false,
        files: [CoverageFixtures.file("src/shapes.rs", [1, 0, 2], targets: ["cov-fixture"])]
      },
      coverage_evidence: evidence
    })
  end

  defp evidence_flags(run) do
    Tuist.ClickHouseRepo.all(
      from(r in Tuist.Tests.TestCaseRun,
        where: r.test_run_id == ^run.id,
        order_by: r.name,
        select: {r.name, r.coverage_evidence}
      )
    )
  end

  test "only Xcode, Mix and Cargo projects have coverage" do
    for {build_system, supported?} <- [xcode: true, mix: true, cargo: true, gradle: false, bazel: false, once: false] do
      assert Coverage.supported?(%Project{build_system: build_system}) == supported?
    end
  end

  test "an Xcode project's run is kept in full in every account", %{account: account, project: project} do
    run = CoverageFixtures.run_with_coverage(project, account, @files, Map.put(@attrs, :recompute, false))

    assert run.git_repository_id > 0
    assert %{covered_lines: 1} = CoverageFixtures.run_summary(project.id, run.id)
    assert [%{scope_kind: "test", path: "Sources/A.swift"}] = CoverageFixtures.evidence_rows(run)
  end

  test "a run of a build system without coverage leaves nothing of coverage or test selection behind", %{
    account: account
  } do
    for build_system <- [:gradle, :bazel, :once] do
      project = ProjectsFixtures.project_fixture(account_id: account.id, build_system: build_system)
      run = CoverageFixtures.run_with_coverage(project, account, @files, @attrs)

      assert run.git_repository_id == 0
      assert CoverageFixtures.run_summary(project.id, run.id) == nil
      assert CoverageFixtures.evidence_rows(run) == []
      assert Commits.summary(project.id, run.git_commit_sha) == nil
    end
  end

  test "a Mix project's coverage is kept", %{account: account} do
    project = ProjectsFixtures.project_fixture(account_id: account.id, build_system: :mix)

    run = mix_run(project, account, [CoverageFixtures.file("lib/app.ex", [1, 0], targets: ["app"])])

    assert run.git_repository_id > 0
    assert %{covered_lines: 1, executable_lines: 2} = CoverageFixtures.run_summary(project.id, run.id)
    assert %{covered_lines: 1} = Commits.summary(project.id, run.git_commit_sha)
  end

  test "a Cargo project's coverage and evidence are kept", %{account: account} do
    project = ProjectsFixtures.project_fixture(account_id: account.id, build_system: :cargo)
    target = %{kind: "target", module: "cov-fixture::api", suite: "", name: "", files: [0], lines: [[1, 1], [3, 3]]}

    nextest =
      cargo_run(project, account, %{
        paths: ["src/shapes.rs"],
        scopes: [
          target,
          %{kind: "test", module: "cov-fixture::api", suite: "", name: "grows", files: [0], lines: [[3, 3]]}
        ]
      })

    assert nextest.git_repository_id > 0
    assert %{covered_lines: 2, executable_lines: 3, partial: false} = CoverageFixtures.run_summary(project.id, nextest.id)
    assert [%{name: "cov-fixture", covered_lines: 2}] = CoverageFixtures.targets_for_run(project.id, nextest.id)
    assert ["target", "test"] = nextest |> CoverageFixtures.evidence_rows() |> Enum.map(& &1.scope_kind)
    assert evidence_flags(nextest) == [{"applies", "none"}, {"grows", "own"}]

    cargo_test =
      cargo_run(project, account, %{
        paths: ["src/shapes.rs"],
        scopes: [target],
        overlapped_tests: [
          %{module: "cov-fixture::api", suite: "", name: "grows"},
          %{module: "cov-fixture::api", suite: "", name: "applies"}
        ]
      })

    assert ["target"] = cargo_test |> CoverageFixtures.evidence_rows() |> Enum.map(& &1.scope_kind)
    assert evidence_flags(cargo_test) == [{"applies", "overlapped"}, {"grows", "overlapped"}]
  end
end
