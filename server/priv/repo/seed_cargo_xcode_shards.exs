# Matched synthetic sharded CI histories for the existing Cargo/Xcode comparison projects.
# Run after seed_cargo_analytics.exs and seed_xcode_comparison.exs in their isolated database.
import Ecto.Query

alias Tuist.Accounts
alias Tuist.ClickHouseRepo
alias Tuist.IngestRepo
alias Tuist.Projects.Project
alias Tuist.Repo
alias Tuist.Shards.ShardPlan
alias Tuist.Shards.ShardPlanModule
alias Tuist.Shards.ShardRun
alias Tuist.Tests

if Mix.env() != :dev, do: raise("Comparison sharding seeds are only supported in development")

{:ok, user} = Accounts.get_user_by_email("tuistrocks@tuist.dev")
account = Repo.preload(user, :account).account
now = NaiveDateTime.utc_now()

for {name, build_system, module_names, suite_names, case_name, scheme} <- [
      {"cargo-demo", "cargo", ["rust-store::lib", "rust-store::test/api", "rust-store::test/storage"],
       ["storage::index", "api::authentication", "storage::transactions"], "creates_record", "nextest"},
      {"xcode-demo", "xcode", ["StoreTests", "APITests", "TransactionsTests"],
       ["StoreTestsSuite", "APITestsSuite", "TransactionsTestsSuite"], "testCreatesRecord", "StoreApp"}
    ] do
  project = Repo.get_by!(Project, account_id: account.id, name: name)

  for day <- 6..0//-1 do
    ran_at = NaiveDateTime.add(now, -(day * 86_400 + 120), :second)
    shard_count = if rem(day, 3) == 0, do: 3, else: 2
    reference = "synthetic-comparison-shards-#{name}-#{day}"

    existing_plan =
      ClickHouseRepo.one(from(p in ShardPlan, where: p.project_id == ^project.id and p.reference == ^reference, limit: 1))

    plan =
      existing_plan ||
        IngestRepo.insert!(
          ShardPlan.create_changeset(%{
            id: UUIDv7.generate(),
            reference: reference,
            project_id: project.id,
            shard_count: shard_count,
            granularity: "module",
            inserted_at: ran_at
          })
        )

    modules =
      module_names
      |> Enum.with_index()
      |> Enum.map(fn {module_name, index} ->
        duration = Enum.at([4000, if(day == 5, do: 12_500, else: 7500), 3600], index) + day * 100
        failed = day == 2 and index == 1
        status = if failed, do: "failure", else: "success"
        suite = Enum.at(suite_names, index)

        %{
          name: module_name,
          status: status,
          duration: duration,
          test_cases: [
            %{
              name: case_name,
              test_suite_name: suite,
              status: status,
              duration: duration,
              failures:
                if(failed,
                  do: [
                    %{
                      message: "Synthetic sharded CI failure",
                      path: "synthetic-fixtures",
                      line_number: 1,
                      issue_type: "assertion_failure"
                    }
                  ],
                  else: []
                )
            }
          ],
          test_suites: [%{name: suite, status: status, duration: duration}],
          shard_index: rem(index, shard_count)
        }
      end)

    for module <- modules do
      exists =
        ClickHouseRepo.exists?(
          from(m in ShardPlanModule,
            where: m.project_id == ^project.id and m.shard_plan_id == ^plan.id and m.module_name == ^module.name
          )
        )

      if not exists do
        IngestRepo.insert_all(ShardPlanModule, [
          %{
            shard_plan_id: plan.id,
            project_id: project.id,
            shard_index: module.shard_index,
            module_name: module.name,
            estimated_duration_ms: module.duration,
            inserted_at: plan.inserted_at
          }
        ])
      end
    end

    for index <- 0..(shard_count - 1) do
      reported =
        ClickHouseRepo.exists?(
          from(r in ShardRun,
            where: r.project_id == ^project.id and r.shard_plan_id == ^plan.id and r.shard_index == ^index
          )
        )

      if not reported do
        assigned = modules |> Enum.filter(&(&1.shard_index == index)) |> Enum.map(&Map.delete(&1, :shard_index))
        status = if Enum.any?(assigned, &(&1.status == "failure")), do: "failure", else: "success"
        duration = 500 + Enum.sum(Enum.map(assigned, & &1.duration))

        {:ok, _} =
          Tests.create_test(%{
            id: UUIDv7.generate(),
            project_id: project.id,
            account_id: account.id,
            build_system: build_system,
            scheme: scheme,
            status: status,
            execution_mode: "parallel",
            is_ci: true,
            duration: duration,
            git_branch: "main",
            git_commit_sha: :sha |> :crypto.hash("synthetic-shards-#{day}") |> Base.encode16(case: :lower),
            ran_at: plan.inserted_at,
            shard_plan_id: plan.id,
            shard_index: index,
            test_modules: assigned
          })
      end
    end
  end

  for buffer <- [
        Tests.Test.Buffer,
        Tests.TestCase.Buffer,
        Tests.TestCaseRun.Buffer,
        Tests.TestModuleRun.Buffer,
        Tests.TestSuiteRun.Buffer,
        Tests.TestCaseFailure.Buffer,
        Tests.TestCaseEvent.Buffer
      ],
      do: buffer.flush()

  root = "#{Tuist.Environment.app_url(route_type: :app)}/#{account.name}/#{project.name}"
  IO.puts("#{name}: seven matched synthetic sharded runs, two/three shards, one failed run")
  IO.puts("Shards: #{root}/tests/shards")
end
