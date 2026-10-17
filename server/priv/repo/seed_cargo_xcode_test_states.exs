# Matched synthetic flakiness and quarantine scenarios for the local comparison projects.
# Run after seed_cargo_analytics.exs and seed_xcode_comparison.exs in their isolated database.
import Ecto.Query

alias Tuist.Accounts
alias Tuist.ClickHouseRepo
alias Tuist.Projects.Project
alias Tuist.Repo
alias Tuist.Tests
alias Tuist.Tests.Test
alias Tuist.Tests.TestCase

if Mix.env() != :dev, do: raise("Comparison test-state seeds are only supported in development")

{:ok, user} = Accounts.get_user_by_email("tuistrocks@tuist.dev")
account = Repo.preload(user, :account).account
now = NaiveDateTime.utc_now()

for {project_name, build_system, modules, suites, names, scheme} <- [
      {"cargo-demo", "cargo", ["rust-store::lib", "rust-store::test/api", "rust-store::test/storage"],
       ["storage::index", "api::authentication", "storage::transactions"],
       [
         "creates_record",
         "reconnects_after_timeout",
         "handles_empty_input",
         "rejects_duplicates",
         "ignores_large_fixture"
       ], "synthetic-test-states"},
      {"xcode-demo", "xcode", ["StoreTests", "APITests", "TransactionsTests"],
       ["StoreTestsSuite", "APITestsSuite", "TransactionsTestsSuite"],
       ["testCreatesRecord", "testReconnects", "testEmptyInput", "testRejectsDuplicates", "testLargeFixture"],
       "StoreApp-TestStates"}
    ] do
  project = Repo.get_by!(Project, account_id: account.id, name: project_name)

  scenarios = [
    %{index: 0, module: 0, state: "enabled", flaky: false},
    %{index: 1, module: 1, state: "enabled", flaky: true},
    %{index: 2, module: 1, state: "muted", flaky: true},
    %{index: 3, module: 2, state: "muted", flaky: false},
    %{index: 4, module: 0, state: "skipped", flaky: false}
  ]

  for scenario <- scenarios do
    name = Enum.at(names, scenario.index)
    module = Enum.at(modules, scenario.module)
    suite = Enum.at(suites, scenario.module)

    test_case =
      ClickHouseRepo.one!(
        from(t in TestCase,
          where: t.project_id == ^project.id and t.name == ^name and t.module_name == ^module and t.suite_name == ^suite,
          limit: 1
        )
      )

    {:ok, _} =
      Tests.update_test_case(test_case.id, %{state: scenario.state, is_flaky: scenario.flaky}, actor_id: account.id)
  end

  existing = ClickHouseRepo.exists?(from(t in Test, where: t.project_id == ^project.id and t.scheme == ^scheme))

  if not existing do
    for day <- 6..0//-1 do
      test_modules =
        for module_index <- 0..2 do
          cases =
            scenarios
            |> Enum.filter(&(&1.module == module_index))
            |> Enum.map(fn scenario ->
              skipped = scenario.state == "skipped"
              muted_failure = scenario.state == "muted" and rem(day, 2) == 0

              status =
                cond do
                  skipped -> "skipped"
                  muted_failure -> "failure"
                  true -> "success"
                end

              duration = if skipped, do: 0, else: 60 + scenario.index * 25

              %{
                name: Enum.at(names, scenario.index),
                test_suite_name: Enum.at(suites, module_index),
                status: status,
                duration: duration,
                is_quarantined: scenario.state != "enabled",
                failures:
                  if(muted_failure,
                    do: [
                      %{
                        message: "Synthetic muted failure: intermittent external dependency",
                        path: "synthetic-fixtures",
                        line_number: 1,
                        issue_type: "assertion_failure"
                      }
                    ],
                    else: []
                  ),
                repetitions:
                  if(scenario.flaky and not skipped and not muted_failure,
                    do: [
                      %{name: "Attempt 1", repetition_number: 1, duration: 40, status: "failure"},
                      %{name: "Attempt 2", repetition_number: 2, duration: duration, status: "success"}
                    ],
                    else: []
                  )
              }
            end)

          duration = Enum.sum(Enum.map(cases, & &1.duration))
          suite = Enum.at(suites, module_index)

          %{
            name: Enum.at(modules, module_index),
            status: "success",
            duration: duration,
            test_cases: cases,
            test_suites: [%{name: suite, status: "success", duration: duration}]
          }
        end

      {:ok, _} =
        Tests.create_test(%{
          id: UUIDv7.generate(),
          project_id: project.id,
          account_id: account.id,
          build_system: build_system,
          scheme: scheme,
          execution_mode: "parallel",
          status: "success",
          is_ci: true,
          git_branch: "main",
          git_commit_sha: :sha |> :crypto.hash("synthetic-test-states-#{day}") |> Base.encode16(case: :lower),
          duration: Enum.max(Enum.map(test_modules, & &1.duration)) + 100,
          ran_at: NaiveDateTime.add(now, -(day * 86_400 + 60), :second),
          test_modules: test_modules
        })
    end
  end

  for buffer <- [
        Test.Buffer,
        TestCase.Buffer,
        Tests.TestCaseRun.Buffer,
        Tests.TestModuleRun.Buffer,
        Tests.TestSuiteRun.Buffer,
        Tests.TestCaseFailure.Buffer,
        Tests.TestCaseEvent.Buffer
      ],
      do: buffer.flush()

  root = "#{Tuist.Environment.app_url(route_type: :app)}/#{account.name}/#{project.name}/tests"
  IO.puts("#{project_name}: matched synthetic healthy, flaky, flaky-muted, muted and skipped cases")
  IO.puts("Flaky tests: #{root}/flaky-tests")
  IO.puts("Quarantined tests: #{root}/quarantined-tests")
end
