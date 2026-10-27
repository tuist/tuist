# Synthetic Cargo and nextest demo data for local development.
# Run with `mix run priv/repo/seed_cargo_analytics.exs` in an isolated development database.

import Ecto.Query

alias Tuist.Accounts
alias Tuist.Cargo
alias Tuist.Cargo.Build
alias Tuist.ClickHouseRepo
alias Tuist.Projects
alias Tuist.Projects.Project
alias Tuist.Repo
alias Tuist.Shards
alias Tuist.Tests

if Mix.env() != :dev, do: raise("Cargo demo seeds are only supported in development")

:rand.seed(:exsss, {2026, 10, 7})

user =
  case Accounts.get_user_by_email("tuistrocks@tuist.dev") do
    {:ok, user} ->
      user

    {:error, :not_found} ->
      {:ok, user} =
        Accounts.create_user("tuistrocks@tuist.dev",
          password: "tuistrocks",
          confirmed_at: NaiveDateTime.utc_now(),
          setup_billing: false
        )

      user
  end

account = Repo.preload(user, :account).account

project =
  Repo.get_by(Project, account_id: account.id, name: "cargo-demo") ||
    Projects.create_project!(%{name: "cargo-demo", account: %{id: account.id}}, build_system: :cargo, visibility: :public)

now = DateTime.utc_now()
binaries = ["rust-store::lib", "rust-store::test/api", "rust-store::test/storage"]

existing = ClickHouseRepo.one(from(b in Build, where: b.project_id == ^project.id, select: count()))

if existing == 0 do
  for index <- 1..36 do
    failed = index in [9, 23, 36]

    {:ok, _} =
      Cargo.create_build(%{
        id: Ecto.UUID.generate(),
        project_id: project.id,
        account_id: account.id,
        command: "build",
        status: if(failed, do: "failure", else: "success"),
        duration_ms: 4500 + :rand.uniform(12_000),
        rust_version: "rustc 1.97.1",
        contract_version: "1",
        is_ci: true,
        started_at: DateTime.add(now, -(36 - index) * 1800, :second),
        git_branch: if(failed, do: "feat/storage-index", else: "main"),
        git_commit_sha: :sha |> :crypto.hash("cargo-demo-#{index}") |> Base.encode16(case: :lower),
        compilations:
          Enum.with_index(
            [
              {"serde", "registry/serde/src/lib.rs", [], 1600},
              {"tokio", "registry/tokio/src/lib.rs", [], 2400},
              {"rust-store", "src/lib.rs", ["serde", "tokio"], 3200},
              {"rust-store-api", "src/main.rs", ["rust_store"], 1900}
            ],
            fn {name, source, dependencies, duration}, position ->
              failure = failed && position == 2

              %{
                name: name,
                source: source,
                dependencies: dependencies,
                kind: "lib",
                start_offset_ms: position * 1100,
                duration_ms: duration + :rand.uniform(800),
                status: if(failure, do: "failure", else: "success"),
                diagnostics:
                  cond do
                    failure ->
                      [
                        %{
                          severity: "error",
                          message:
                            "error[E0308]: mismatched types: expected `Result<Record, StoreError>`, found `Option<Record>`",
                          file: "src/storage/index.rs",
                          line: 84
                        }
                      ]

                    position == 3 ->
                      [%{severity: "warning", message: "unused variable: `request_id`", file: "src/main.rs", line: 42}]

                    true ->
                      []
                  end
              }
            end
          )
      })
  end

  for day <- 13..0//-1, attempt <- 1..3 do
    failed = day == 0 && attempt == 3
    flaky = rem(day + attempt, 4) == 0

    modules =
      Enum.with_index(binaries, fn binary, binary_index ->
        suite = Enum.at(["storage::index", "api::authentication", "storage::transactions"], binary_index)

        cases =
          Enum.with_index(
            [
              "creates_record",
              "rejects_duplicates",
              "reconnects_after_timeout",
              "handles_empty_input",
              "ignores_large_fixture"
            ],
            fn name, case_index ->
              failure = failed && binary_index == 2 && case_index == 1
              retry = flaky && binary_index == 1 && case_index == 2

              status =
                cond do
                  failure -> "failure"
                  case_index == 4 -> "skipped"
                  true -> "success"
                end

              duration = if(status == "skipped", do: 0, else: 20 + :rand.uniform(180))

              %{
                name: name,
                test_suite_name: suite,
                status: status,
                duration: duration,
                failures:
                  if(failure,
                    do: [
                      %{
                        message: "assertion `left == right` failed\n  left: Ok(2)\n right: Err(DuplicateKey)",
                        path: "tests/storage.rs",
                        line_number: 57,
                        issue_type: "assertion_failure"
                      }
                    ],
                    else: []
                  ),
                repetitions:
                  if(retry,
                    do: [
                      %{name: "Attempt 1", repetition_number: 1, duration: 110, status: "failure", source: "run"},
                      %{name: "Attempt 2", repetition_number: 2, duration: duration, status: "success", source: "run"}
                    ],
                    else: []
                  )
              }
            end
          )

        status = if(Enum.any?(cases, &(&1.status == "failure")), do: "failure", else: "success")
        duration = Enum.sum(Enum.map(cases, & &1.duration))

        %{
          name: binary,
          status: status,
          duration: duration,
          test_suites: [%{name: suite, duration: duration, status: status}],
          test_cases: cases
        }
      end)

    {:ok, _} =
      Tests.create_test(%{
        id: UUIDv7.generate(),
        project_id: project.id,
        account_id: account.id,
        build_system: "cargo",
        scheme: "nextest",
        execution_mode: "parallel",
        status: if(failed, do: "failure", else: "success"),
        duration: Enum.max(Enum.map(modules, & &1.duration)) + 100,
        is_ci: true,
        ci_provider: "github",
        git_branch: "main",
        git_commit_sha: :sha |> :crypto.hash("nextest-demo-#{day}-#{attempt}") |> Base.encode16(case: :lower),
        ran_at: now |> DateTime.add(-(day * 86_400 + (3 - attempt) * 3600), :second) |> DateTime.to_naive(),
        test_modules: modules,
        enumerated_tests:
          Enum.flat_map(modules, fn module ->
            Enum.map(
              module.test_cases,
              &%{module: module.name, suite: &1.test_suite_name, name: &1.name, enabled: &1.status != "skipped"}
            )
          end)
      })
  end

  for buffer <- [
        Tuist.Cargo.Build.Buffer,
        Tuist.Cargo.Compilation.Buffer,
        Tuist.Tests.Test.Buffer,
        Tuist.Tests.TestCase.Buffer,
        Tuist.Tests.TestCaseRun.Buffer,
        Tuist.Tests.TestModuleRun.Buffer,
        Tuist.Tests.TestSuiteRun.Buffer,
        Tuist.Tests.TestCaseFailure.Buffer
      ],
      do: buffer.flush()

  Shards.create_shard_plan(project, %{
    reference: "cargo-demo-compile-once",
    modules: binaries,
    parallelizable_modules: binaries,
    granularity: "module",
    shard_total: 2
  })
end

build =
  ClickHouseRepo.one(
    from(b in Build,
      where: b.project_id == ^project.id and b.status == "failure",
      order_by: [desc: b.inserted_at],
      limit: 1
    )
  )

test =
  ClickHouseRepo.one(
    from(t in Tuist.Tests.Test,
      where: t.project_id == ^project.id and t.status == "failure",
      order_by: [desc: t.ran_at],
      limit: 1
    )
  )

base = Tuist.Environment.app_url(route_type: :app)
root = "#{base}/#{account.name}/#{project.name}"

IO.puts("""
Cargo demo ready (synthetic data): 36 builds, 42 nextest runs, 3 binaries, one two-shard plan.
Login: #{base}/users/log_in (tuistrocks@tuist.dev / tuistrocks)
Overview: #{root}
Builds: #{root}/builds/build-runs
Failed build: #{root}/builds/cargo-builds/#{build.id}
Tests: #{root}/tests/test-runs
Failed test run: #{root}/tests/test-runs/#{test.id}
Test cases: #{root}/tests/test-cases
Shards: #{root}/tests/shards
""")
