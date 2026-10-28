# Bounded, synthetic Xcode build/test data for comparison with the Cargo demo.
# Run in the same isolated development database as seed_cargo_analytics.exs.
import Ecto.Query

alias Tuist.Accounts
alias Tuist.Builds
alias Tuist.Builds.Build
alias Tuist.ClickHouseRepo
alias Tuist.Projects
alias Tuist.Projects.Project
alias Tuist.Repo
alias Tuist.Tests
alias Tuist.Tests.Test

if Mix.env() != :dev, do: raise("Xcode comparison seeds are only supported in development")

{:ok, user} = Accounts.get_user_by_email("tuistrocks@tuist.dev")
account = Repo.preload(user, :account).account

project =
  Repo.get_by(Project, account_id: account.id, name: "xcode-demo") ||
    Projects.create_project!(%{name: "xcode-demo", account: %{id: account.id}}, build_system: :xcode, visibility: :public)

now = NaiveDateTime.utc_now()

if not ClickHouseRepo.exists?(from(b in Build, where: b.project_id == ^project.id)) do
  for index <- 1..42 do
    failed = index in [9, 23, 42]
    timestamp = NaiveDateTime.add(now, -(42 - index) * 28_800, :second)

    {:ok, _} =
      Builds.create_build(%{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        duration: 18_000 + rem(index * 7919, 32_000),
        status: if(failed, do: "failure", else: "success"),
        category: if(rem(index, 4) == 0, do: "clean", else: "incremental"),
        scheme: "StoreApp",
        configuration: "Debug",
        is_ci: rem(index, 3) != 0,
        ci_provider: "github",
        git_branch: "main",
        git_commit_sha: :sha |> :crypto.hash("synthetic-xcode-#{index}") |> Base.encode16(case: :lower),
        xcode_version: "26.0",
        macos_version: "26.0",
        model_identifier: "Mac15,6",
        inserted_at: timestamp,
        custom_tags: ["synthetic-demo"]
      })
  end

  Build.Buffer.flush()
end

if not ClickHouseRepo.exists?(from(t in Test, where: t.project_id == ^project.id)) do
  for day <- 13..0//-1, attempt <- 1..3 do
    failed = day == 0 && attempt == 3

    modules =
      Enum.with_index(["StoreTests", "APITests", "TransactionsTests"], fn name, module_index ->
        suite = "#{name}Suite"

        cases =
          Enum.with_index(
            ["testCreatesRecord", "testRejectsDuplicates", "testReconnects", "testEmptyInput", "testLargeFixture"],
            fn name, case_index ->
              failure = failed && module_index == 2 && case_index == 1
              retry = rem(day + attempt, 4) == 0 && module_index == 1 && case_index == 2

              status =
                cond do
                  failure -> "failure"
                  case_index == 4 -> "skipped"
                  true -> "success"
                end

              duration = if(status == "skipped", do: 0, else: 50 + rem(day * 13 + attempt * 17 + case_index * 23, 200))

              %{
                name: name,
                test_suite_name: suite,
                status: status,
                duration: duration,
                failures:
                  if(failure,
                    do: [
                      %{
                        message: "XCTAssertEqual failed: duplicate record was accepted (synthetic demo)",
                        path: "Tests/TransactionsTests.swift",
                        line_number: 57,
                        issue_type: "assertion_failure"
                      }
                    ],
                    else: []
                  ),
                repetitions:
                  if(retry,
                    do: [
                      %{name: "Attempt 1", repetition_number: 1, duration: 110, status: "failure"},
                      %{name: "Attempt 2", repetition_number: 2, duration: duration, status: "success"}
                    ],
                    else: []
                  )
              }
            end
          )

        status = if(Enum.any?(cases, &(&1.status == "failure")), do: "failure", else: "success")
        duration = Enum.sum(Enum.map(cases, & &1.duration))

        %{
          name: name,
          status: status,
          duration: duration,
          test_cases: cases,
          test_suites: [%{name: suite, duration: duration, status: status}]
        }
      end)

    {:ok, _} =
      Tests.create_test(%{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        build_system: "xcode",
        scheme: "StoreApp",
        execution_mode: "parallel",
        status: if(failed, do: "failure", else: "success"),
        duration: Enum.max(Enum.map(modules, & &1.duration)) + 100,
        is_ci: true,
        ci_provider: "github",
        git_branch: "main",
        xcode_version: "26.0",
        macos_version: "26.0",
        model_identifier: "Mac15,6",
        ran_at: NaiveDateTime.add(now, -(day * 86_400 + (3 - attempt) * 3600), :second),
        test_modules: modules
      })
  end

  for buffer <- [
        Test.Buffer,
        Tests.TestCase.Buffer,
        Tests.TestCaseRun.Buffer,
        Tests.TestModuleRun.Buffer,
        Tests.TestSuiteRun.Buffer,
        Tests.TestCaseFailure.Buffer
      ],
      do: buffer.flush()
end

root = "#{Tuist.Environment.app_url(route_type: :app)}/#{account.name}/#{project.name}"
IO.puts("Xcode comparison ready (synthetic data). Overview: #{root}")
IO.puts("Builds: #{root}/builds/build-runs")
IO.puts("Tests: #{root}/tests/test-runs")
