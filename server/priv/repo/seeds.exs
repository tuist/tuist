import Ecto.Query

alias Tuist.Accounts
alias Tuist.Alerts.Alert
alias Tuist.Alerts.AlertRule
alias Tuist.AppBuilds.AppBuild
alias Tuist.AppBuilds.Preview
alias Tuist.Billing
alias Tuist.Billing.Subscription
alias Tuist.Bundles
alias Tuist.CommandEvents.Event
alias Tuist.Environment
alias Tuist.IngestRepo
alias Tuist.Projects
alias Tuist.Projects.Project
alias Tuist.QA
alias Tuist.QA.Log
alias Tuist.QA.Run
alias Tuist.Repo
alias Tuist.Runs.Build
alias Tuist.Runs.Test
alias Tuist.Runs.TestCaseEvent
alias Tuist.Runs.TestCaseRun
alias Tuist.Runs.TestModuleRun
alias Tuist.Runs.TestSuiteRun
alias Tuist.Slack.Installation

# =============================================================================
# Configuration via Environment Variables
# =============================================================================
#
# This seed script supports configurable data volumes via environment variables.
# Use SEED_SCALE to quickly set production-like data volumes.
#
# Usage examples:
#   mix run priv/repo/seeds.exs                  # Default (small) - small dataset
#   SEED_SCALE=medium mix run priv/repo/seeds.exs    # Production-like volumes
#   SEED_SCALE=large mix run priv/repo/seeds.exs     # 2x production volumes
#
# Individual overrides (these override SEED_SCALE):
#   SEED_BUILD_RUNS=100000 mix run priv/repo/seeds.exs
#   SEED_TEST_RUNS=500000 mix run priv/repo/seeds.exs
#   SEED_COMMAND_EVENTS=6000000 mix run priv/repo/seeds.exs
#
# Environment variable reference:
#   SEED_SCALE              - Preset scale: "small" (default), "medium", "large"
#   SEED_BATCH_SIZE         - Batch size for inserts (default: 10000)
#   SEED_BUILD_RUNS         - Number of build runs
#   SEED_TEST_RUNS          - Number of test runs
#   SEED_COMMAND_EVENTS     - Number of command events
#   SEED_PREVIEWS           - Number of previews
#   SEED_BUNDLES            - Number of bundles
#   SEED_CAS_OPS_PER_BUILD  - CAS operations per build
#   SEED_FILES_PER_BUILD    - Build files to generate per build (for selected builds)
#   SEED_TARGETS_PER_BUILD  - Build targets per build
#   SEED_ISSUES_PER_BUILD   - Build issues per build (for failed builds)
#
# The "medium" and "large" presets are calibrated based on production data
# as of January 2026. These values should be periodically reviewed and updated
# as production data grows.
#
# =============================================================================

# Scale presets
seed_scale = System.get_env("SEED_SCALE", "small")

{default_build_runs, default_test_runs, default_command_events, default_previews, default_bundles,
 default_cas_ops_per_build, default_files_per_build, default_targets_per_build, default_issues_per_build,
 default_modules_per_test, default_suites_per_module, default_cases_per_suite, default_xcode_graphs,
 default_xcode_projects_per_graph, default_xcode_targets_per_project} =
  case seed_scale do
    "medium" ->
      # Production-like volumes (calibrated January 2026)
      # xcode: 500K graphs * 5 projects * 8 targets = 20M targets
      {100_000, 590_000, 1_000_000, 100, 50, 25, 500, 50, 30, 4, 5, 15, 500_000, 5, 8}

    "large" ->
      # 2x production volumes for staging/canary load testing (calibrated January 2026)
      # command_events: ~2M matches largest production project
      # xcode: 1M graphs * 5 projects * 8 targets = 40M targets
      {200_000, 1_200_000, 2_000_000, 200, 100, 25, 500, 50, 30, 4, 5, 15, 1_000_000, 5, 8}

    _ ->
      # Default small values (small dataset for fast local development)
      {2_000, 1_500, 8_000, 40, 20, 15, 0, 0, 0, 3, 4, 10, 100, 3, 5}
  end

# Allow individual overrides
# PostgreSQL has a limit of 65535 parameters per query, so batch size must be
# calculated as: 65535 / num_columns. With tables having up to 20 columns,
# a batch size of 3000 is safe for all PostgreSQL inserts.
# ClickHouse has no such limit and performs better with larger batches (50k-100k).
seed_config = %{
  pg_batch_size: String.to_integer(System.get_env("SEED_PG_BATCH_SIZE", "3000")),
  ch_batch_size: String.to_integer(System.get_env("SEED_CH_BATCH_SIZE", "50000")),
  build_runs: String.to_integer(System.get_env("SEED_BUILD_RUNS", "#{default_build_runs}")),
  test_runs: String.to_integer(System.get_env("SEED_TEST_RUNS", "#{default_test_runs}")),
  command_events: String.to_integer(System.get_env("SEED_COMMAND_EVENTS", "#{default_command_events}")),
  previews: String.to_integer(System.get_env("SEED_PREVIEWS", "#{default_previews}")),
  bundles: String.to_integer(System.get_env("SEED_BUNDLES", "#{default_bundles}")),
  cas_ops_per_build: String.to_integer(System.get_env("SEED_CAS_OPS_PER_BUILD", "#{default_cas_ops_per_build}")),
  files_per_build: String.to_integer(System.get_env("SEED_FILES_PER_BUILD", "#{default_files_per_build}")),
  targets_per_build: String.to_integer(System.get_env("SEED_TARGETS_PER_BUILD", "#{default_targets_per_build}")),
  issues_per_build: String.to_integer(System.get_env("SEED_ISSUES_PER_BUILD", "#{default_issues_per_build}")),
  modules_per_test: String.to_integer(System.get_env("SEED_MODULES_PER_TEST", "#{default_modules_per_test}")),
  suites_per_module: String.to_integer(System.get_env("SEED_SUITES_PER_MODULE", "#{default_suites_per_module}")),
  cases_per_suite: String.to_integer(System.get_env("SEED_CASES_PER_SUITE", "#{default_cases_per_suite}")),
  xcode_graphs: String.to_integer(System.get_env("SEED_XCODE_GRAPHS", "#{default_xcode_graphs}")),
  xcode_projects_per_graph:
    String.to_integer(System.get_env("SEED_XCODE_PROJECTS_PER_GRAPH", "#{default_xcode_projects_per_graph}")),
  xcode_targets_per_project:
    String.to_integer(System.get_env("SEED_XCODE_TARGETS_PER_PROJECT", "#{default_xcode_targets_per_project}"))
}

IO.puts("=== Seed Configuration (scale: #{seed_scale}) ===")
IO.puts("  build_runs: #{seed_config.build_runs}")
IO.puts("  test_runs: #{seed_config.test_runs}")
IO.puts("  command_events: #{seed_config.command_events}")
IO.puts("  xcode_graphs: #{seed_config.xcode_graphs}")
IO.puts("  xcode_projects: ~#{seed_config.xcode_graphs * seed_config.xcode_projects_per_graph}")

IO.puts(
  "  xcode_targets: ~#{seed_config.xcode_graphs * seed_config.xcode_projects_per_graph * seed_config.xcode_targets_per_project}"
)

IO.puts("  previews: #{seed_config.previews}")
IO.puts("  bundles: #{seed_config.bundles}")
IO.puts("  pg_batch_size: #{seed_config.pg_batch_size} (PostgreSQL)")
IO.puts("  ch_batch_size: #{seed_config.ch_batch_size} (ClickHouse)")
IO.puts("")

# Helper for progress logging during large inserts
defmodule SeedHelpers do
  # ClickHouse optimal batch size
  @moduledoc false
  @ch_batch_size 100_000
  # PostgreSQL safe batch size
  @pg_batch_size 3_000

  # For PostgreSQL: use batching due to 65535 parameter limit
  def insert_in_batches_pg(items, schema, repo, label \\ "") do
    total = length(items)
    IO.puts("Inserting #{total} #{label}...")

    items
    |> Enum.chunk_every(@pg_batch_size)
    |> Enum.with_index(1)
    |> Enum.each(fn {chunk, chunk_index} ->
      repo.insert_all(schema, chunk)
      progress = min(chunk_index * @pg_batch_size, total)
      IO.write("\r  Progress: #{progress}/#{total}")
    end)

    IO.puts("")
  end

  # For ClickHouse: streaming insert with large batches (100K)
  # Uses extended timeout to avoid connection timeout on large inserts
  def insert_bulk_ch(items, schema, repo, label \\ "") do
    total = length(items)
    IO.puts("Inserting #{total} #{label}...")

    items
    |> Stream.chunk_every(@ch_batch_size)
    |> Stream.with_index(1)
    |> Enum.each(fn {chunk, _idx} ->
      repo.insert_all(schema, chunk, timeout: 120_000)
    end)

    IO.puts("  Done.")
  end

  # Parallel flat_map using Task.async_stream for CPU-bound work
  def parallel_flat_map(enumerable, fun, opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online() * 2)
    ordered = Keyword.get(opts, :ordered, false)

    enumerable
    |> Task.async_stream(fun, max_concurrency: max_concurrency, ordered: ordered, timeout: :infinity)
    |> Enum.flat_map(fn {:ok, result} -> result end)
  end

  # Stream generation directly to DB - avoids holding all data in memory
  def stream_generate_insert(enumerable, generator_fn, schema, repo, label) do
    total_items = if is_list(enumerable), do: length(enumerable), else: Enum.count(enumerable)
    IO.puts("Generating and inserting #{label} (~#{total_items} source items)...")

    counter = :counters.new(1, [:atomics])
    max_concurrency = System.schedulers_online() * 2

    enumerable
    |> Task.async_stream(generator_fn, max_concurrency: max_concurrency, ordered: false, timeout: :infinity)
    |> Stream.flat_map(fn {:ok, result} -> result end)
    |> Stream.chunk_every(@ch_batch_size)
    |> Enum.each(fn chunk ->
      repo.insert_all(schema, chunk)
      :counters.add(counter, 1, length(chunk))
      IO.write("\r  Inserted: #{:counters.get(counter, 1)}")
    end)

    IO.puts("")
  end

  # Fast random string generation using :crypto
  def random_base64(length) do
    length
    |> :crypto.strong_rand_bytes()
    |> Base.encode64()
    |> binary_part(0, length)
  end

  def random_hex(length) do
    (length + 1)
    |> div(2)
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
    |> binary_part(0, length)
  end
end

# Stubs
email = "tuistrocks@tuist.dev"
password = "tuistrocks"

FunWithFlags.enable(:qa)

_account =
  case Accounts.get_user_by_email(email) do
    {:error, :not_found} ->
      {:ok, account} =
        Accounts.create_user(email,
          password: password,
          confirmed_at: NaiveDateTime.utc_now(),
          setup_billing: false,
          customer_id: "cus_RFlTyvSVonyndv"
        )

      %Subscription{}
      |> Subscription.create_changeset(%{
        plan: :pro,
        subscription_id: "sub_1QNEs2LWue9IBlPSsKtuPQ5L",
        status: "active",
        account_id: account.id,
        default_payment_method: "pmc_1QNBBVLWue9IBlPSH2tnx4hH"
      })
      |> Repo.insert!()

      account

    {:ok, user} ->
      user
  end

{:ok, user} = Accounts.get_user_by_email(email)

organization =
  if Accounts.get_organization_by_handle("tuist") do
    Accounts.get_organization_by_handle("tuist")
  else
    {:ok, organization} =
      Accounts.create_organization(%{name: "tuist", creator: user}, setup_billing: false)

    organization
  end

# Create additional organization member
member_email = "member@tuist.dev"

_member_user =
  case Accounts.get_user_by_email(member_email) do
    {:error, :not_found} ->
      {:ok, member} =
        Accounts.create_user(member_email,
          password: password,
          confirmed_at: NaiveDateTime.utc_now(),
          setup_billing: false
        )

      # Add member to the organization
      :ok = Accounts.add_user_to_organization(member, organization)

      member

    {:ok, member} ->
      member
  end

Accounts.update_okta_configuration(organization.id, %{
  okta_client_id: System.get_env("TUIST_OKTA_1_CLIENT_ID"),
  okta_client_secret: System.get_env("TUIST_OKTA_1_CLIENT_SECRET"),
  sso_provider: :okta,
  sso_organization_id: "trial-2983119.okta.com"
})

_public_project =
  case Projects.get_project_by_slug("tuist/public") do
    {:ok, %Project{} = project} ->
      project

    {:error, _} ->
      Projects.create_project(%{name: "public", account: %{id: organization.account.id}},
        visibility: :public
      )
  end

_ios_app_with_frameworks_project =
  case Projects.get_project_by_slug("tuist/ios_app_with_frameworks") do
    {:ok, project} ->
      project

    {:error, _} ->
      Projects.create_project!(%{
        name: "ios_app_with_frameworks",
        account: %{id: organization.account.id}
      })
  end

tuist_project =
  case Projects.get_project_by_slug("tuist/tuist") do
    {:ok, project} ->
      project

    {:error, _} ->
      Projects.create_project!(
        %{
          name: "tuist",
          account: %{id: organization.account.id}
        },
        vcs_repository_full_handle: "tuist/tuist",
        vcs_provider: :github
      )
  end

if is_nil(Repo.get_by(QA.LaunchArgumentGroup, project_id: tuist_project.id, name: "login-credentials")) do
  %QA.LaunchArgumentGroup{}
  |> QA.LaunchArgumentGroup.create_changeset(%{
    project_id: tuist_project.id,
    name: "login-credentials",
    value: "--email tuistrocks@tuist.dev --password tuistrocks",
    description: "Log in credentials that can be used to skip the login"
  })
  |> Repo.insert!()
end

IO.puts("Generating #{seed_config.build_runs} build runs in parallel...")

org_account_id = organization.account.id
user_account_id = user.account.id
project_id = tuist_project.id

build_generator = fn _i ->
  status = Enum.random([:success, :failure])
  is_ci = Enum.random([true, false])
  total_tasks = Enum.random(50..200)
  remote_hits = Enum.random(0..div(total_tasks, 2))
  local_hits = Enum.random(0..(total_tasks - remote_hits))

  %{
    id: UUIDv7.generate(),
    duration: Enum.random(10_000..100_000),
    macos_version: Enum.random(["11.2.3", "12.3.4", "13.4.5", "14.0", "14.5"]),
    xcode_version: Enum.random(["12.4", "13.0", "13.2", "14.0", "15.0", "15.2"]),
    is_ci: is_ci,
    model_identifier: Enum.random(["MacBookPro14,2", "MacBookPro15,1", "MacBookPro10,2", "Macmini8,1", "Mac14,6"]),
    project_id: project_id,
    account_id: if(is_ci, do: org_account_id, else: user_account_id),
    scheme: Enum.random(["App", "AppTests"]),
    configuration: Enum.random(["Debug", "Release"]),
    inserted_at:
      DateTime.new!(
        Date.add(DateTime.utc_now(), -Enum.random(0..400)),
        Time.new!(Enum.random(0..23), Enum.random(0..59), Enum.random(0..59))
      ),
    status: status,
    cacheable_tasks_count: total_tasks,
    cacheable_task_remote_hits_count: remote_hits,
    cacheable_task_local_hits_count: local_hits
  }
end

builds = SeedHelpers.parallel_flat_map(1..seed_config.build_runs, fn i -> [build_generator.(i)] end)

# Insert builds in batches for large volumes
build_records =
  builds
  |> Enum.chunk_every(seed_config.pg_batch_size)
  |> Enum.flat_map(fn chunk ->
    {_count, records} = Repo.insert_all(Build, chunk, returning: [:id])
    records
  end)

generate_cache_key = fn _build_id, _task_type, _index ->
  "0~#{SeedHelpers.random_base64(88)}"
end

generate_task_description = fn task_type ->
  swift_files = [
    "ContentView.swift",
    "AppDelegate.swift",
    "ViewModel.swift",
    "MainView.swift",
    "NetworkManager.swift",
    "DataModel.swift",
    "HomeViewController.swift",
    "SettingsView.swift",
    "ProfileViewModel.swift",
    "AuthenticationService.swift"
  ]

  clang_files = [
    "main.m",
    "NetworkManager.m",
    "Utils.c",
    "DataProcessor.mm",
    "ImageHelper.m",
    "CacheManager.m",
    "Analytics.m",
    "Bridge.mm"
  ]

  swift_actions = [
    "Compiling",
    "Emitting module for"
  ]

  _clang_actions = [
    "Compiling"
  ]

  case task_type do
    "swift" ->
      action = Enum.random(swift_actions)
      file = Enum.random(swift_files)
      if action == "Emitting module for", do: String.replace(file, ".swift", ""), else: file
      "#{action} #{if action == "Emitting module for", do: String.replace(file, ".swift", ""), else: file}"

    "clang" ->
      "Compiling #{Enum.random(clang_files)}"
  end
end

generate_cas_node_id = fn -> SeedHelpers.random_base64(64) end
generate_checksum = fn -> SeedHelpers.random_hex(64) end

cas_file_types = [
  "object",
  "swiftmodule",
  "swiftdoc",
  "dependencies",
  "swift-dependencies",
  "swiftinterface",
  "llvm-bc",
  "diagnostics"
]

IO.puts("Generating CAS outputs (#{seed_config.cas_ops_per_build} per build) in parallel...")

cas_output_generator = fn build ->
  operation_count =
    if seed_config.cas_ops_per_build > 0 do
      max(5, Enum.random(div(seed_config.cas_ops_per_build, 2)..seed_config.cas_ops_per_build))
    else
      Enum.random(5..25)
    end

  inserted_at = DateTime.to_naive(build.inserted_at)

  Enum.map(1..operation_count, fn _i ->
    operation = Enum.random(["download", "upload"])
    size = Enum.random(1024..50_000_000)
    compressed_size = trunc(size * (0.3 + :rand.uniform() * 0.6))

    %{
      build_run_id: build.id,
      node_id: generate_cas_node_id.(),
      checksum: generate_checksum.(),
      size: size,
      duration: Enum.random(100..30_000),
      compressed_size: compressed_size,
      operation: operation,
      type: Enum.random(cas_file_types),
      inserted_at: inserted_at
    }
  end)
end

cas_outputs = SeedHelpers.parallel_flat_map(builds, cas_output_generator)
SeedHelpers.insert_bulk_ch(cas_outputs, Tuist.Runs.CASOutput, IngestRepo, "CAS outputs")

# Generate CAS events based on CAS outputs
# CAS events track upload/download actions for analytics
IO.puts("Generating CAS events...")

cas_events =
  Enum.map(cas_outputs, fn cas_output ->
    # Use the operation from CAS output (upload or download) as the action
    action = cas_output.operation

    %{
      id: UUIDv7.generate(),
      action: action,
      size: cas_output.size,
      cas_id: cas_output.node_id,
      project_id: tuist_project.id,
      inserted_at: cas_output.inserted_at
    }
  end)

SeedHelpers.insert_bulk_ch(cas_events, Tuist.Cache.CASEvent, IngestRepo, "CAS events")

# Group CAS outputs by build_id for later use
cas_outputs_by_build = Enum.group_by(cas_outputs, & &1.build_run_id)

# Create a map of build_id -> build for O(1) lookups
builds_by_id = Map.new(builds, fn b -> {b.id, b} end)

# For cacheable tasks, use a proportion of builds based on scale
cacheable_tasks_build_count = min(length(build_records), max(500, div(seed_config.build_runs, 4)))
IO.puts("Generating cacheable tasks for #{cacheable_tasks_build_count} builds...")

cacheable_tasks =
  build_records
  |> Enum.map(& &1.id)
  |> Enum.shuffle()
  |> Enum.take(cacheable_tasks_build_count)
  |> Enum.flat_map(fn build_id ->
    build = Map.fetch!(builds_by_id, build_id)
    total_tasks = build.cacheable_tasks_count
    remote_hits = build.cacheable_task_remote_hits_count
    local_hits = build.cacheable_task_local_hits_count
    misses = total_tasks - remote_hits - local_hits

    # Get CAS output node_ids for this build
    cas_node_ids =
      cas_outputs_by_build
      |> Map.get(build_id, [])
      |> Enum.map(& &1.node_id)

    tasks = []

    tasks =
      if remote_hits > 0 do
        tasks ++
          Enum.map(1..remote_hits, fn i ->
            task_type = Enum.random(["clang", "swift"])
            # Randomly select 0-5 CAS output node_ids for this task
            selected_node_ids = Enum.take_random(cas_node_ids, Enum.random(0..min(5, length(cas_node_ids))))

            %{
              build_run_id: build_id,
              type: task_type,
              status: "hit_remote",
              key: generate_cache_key.(build_id, "remote", i),
              read_duration: Enum.random(100..2000) * 1.0,
              write_duration: nil,
              description: generate_task_description.(task_type),
              cas_output_node_ids: selected_node_ids,
              inserted_at: DateTime.to_naive(build.inserted_at)
            }
          end)
      else
        tasks
      end

    tasks =
      if local_hits > 0 do
        tasks ++
          Enum.map(1..local_hits, fn i ->
            task_type = Enum.random(["clang", "swift"])
            # Randomly select 0-5 CAS output node_ids for this task
            selected_node_ids = Enum.take_random(cas_node_ids, Enum.random(0..min(5, length(cas_node_ids))))

            %{
              build_run_id: build_id,
              type: task_type,
              status: "hit_local",
              key: generate_cache_key.(build_id, "local", i),
              read_duration: Enum.random(10..100) * 1.0,
              write_duration: nil,
              description: generate_task_description.(task_type),
              cas_output_node_ids: selected_node_ids,
              inserted_at: DateTime.to_naive(build.inserted_at)
            }
          end)
      else
        tasks
      end

    tasks =
      if misses > 0 do
        tasks ++
          Enum.map(1..misses, fn i ->
            task_type = Enum.random(["clang", "swift"])
            # Randomly select 0-5 CAS output node_ids for this task
            selected_node_ids = Enum.take_random(cas_node_ids, Enum.random(0..min(5, length(cas_node_ids))))

            %{
              build_run_id: build_id,
              type: task_type,
              status: "miss",
              key: generate_cache_key.(build_id, "miss", i),
              read_duration: Enum.random(50..500) * 1.0,
              write_duration: Enum.random(100..2000) * 1.0,
              description: generate_task_description.(task_type),
              cas_output_node_ids: selected_node_ids,
              inserted_at: DateTime.to_naive(build.inserted_at)
            }
          end)
      else
        tasks
      end

    tasks
  end)

SeedHelpers.insert_bulk_ch(cacheable_tasks, Tuist.Runs.CacheableTask, IngestRepo, "cacheable tasks")

branches = [
  "main",
  "develop",
  "feature/wearables",
  "feature/new-ui",
  "bugfix/crash-fix",
  "release/v2.0",
  "hotfix/security"
]

module_names = [
  "AppTests",
  "FrameworkTests",
  "UITests",
  "IntegrationTests",
  "UnitTests",
  "PerformanceTests",
  "SecurityTests",
  "APITests"
]

suite_names = [
  "LoginTests",
  "NavigationTests",
  "DataModelTests",
  "NetworkTests",
  "ViewModelTests",
  "ServiceTests",
  "UtilityTests",
  "CacheTests"
]

test_case_names = [
  "testUserLogin",
  "testUserLogout",
  "testNavigationFlow",
  "testDataValidation",
  "testNetworkRequest",
  "testCacheHit",
  "testErrorHandling",
  "testUIRendering",
  "testPerformance",
  "testSecurity"
]

failure_messages = [
  ~s{XCTAssertEqual failed: ("expected") is not equal to ("actual")},
  "XCTAssertTrue failed",
  "XCTAssertNotNil failed",
  "Asynchronous wait failed: Exceeded timeout of 10 seconds",
  "Threw error: NetworkError.timeout",
  "XCTAssertFalse failed - Condition was unexpectedly true",
  "Failed to unwrap Optional value",
  "XCTAssertGreaterThan failed: (0) is not greater than (0)"
]

paths = [
  "AppTests/LoginTests.swift",
  "AppTests/NavigationTests.swift",
  "FrameworkTests/DataModelTests.swift",
  "UITests/ViewTests.swift",
  "IntegrationTests/APITests.swift",
  "UnitTests/ServiceTests.swift"
]

# Create test cases first with all unique combinations of (module_name, suite_name, test_case_name)
test_case_definitions =
  for module_name <- module_names,
      suite_name <- suite_names,
      test_case_name <- test_case_names do
    # ~20% of test cases are marked as flaky (and also quarantined)
    is_flaky = Enum.random([false, false, false, false, true])

    %{
      name: test_case_name,
      module_name: module_name,
      suite_name: suite_name,
      status: Enum.random(["success", "failure", "skipped"]),
      is_flaky: is_flaky,
      is_quarantined: is_flaky,
      duration: Enum.random(10..500),
      ran_at: NaiveDateTime.utc_now()
    }
  end

{test_case_id_map, _test_cases_with_flaky_run} = Tuist.Runs.create_test_cases(tuist_project.id, test_case_definitions)

# Update flaky test cases to be marked as is_flaky
# ~70% stay quarantined, ~30% get unquarantined (to show chart going down)
# (create_test_cases doesn't set these from input, so we insert updated rows)
flaky_test_case_defs =
  test_case_definitions
  |> Enum.filter(& &1.is_flaky)
  |> Enum.map(fn def ->
    id = test_case_id_map[{def.name, def.module_name, def.suite_name}]
    # ~30% will be unquarantined
    is_quarantined = Enum.random(1..10) > 3
    {def, id, is_quarantined}
  end)
  |> Enum.reject(fn {_def, id, _is_quarantined} -> is_nil(id) end)

flaky_test_case_updates =
  Enum.map(flaky_test_case_defs, fn {def, id, is_quarantined} ->
    now = NaiveDateTime.utc_now()

    %{
      id: id,
      name: def.name,
      module_name: def.module_name,
      suite_name: def.suite_name,
      project_id: project_id,
      last_status: def.status,
      last_duration: def.duration,
      last_ran_at: def.ran_at,
      is_flaky: true,
      is_quarantined: is_quarantined,
      inserted_at: now,
      recent_durations: [def.duration],
      avg_duration: def.duration
    }
  end)

# Track which test cases are quarantined vs unquarantined for event generation
{quarantined_ids, unquarantined_ids} =
  flaky_test_case_defs
  |> Enum.split_with(fn {_def, _id, is_quarantined} -> is_quarantined end)
  |> then(fn {quarantined, unquarantined} ->
    {Enum.map(quarantined, fn {_def, id, _} -> id end), Enum.map(unquarantined, fn {_def, id, _} -> id end)}
  end)

quarantined_test_cases =
  if length(flaky_test_case_updates) > 0 do
    IngestRepo.insert_all(Tuist.Runs.TestCase, flaky_test_case_updates, timeout: 120_000)

    IO.puts(
      "Updated #{length(flaky_test_case_updates)} test cases as flaky (#{length(quarantined_ids)} quarantined, #{length(unquarantined_ids)} unquarantined)"
    )

    # Keep track of quarantined test cases for ensuring they get test runs
    flaky_test_case_updates
    |> Enum.filter(& &1.is_quarantined)
    |> Enum.map(fn tc ->
      %{id: tc.id, name: tc.name, module_name: tc.module_name, suite_name: tc.suite_name}
    end)
  else
    []
  end

# Convert to a list of test cases grouped by module/suite for fast lookup
_test_cases_by_module_suite =
  test_case_id_map
  |> Enum.map(fn {{name, module_name, suite_name}, id} ->
    %{id: id, name: name, module_name: module_name, suite_name: suite_name}
  end)
  |> Enum.group_by(fn tc -> {tc.module_name, tc.suite_name} end)

all_test_cases =
  Enum.map(test_case_id_map, fn {{name, module_name, suite_name}, id} ->
    %{id: id, name: name, module_name: module_name, suite_name: suite_name}
  end)

# Process test runs in PARALLEL chunks - optimized for memory efficiency and CH throughput
# Key insight: generate in parallel, but serialize CH inserts to avoid connection contention
# Larger chunks for better throughput
chunk_size = 20_000
total_test_runs = seed_config.test_runs
# Only 2% of tests get detailed hierarchy (still ~24K detailed tests for large)
selected_test_ratio = 0.02
# Process detailed tests in batches
detail_batch_size = 100
num_chunks = div(total_test_runs, chunk_size) + 1

IO.puts("Generating #{total_test_runs} test runs in #{num_chunks} chunks (CH inserts serialized)...")
IO.puts("  - Detailed tests: ~#{trunc(total_test_runs * selected_test_ratio)} (#{trunc(selected_test_ratio * 100)}%)")

test_run_counter = :counters.new(1, [:atomics])
module_run_counter = :counters.new(1, [:atomics])
suite_run_counter = :counters.new(1, [:atomics])
case_run_counter = :counters.new(1, [:atomics])
failure_counter = :counters.new(1, [:atomics])

# Pre-compute all static data
all_test_cases_list = Enum.to_list(all_test_cases)
quarantined_test_cases_list = Enum.to_list(quarantined_test_cases)

# Chunk generator function - processes one chunk and inserts to DB immediately
chunk_processor = fn chunk_indices ->
  chunk_count = length(chunk_indices)
  detail_count = trunc(chunk_count * selected_test_ratio)

  # Generate and insert test runs IMMEDIATELY
  tests_chunk =
    Enum.map(chunk_indices, fn _i ->
      status = Enum.random(["success", "failure"])
      is_ci = Enum.random([true, false])
      git_branch = Enum.random(branches)
      base_date = DateTime.utc_now()
      day_offset = Enum.random(0..400)
      ran_at = base_date |> Date.add(-day_offset) |> DateTime.new!(~T[12:00:00.000000]) |> DateTime.to_naive()

      %{
        id: UUIDv7.generate(),
        duration: Enum.random(5_000..60_000),
        macos_version: Enum.random(["11.2.3", "12.3.4", "13.4.5"]),
        xcode_version: Enum.random(["12.4", "13.0", "13.2"]),
        is_ci: is_ci,
        # ~20% flaky
        is_flaky: Enum.random([false, false, false, false, true]),
        model_identifier: Enum.random(["MacBookPro14,2", "MacBookPro15,1", "MacBookPro10,2", "Macmini8,1"]),
        scheme: Enum.random(["AppTests", "FrameworkTests", "UITests"]),
        status: status,
        git_branch: git_branch,
        git_commit_sha: Enum.random(["a1b2c3d4e5f6", "f6e5d4c3b2a1", "123456789abc", "abcdef123456"]),
        git_ref: "refs/heads/#{git_branch}",
        ran_at: ran_at,
        project_id: project_id,
        account_id: if(is_ci, do: org_account_id, else: user_account_id),
        inserted_at: ran_at,
        ci_run_id: if(is_ci, do: "#{Enum.random(19_000_000_000..20_000_000_000)}", else: ""),
        ci_project_handle: if(is_ci, do: "tuist/tuist", else: ""),
        ci_host: "",
        ci_provider: if(is_ci, do: "github")
      }
    end)

  # Insert test runs immediately with extended timeout
  IngestRepo.insert_all(Test, tests_chunk, timeout: 120_000)
  :counters.add(test_run_counter, 1, length(tests_chunk))

  # Select tests for detailed hierarchy
  selected_tests = Enum.take_random(tests_chunk, detail_count)

  # Process detailed tests in small batches to limit memory
  selected_tests
  |> Enum.chunk_every(detail_batch_size)
  |> Enum.each(fn test_batch ->
    # Generate and accumulate data for this small batch
    {module_runs, suite_runs, case_runs, failures} =
      Enum.reduce(test_batch, {[], [], [], []}, fn test, {mods, suites, cases, fails} ->
        # Reduced from 3..5
        module_count = Enum.random(2..3)

        {batch_mods, batch_suites, batch_cases, batch_fails} =
          Enum.reduce(1..module_count, {[], [], [], []}, fn _, {m_acc, s_acc, c_acc, f_acc} ->
            module_name = Enum.random(module_names)
            module_status = if test.status == "success", do: 0, else: Enum.random([0, 0, 1])
            # Reduced from 4..6
            suite_count = Enum.random(2..4)
            module_id = UUIDv7.generate()

            module_run = %{
              id: module_id,
              name: module_name,
              test_run_id: test.id,
              status: module_status,
              is_flaky: Enum.random([false, false, false, true]),
              duration: Enum.random(1_000..10_000),
              test_suite_count: suite_count,
              test_case_count: suite_count * 8,
              avg_test_case_duration: 50,
              inserted_at: test.inserted_at
            }

            {suite_list, case_list, fail_list} =
              Enum.reduce(1..suite_count, {[], [], []}, fn _, {sl, cl, fl} ->
                suite_name = Enum.random(suite_names)
                suite_status = if module_status == 0, do: Enum.random([0, 0, 0, 0, 2]), else: Enum.random([0, 0, 1, 2])
                # Reduced from 12..18
                case_count = Enum.random(5..10)
                suite_id = UUIDv7.generate()

                suite_run = %{
                  id: suite_id,
                  name: suite_name,
                  test_run_id: test.id,
                  test_module_run_id: module_id,
                  status: suite_status,
                  is_flaky: Enum.random([false, false, false, true]),
                  duration: Enum.random(500..5000),
                  test_case_count: case_count,
                  avg_test_case_duration: 30,
                  inserted_at: test.inserted_at
                }

                {case_list_inner, fail_list_inner} =
                  Enum.reduce(1..case_count, {[], []}, fn _, {cl_inner, fl_inner} ->
                    # Ensure quarantined test cases get test_case_runs (10% chance to pick from quarantined)
                    # This ensures they have last_run_id populated for proper link rendering
                    test_case =
                      if length(quarantined_test_cases_list) > 0 and Enum.random(1..10) == 1 do
                        Enum.random(quarantined_test_cases_list)
                      else
                        Enum.random(all_test_cases_list)
                      end

                    case_status =
                      if suite_status == 0,
                        do: Enum.random([0, 0, 0, 0, 0, 0, 0, 0, 1, 2]),
                        else: Enum.random([0, 0, 1, 2])

                    case_run = %{
                      id: UUIDv7.generate(),
                      name: test_case.name,
                      test_run_id: test.id,
                      test_module_run_id: module_id,
                      test_suite_run_id: suite_id,
                      test_case_id: test_case.id,
                      project_id: test.project_id,
                      is_ci: test.is_ci,
                      scheme: test.scheme,
                      account_id: test.account_id,
                      ran_at: test.ran_at,
                      git_branch: test.git_branch,
                      git_commit_sha: test.git_commit_sha,
                      status: case_status,
                      is_flaky: Enum.random([false, false, false, false, true]),
                      is_new: Enum.random([false, false, false, false, false, true]),
                      duration: Enum.random(10..200),
                      module_name: test_case.module_name,
                      suite_name: test_case.suite_name,
                      inserted_at: test.inserted_at
                    }

                    fail =
                      if case_status == 1 do
                        [
                          %{
                            id: UUIDv7.generate(),
                            test_case_run_id: case_run.id,
                            message: Enum.random(failure_messages),
                            path: Enum.random(paths),
                            line_number: Enum.random(10..500),
                            issue_type: Enum.random(["error_thrown", "assertion_failure"]),
                            inserted_at: test.inserted_at
                          }
                        ]
                      else
                        []
                      end

                    {[case_run | cl_inner], fail ++ fl_inner}
                  end)

                {[suite_run | sl], case_list_inner ++ cl, fail_list_inner ++ fl}
              end)

            {[module_run | m_acc], suite_list ++ s_acc, case_list ++ c_acc, fail_list ++ f_acc}
          end)

        {batch_mods ++ mods, batch_suites ++ suites, batch_cases ++ cases, batch_fails ++ fails}
      end)

    # Insert this batch's data with extended timeout to avoid CH connection timeout
    if length(module_runs) > 0 do
      IngestRepo.insert_all(TestModuleRun, module_runs, timeout: 120_000)
      :counters.add(module_run_counter, 1, length(module_runs))
    end

    if length(suite_runs) > 0 do
      IngestRepo.insert_all(TestSuiteRun, suite_runs, timeout: 120_000)
      :counters.add(suite_run_counter, 1, length(suite_runs))
    end

    if length(case_runs) > 0 do
      IngestRepo.insert_all(TestCaseRun, case_runs, timeout: 120_000)
      :counters.add(case_run_counter, 1, length(case_runs))
    end

    if length(failures) > 0 do
      IngestRepo.insert_all(Tuist.Runs.TestCaseFailure, failures, timeout: 120_000)
      :counters.add(failure_counter, 1, length(failures))
    end
  end)

  :ok
end

# Process all chunks in PARALLEL with higher concurrency for faster throughput
1..total_test_runs
|> Enum.chunk_every(chunk_size)
|> Task.async_stream(chunk_processor, max_concurrency: 8, timeout: :infinity, ordered: false)
|> Enum.each(fn {:ok, _} ->
  IO.write(
    "\r  Progress: tests=#{:counters.get(test_run_counter, 1)}, modules=#{:counters.get(module_run_counter, 1)}, suites=#{:counters.get(suite_run_counter, 1)}, cases=#{:counters.get(case_run_counter, 1)}"
  )
end)

IO.puts("")
IO.puts("Test data generation complete:")
IO.puts("  - Test runs: #{:counters.get(test_run_counter, 1)}")
IO.puts("  - Module runs: #{:counters.get(module_run_counter, 1)}")
IO.puts("  - Suite runs: #{:counters.get(suite_run_counter, 1)}")
IO.puts("  - Case runs: #{:counters.get(case_run_counter, 1)}")
IO.puts("  - Failures: #{:counters.get(failure_counter, 1)}")

# =============================================================================
# Ensure all quarantined test cases have at least one test case run
# =============================================================================
#
# Quarantined test cases need associated runs for proper link rendering.
# Create explicit runs for each quarantined test case to guarantee this.

IO.puts("Ensuring all quarantined test cases have runs...")

if length(quarantined_test_cases) > 0 do
  # Create a test run to associate with quarantined test case runs
  quarantine_test_run_id = UUIDv7.generate()
  ran_at = DateTime.utc_now() |> DateTime.add(-1, :day) |> DateTime.to_naive()

  quarantine_test_run = %{
    id: quarantine_test_run_id,
    duration: 30_000,
    macos_version: "14.0",
    xcode_version: "15.0",
    is_ci: true,
    is_flaky: true,
    model_identifier: "MacBookPro14,2",
    scheme: "AppTests",
    status: "success",
    git_branch: "main",
    git_commit_sha: "abc123def456",
    git_ref: "refs/heads/main",
    ran_at: ran_at,
    project_id: project_id,
    account_id: org_account_id,
    inserted_at: ran_at,
    ci_run_id: "19500000000",
    ci_project_handle: "tuist/tuist",
    ci_host: "",
    ci_provider: "github"
  }

  IngestRepo.insert_all(Test, [quarantine_test_run], timeout: 120_000)

  # Create module and suite runs for the quarantined test cases
  quarantine_module_id = UUIDv7.generate()
  quarantine_suite_id = UUIDv7.generate()

  quarantine_module_run = %{
    id: quarantine_module_id,
    name: "QuarantinedTests",
    test_run_id: quarantine_test_run_id,
    status: 0,
    is_flaky: true,
    duration: 5_000,
    test_suite_count: 1,
    test_case_count: length(quarantined_test_cases),
    avg_test_case_duration: 50,
    inserted_at: ran_at
  }

  quarantine_suite_run = %{
    id: quarantine_suite_id,
    name: "QuarantinedSuite",
    test_run_id: quarantine_test_run_id,
    test_module_run_id: quarantine_module_id,
    status: 0,
    is_flaky: true,
    duration: 3_000,
    test_case_count: length(quarantined_test_cases),
    avg_test_case_duration: 30,
    inserted_at: ran_at
  }

  IngestRepo.insert_all(TestModuleRun, [quarantine_module_run], timeout: 120_000)
  IngestRepo.insert_all(TestSuiteRun, [quarantine_suite_run], timeout: 120_000)

  # Create a test case run for each quarantined test case
  quarantined_case_runs =
    Enum.map(quarantined_test_cases, fn tc ->
      %{
        id: UUIDv7.generate(),
        name: tc.name,
        test_run_id: quarantine_test_run_id,
        test_module_run_id: quarantine_module_id,
        test_suite_run_id: quarantine_suite_id,
        test_case_id: tc.id,
        project_id: project_id,
        is_ci: true,
        scheme: "AppTests",
        account_id: org_account_id,
        ran_at: ran_at,
        git_branch: "main",
        git_commit_sha: "abc123def456",
        status: 0,
        is_flaky: true,
        is_new: false,
        duration: Enum.random(10..200),
        module_name: tc.module_name,
        suite_name: tc.suite_name,
        inserted_at: ran_at
      }
    end)

  IngestRepo.insert_all(TestCaseRun, quarantined_case_runs, timeout: 120_000)
  IO.puts("  - Created #{length(quarantined_case_runs)} runs for quarantined test cases")
end

# =============================================================================
# Test Case Events (Quarantine History)
# =============================================================================
#
# Create historical quarantine/unquarantine events for test cases to populate
# the quarantined tests analytics chart. Events match the final quarantine state.

IO.puts("Generating test case events for quarantine history...")

# Generate events for quarantined test cases (odd number of events, ending with "quarantined")
quarantined_events =
  Enum.flat_map(quarantined_ids, fn test_case_id ->
    # Odd number of events so it ends with "quarantined"
    num_events = Enum.random([1, 3, 5, 7])
    base_date = DateTime.utc_now()

    event_timestamps =
      1..num_events
      |> Enum.map(fn _ -> Enum.random(1..400) end)
      |> Enum.sort(:desc)
      |> Enum.map(fn day_offset ->
        base_date |> DateTime.add(-day_offset, :day) |> DateTime.to_naive()
      end)

    event_timestamps
    |> Enum.with_index()
    |> Enum.map(fn {inserted_at, index} ->
      event_type = if rem(index, 2) == 0, do: "quarantined", else: "unquarantined"
      actor_id = if Enum.random(1..10) <= 7, do: nil, else: user_account_id

      %{
        id: UUIDv7.generate(),
        test_case_id: test_case_id,
        event_type: event_type,
        actor_id: actor_id,
        inserted_at: inserted_at
      }
    end)
  end)

# Generate events for unquarantined test cases (even number of events, ending with "unquarantined")
unquarantined_events =
  Enum.flat_map(unquarantined_ids, fn test_case_id ->
    # Even number of events so it ends with "unquarantined"
    num_events = Enum.random([2, 4, 6])
    base_date = DateTime.utc_now()

    event_timestamps =
      1..num_events
      |> Enum.map(fn _ -> Enum.random(1..400) end)
      |> Enum.sort(:desc)
      |> Enum.map(fn day_offset ->
        base_date |> DateTime.add(-day_offset, :day) |> DateTime.to_naive()
      end)

    event_timestamps
    |> Enum.with_index()
    |> Enum.map(fn {inserted_at, index} ->
      event_type = if rem(index, 2) == 0, do: "quarantined", else: "unquarantined"
      actor_id = if Enum.random(1..10) <= 7, do: nil, else: user_account_id

      %{
        id: UUIDv7.generate(),
        test_case_id: test_case_id,
        event_type: event_type,
        actor_id: actor_id,
        inserted_at: inserted_at
      }
    end)
  end)

test_case_events = quarantined_events ++ unquarantined_events

# Insert test case events
if length(test_case_events) > 0 do
  IngestRepo.insert_all(TestCaseEvent, test_case_events, timeout: 120_000)
end

IO.puts("  - Test case events: #{length(test_case_events)}")
IO.puts("  - Currently quarantined: #{length(quarantined_ids)}, unquarantined: #{length(unquarantined_ids)}")

IO.puts("Generating #{seed_config.command_events} command events in parallel...")

# Pre-compute static data outside the generator
cacheable_targets_static = [
  "TargetOne",
  "TargetTwo",
  "TargetThree",
  "TargetFour",
  "TargetFive",
  "TargetSix",
  "TargetSeven",
  "TargetEight",
  "TargetNine",
  "TargetTen",
  "TargetEleven",
  "TargetTwelve",
  "TargetThirteen",
  "TargetFourteen",
  "TargetFifteen"
]

test_targets_static = [
  "TestTargetOne",
  "TestTargetTwo",
  "TestTargetThree",
  "TestTargetFour",
  "TestTargetFive",
  "TestTargetSix",
  "TestTargetSeven",
  "TestTargetEight",
  "TestTargetNine",
  "TestTargetTen",
  "TestTargetEleven",
  "TestTargetTwelve",
  "TestTargetThirteen",
  "TestTargetFourteen",
  "TestTargetFifteen"
]

base_date = DateTime.utc_now()
cmd_project_id = tuist_project.id
cmd_user_id = user.id

event_counter = :counters.new(1, [:atomics])
generate_event_counter = :counters.new(1, [:atomics])

# Stream and insert command events in parallel chunks
# Use larger chunks (100K) and higher concurrency for faster throughput
cmd_chunk_size = 100_000

# Process command events sequentially to avoid overwhelming ClickHouse connections
# Using Stream.chunk_every for memory efficiency
1..seed_config.command_events
|> Stream.chunk_every(cmd_chunk_size)
|> Enum.each(fn chunk_indices ->
  events =
    Enum.map(chunk_indices, fn _i ->
      name = Enum.random(["test", "cache", "generate"])
      status = Enum.random([0, 1])
      is_ci = Enum.random([true, false])

      remote_count = Enum.random(0..14)
      local_count = Enum.random(0..(14 - remote_count))
      remote_cache_hits = Enum.take(cacheable_targets_static, remote_count)
      local_cache_hits = cacheable_targets_static |> Enum.reverse() |> Enum.take(local_count)

      {test_targets, remote_test_hits, local_test_hits} =
        if name == "test" do
          r = Enum.random(0..14)
          l = Enum.random(0..(14 - r))
          {test_targets_static, Enum.take(test_targets_static, r), test_targets_static |> Enum.reverse() |> Enum.take(l)}
        else
          {[], [], []}
        end

      day_offset = Enum.random(0..400)
      created_at = base_date |> Date.add(-day_offset) |> DateTime.new!(~T[12:00:00.000000]) |> DateTime.to_naive()

      %{
        id: UUIDv7.generate(),
        name: name,
        duration: Enum.random(10_000..100_000),
        tuist_version: "4.1.0",
        project_id: cmd_project_id,
        cacheable_targets: cacheable_targets_static,
        local_cache_target_hits: local_cache_hits,
        remote_cache_target_hits: remote_cache_hits,
        test_targets: test_targets,
        local_test_target_hits: local_test_hits,
        remote_test_target_hits: remote_test_hits,
        swift_version: "5.2",
        macos_version: "10.15",
        subcommand: "",
        command_arguments: "",
        is_ci: is_ci,
        user_id: if(is_ci, do: nil, else: cmd_user_id),
        client_id: "client-id",
        status: status,
        error_message: nil,
        preview_id: nil,
        git_ref: nil,
        git_commit_sha: nil,
        git_branch: nil,
        created_at: created_at,
        updated_at: created_at,
        ran_at: created_at,
        build_run_id: nil
      }
    end)

  IngestRepo.insert_all(Event, events, timeout: 120_000)
  :counters.add(event_counter, 1, length(events))

  # Count generate events for later xcode graph generation
  gen_count = Enum.count(events, &(&1.name == "generate"))
  :counters.add(generate_event_counter, 1, gen_count)

  IO.write("\r  Inserted: #{:counters.get(event_counter, 1)}")
end)

IO.puts("\n  Done. (#{:counters.get(generate_event_counter, 1)} generate events)")

# Generate XcodeGraphs, Projects, and Targets in a fully streaming manner
# Process graphs in chunks to avoid memory pressure with 40M+ targets
project_names = ["App", "Framework", "Core", "UI", "Networking", "Database", "Analytics", "Authentication"]

target_names = [
  "AppTarget",
  "FrameworkTarget",
  "CoreKit",
  "UIComponents",
  "NetworkLayer",
  "DataStore",
  "AnalyticsSDK",
  "AuthService",
  "FeatureA",
  "FeatureB",
  "FeatureC",
  "CommonUtils",
  "TestHelpers",
  "Mocks"
]

product_types = [
  "app",
  "static_library",
  "dynamic_library",
  "framework",
  "static_framework",
  "unit_test_bundle",
  "ui_test_bundle",
  "app_extension",
  "watch2_app",
  "watch2_extension"
]

destination_types = ["iphone", "ipad", "mac", "apple_watch", "apple_tv", "apple_vision"]

generate_hash = fn -> SeedHelpers.random_hex(64) end
generate_subhash = fn -> SeedHelpers.random_hex(32) end

xcode_graph_count = seed_config.xcode_graphs
expected_projects = xcode_graph_count * seed_config.xcode_projects_per_graph
expected_targets = expected_projects * seed_config.xcode_targets_per_project

IO.puts("Generating Xcode data by date ranges (optimized for large batches):")
IO.puts("  - #{xcode_graph_count} graphs")
IO.puts("  - ~#{expected_projects} projects")
IO.puts("  - ~#{expected_targets} targets")

# Counters for progress tracking
graph_counter = :counters.new(1, [:atomics])
project_counter = :counters.new(1, [:atomics])
target_counter = :counters.new(1, [:atomics])

# Generate data BY DATE to allow large batch inserts (staying under 100 partition limit)
# With 400 days and 1M graphs, we get ~2500 graphs/day
# Process 10 days at a time = ~25K graphs -> 125K projects -> 1M targets per batch
total_days = 400
graphs_per_day = max(div(xcode_graph_count, total_days), 1)
days_per_batch = 10

# Pre-generate values for faster target creation
# Generate pools of random hashes to pick from (avoids expensive per-target generation)
hash_pool = Enum.map(1..1000, fn _ -> SeedHelpers.random_hex(64) end)
subhash_pool = Enum.map(1..1000, fn _ -> SeedHelpers.random_hex(32) end)
dest_pool = [["iphone"], ["ipad"], ["mac"], ["iphone", "ipad"], ["mac", "iphone"], ["apple_watch", "iphone"]]

# Simplified target creation - minimal randomness per target
make_target = fn project, target_idx, target_name ->
  # Use index-based selection for speed (no random per target)
  hit_value = rem(target_idx, 3)
  is_external = rem(target_idx, 10) == 0
  hash_idx = rem(target_idx, 1000)

  %{
    id: UUIDv7.generate(),
    name: "#{project.name}_#{target_name}",
    binary_cache_hash: Enum.at(hash_pool, hash_idx),
    binary_cache_hit: hit_value,
    binary_build_duration: 5000 + rem(target_idx * 17, 25_000),
    selective_testing_hash: nil,
    selective_testing_hit: 0,
    xcode_project_id: project.id,
    command_event_id: project.command_event_id,
    inserted_at: project.inserted_at,
    product: Enum.at(product_types, rem(target_idx, length(product_types))),
    bundle_id: "com.tuist.#{String.downcase(project.name)}.#{String.downcase(target_name)}",
    product_name: target_name,
    destinations: Enum.at(dest_pool, rem(target_idx, length(dest_pool))),
    external_hash: if(is_external, do: Enum.at(subhash_pool, hash_idx), else: ""),
    sources_hash: if(is_external, do: "", else: Enum.at(subhash_pool, rem(hash_idx + 1, 1000))),
    resources_hash:
      if(rem(target_idx, 2) == 0 and not is_external, do: Enum.at(subhash_pool, rem(hash_idx + 2, 1000)), else: ""),
    copy_files_hash: "",
    core_data_models_hash: "",
    target_scripts_hash: "",
    environment_hash: if(is_external, do: "", else: Enum.at(subhash_pool, rem(hash_idx + 3, 1000))),
    headers_hash: "",
    deployment_target_hash: if(is_external, do: "", else: Enum.at(subhash_pool, rem(hash_idx + 4, 1000))),
    info_plist_hash:
      if(rem(target_idx, 2) == 0 and not is_external, do: Enum.at(subhash_pool, rem(hash_idx + 5, 1000)), else: ""),
    entitlements_hash: "",
    dependencies_hash: if(is_external, do: "", else: Enum.at(subhash_pool, rem(hash_idx + 6, 1000))),
    project_settings_hash: if(is_external, do: "", else: Enum.at(subhash_pool, rem(hash_idx + 7, 1000))),
    target_settings_hash: if(is_external, do: "", else: Enum.at(subhash_pool, rem(hash_idx + 8, 1000))),
    buildable_folders_hash: "",
    additional_strings: []
  }
end

# Process in date batches - each batch has only days_per_batch unique dates
# This allows us to use 50K chunk sizes safely (well under 100 partition limit)
0..(total_days - 1)
|> Stream.chunk_every(days_per_batch)
|> Enum.each(fn day_offsets ->
  # Generate all graphs for this date range
  graphs =
    Enum.flat_map(day_offsets, fn day_offset ->
      inserted_at = base_date |> Date.add(-day_offset) |> DateTime.new!(~T[12:00:00]) |> DateTime.to_naive()

      Enum.map(1..graphs_per_day, fn _ ->
        %{
          id: UUIDv7.generate(),
          name: "Workspace",
          command_event_id: UUIDv7.generate(),
          binary_build_duration: Enum.random(10_000..300_000),
          inserted_at: inserted_at
        }
      end)
    end)

  # Insert graphs (all from ≤10 dates, safe for large batch)
  IngestRepo.insert_all(Tuist.Xcode.XcodeGraph, graphs, timeout: 120_000)
  :counters.add(graph_counter, 1, length(graphs))

  # Generate all projects for this batch's graphs
  projects =
    Enum.flat_map(graphs, fn graph ->
      Enum.map(1..seed_config.xcode_projects_per_graph, fn i ->
        project_name = Enum.at(project_names, rem(i - 1, length(project_names)))

        %{
          id: UUIDv7.generate(),
          name: project_name,
          path: "/#{project_name}/#{project_name}.xcodeproj",
          xcode_graph_id: graph.id,
          command_event_id: graph.command_event_id,
          inserted_at: graph.inserted_at
        }
      end)
    end)

  # Insert projects in 50K chunks (safe with ≤10 dates per batch)
  projects
  |> Enum.chunk_every(50_000)
  |> Enum.each(fn chunk ->
    IngestRepo.insert_all(Tuist.Xcode.XcodeProject, chunk, timeout: 120_000)
    :counters.add(project_counter, 1, length(chunk))
  end)

  # Generate and insert targets in 100K chunks (safe with ≤10 dates per batch)
  # Use with_index for deterministic variation
  projects
  |> Stream.with_index()
  |> Stream.flat_map(fn {project, proj_idx} ->
    Enum.map(1..seed_config.xcode_targets_per_project, fn i ->
      target_name = Enum.at(target_names, rem(i - 1, length(target_names)))
      make_target.(project, proj_idx * 100 + i, target_name)
    end)
  end)
  |> Stream.chunk_every(100_000)
  |> Enum.each(fn chunk ->
    IngestRepo.insert_all(Tuist.Xcode.XcodeTarget, chunk, timeout: 120_000)
    :counters.add(target_counter, 1, length(chunk))
  end)

  IO.write(
    "\r  Progress: graphs=#{:counters.get(graph_counter, 1)}, projects=#{:counters.get(project_counter, 1)}, targets=#{:counters.get(target_counter, 1)}"
  )
end)

IO.puts("")
IO.puts("Xcode data generation complete:")
IO.puts("  - Graphs: #{:counters.get(graph_counter, 1)}")
IO.puts("  - Projects: #{:counters.get(project_counter, 1)}")
IO.puts("  - Targets: #{:counters.get(target_counter, 1)}")

bundle_identifiers = [
  "com.example.myapp.mixed",
  "com.example.myapp.all",
  "com.example.myapp.single",
  "com.example.myapp.watch"
]

platform_combinations = [
  [:ios_simulator, :ios, :macos],
  [:macos, :ios, :watchos_simulator, :tvos_simulator, :ios_simulator, :visionos],
  [:ios],
  [:watchos_simulator, :visionos, :watchos, :visionos_simulator]
]

preview_tracks = ["", "", "", "beta", "nightly", "internal"]

IO.puts("Generating #{seed_config.previews} previews...")

test_previews =
  Enum.map(1..seed_config.previews, fn _index ->
    bundle_identifier = Enum.random(bundle_identifiers)
    supported_platforms = Enum.random(platform_combinations)

    version = "#{Enum.random(1..5)}.#{Enum.random(0..9)}.#{Enum.random(0..9)}"

    git_commit_sha =
      1..12
      |> Enum.map(fn _ -> Enum.random(~c"0123456789abcdef") end)
      |> List.to_string()

    git_branch = Enum.random(branches)
    track = Enum.random(preview_tracks)

    %{
      display_name: "MyApp",
      bundle_identifier: bundle_identifier,
      version: version,
      supported_platforms: supported_platforms,
      git_branch: git_branch,
      git_commit_sha: git_commit_sha,
      track: track,
      project_id: tuist_project.id,
      created_by_account_id: organization.account.id,
      inserted_at:
        DateTime.new!(
          Date.add(DateTime.utc_now(), -Enum.random(0..400)),
          Time.new!(
            Enum.random(0..23),
            Enum.random(0..59),
            Enum.random(0..59)
          )
        ),
      visibility: :public
    }
  end)

Enum.each(test_previews, fn preview_attrs ->
  changeset = Preview.create_changeset(%Preview{}, preview_attrs)
  preview = Repo.insert!(changeset)

  supported_platforms = preview_attrs.supported_platforms

  Enum.each(1..Enum.random(1..3), fn _ ->
    build_platforms =
      Enum.take_random(supported_platforms, Enum.random(1..length(supported_platforms)))

    build_type = Enum.random([:app_bundle, :ipa])

    binary_id =
      1..32
      |> Enum.map(fn _ -> Enum.random(~c"0123456789abcdef") end)
      |> List.to_string()

    app_build_attrs = %{
      preview_id: preview.id,
      type: build_type,
      supported_platforms: build_platforms,
      binary_id: binary_id
    }

    app_build_changeset = AppBuild.create_changeset(%AppBuild{}, app_build_attrs)
    Repo.insert!(app_build_changeset)
  end)
end)

app_builds = AppBuild |> Repo.all() |> Repo.preload(preview: :project)

qa_prompts = [
  "Test the main app flow and login functionality",
  "Verify that all buttons work correctly and navigation is smooth",
  "Check if the app handles edge cases properly",
  "Test the user registration and onboarding process",
  "Validate the app's performance under various conditions",
  "Test accessibility features and VoiceOver support",
  "Verify dark mode and light mode switching",
  "Test the payment flow and subscription features",
  "Check if push notifications work correctly",
  "Test offline functionality and data synchronization"
]

qa_statuses = ["pending", "running", "completed", "failed"]

selected_app_builds = Enum.take_random(app_builds, 25)

qa_runs =
  Enum.map(selected_app_builds, fn app_build ->
    status = Enum.random(qa_statuses)
    prompt = Enum.random(qa_prompts)

    git_refs = ["main", "develop", "feature/new-ui", "feature/qa-testing", "release/v1.2.0"]

    inserted_at =
      DateTime.new!(
        Date.add(DateTime.utc_now(), -Enum.random(0..30)),
        Time.new!(
          Enum.random(0..23),
          Enum.random(0..59),
          Enum.random(0..59)
        )
      )

    finished_at =
      if status in ["completed", "failed"] do
        duration_minutes = Enum.random(5..45)
        DateTime.add(inserted_at, duration_minutes * 60, :second)
      end

    base_attrs = %{
      id: UUIDv7.generate(),
      app_build_id: app_build.id,
      prompt: prompt,
      status: status,
      git_ref: Enum.random(git_refs),
      issue_comment_id: if(Enum.random([true, false]), do: Enum.random(1000..9999)),
      inserted_at: inserted_at,
      updated_at: inserted_at
    }

    if finished_at do
      Map.put(base_attrs, :finished_at, finished_at)
    else
      base_attrs
    end
  end)

Repo.insert_all(Run, qa_runs)

qa_logs =
  Enum.flat_map(qa_runs, fn qa_run ->
    log_messages =
      case qa_run.status do
        "pending" ->
          [
            {"info", "QA run initialized"},
            {"debug", "Waiting for agent to become available"}
          ]

        "running" ->
          [
            {"info", "QA run initialized"},
            {"debug", "Waiting for agent to become available"},
            {"info", "QA agent started"},
            {"info", "Starting test execution"},
            {"debug", "Loading app on simulator"},
            {"info", "Running automated tests..."}
          ]

        "completed" ->
          [
            {"info", "QA run initialized"},
            {"debug", "Waiting for agent to become available"},
            {"info", "QA agent started"},
            {"info", "Starting test execution"},
            {"debug", "Loading app on simulator"},
            {"info", "Running automated tests..."},
            {"debug", "Screenshot captured for main screen"},
            {"info", "Testing navigation flows"},
            {"debug", "All UI elements found and verified"},
            {"info", "Testing user interactions"},
            {"debug", "Form validation tests passed"},
            {"info", "Testing edge cases"},
            {"debug", "Error handling validated"},
            {"info", "All tests completed successfully"},
            {"info", "Generating test summary"},
            {"info", "QA run completed successfully"}
          ]

        "failed" ->
          [
            {"info", "QA run initialized"},
            {"debug", "Waiting for agent to become available"},
            {"info", "QA agent started"},
            {"info", "Starting test execution"},
            {"debug", "Loading app on simulator"},
            {"info", "Running automated tests..."},
            {"warning", "App took longer than expected to load"},
            {"debug", "Screenshot captured for main screen"},
            {"info", "Testing navigation flows"},
            {"error", "Button element not found on screen"},
            {"debug", "Attempting to retry element lookup"},
            {"error", "Element lookup failed after retry"},
            {"warning", "Continuing with remaining tests"},
            {"info", "Testing user interactions"},
            {"error", "Form submission failed - validation error"},
            {"debug", "Error details: Required field missing"},
            {"error", "Critical test failure detected"},
            {"info", "Stopping test execution due to failures"},
            {"error", "QA run failed with critical issues"}
          ]
      end

    base_time = qa_run.inserted_at

    duration_minutes =
      case qa_run.status do
        "pending" -> 1
        "running" -> 15
        "completed" -> 30
        "failed" -> 20
      end

    log_messages
    |> Enum.with_index()
    |> Enum.map(fn {{level, message}, index} ->
      minutes_offset = div(duration_minutes * index, length(log_messages))

      log_timestamp =
        base_time
        |> NaiveDateTime.add(minutes_offset * 60, :second)
        |> NaiveDateTime.truncate(:second)

      level_int =
        case level do
          "debug" -> 0
          "info" -> 1
          "warning" -> 2
          "error" -> 3
        end

      app_build = Enum.find(app_builds, &(&1.id == qa_run.app_build_id))
      project_id = app_build.preview.project.id

      %{
        project_id: project_id,
        qa_run_id: qa_run.id,
        data: message,
        type: level_int,
        timestamp: log_timestamp,
        inserted_at: log_timestamp
      }
    end)
  end)

qa_logs
|> Enum.chunk_every(1000)
|> Enum.each(fn chunk ->
  processed_logs =
    Enum.map(chunk, fn log ->
      %{
        log
        | timestamp: NaiveDateTime.truncate(log.timestamp, :second),
          inserted_at: NaiveDateTime.truncate(log.inserted_at, :second)
      }
    end)

  IngestRepo.insert_all(Log, processed_logs, timeout: 120_000)
end)

token_usage_data =
  Enum.flat_map(qa_runs, fn qa_run ->
    app_build = Enum.find(app_builds, &(&1.id == qa_run.app_build_id))
    account_id = app_build.preview.project.account_id

    case qa_run.status do
      "completed" ->
        base_time = qa_run.inserted_at

        [
          %{
            id: UUIDv7.generate(),
            input_tokens: Enum.random(800..1500),
            output_tokens: Enum.random(400..800),
            model: "claude-sonnet-4-20250514",
            feature: "qa",
            feature_resource_id: qa_run.id,
            account_id: account_id,
            timestamp: DateTime.add(base_time, Enum.random(10..30), :second),
            inserted_at: DateTime.add(base_time, Enum.random(10..30), :second),
            updated_at: DateTime.add(base_time, Enum.random(10..30), :second)
          },
          %{
            id: UUIDv7.generate(),
            input_tokens: Enum.random(500..1000),
            output_tokens: Enum.random(300..600),
            model: "claude-sonnet-4-20250514",
            feature: "qa",
            feature_resource_id: qa_run.id,
            account_id: account_id,
            timestamp: DateTime.add(base_time, Enum.random(60..120), :second),
            inserted_at: DateTime.add(base_time, Enum.random(60..120), :second),
            updated_at: DateTime.add(base_time, Enum.random(60..120), :second)
          },
          %{
            id: UUIDv7.generate(),
            input_tokens: Enum.random(200..600),
            output_tokens: Enum.random(100..300),
            model: "claude-sonnet-4-20250514",
            feature: "qa",
            feature_resource_id: qa_run.id,
            account_id: account_id,
            timestamp: DateTime.add(base_time, Enum.random(150..200), :second),
            inserted_at: DateTime.add(base_time, Enum.random(150..200), :second),
            updated_at: DateTime.add(base_time, Enum.random(150..200), :second)
          }
        ]

      "failed" ->
        base_time = qa_run.inserted_at

        [
          %{
            id: UUIDv7.generate(),
            input_tokens: Enum.random(600..1200),
            output_tokens: Enum.random(300..600),
            model: "claude-sonnet-4-20250514",
            feature: "qa",
            feature_resource_id: qa_run.id,
            account_id: account_id,
            timestamp: DateTime.add(base_time, Enum.random(10..30), :second),
            inserted_at: DateTime.add(base_time, Enum.random(10..30), :second),
            updated_at: DateTime.add(base_time, Enum.random(10..30), :second)
          }
        ]

      "running" ->
        base_time = qa_run.inserted_at

        [
          %{
            id: UUIDv7.generate(),
            input_tokens: Enum.random(400..800),
            output_tokens: Enum.random(200..400),
            model: "claude-sonnet-4-20250514",
            feature: "qa",
            feature_resource_id: qa_run.id,
            account_id: account_id,
            timestamp: DateTime.add(base_time, Enum.random(5..15), :second),
            inserted_at: DateTime.add(base_time, Enum.random(5..15), :second),
            updated_at: DateTime.add(base_time, Enum.random(5..15), :second)
          }
        ]

      _ ->
        []
    end
  end)

if !Enum.empty?(token_usage_data) do
  Repo.insert_all(Billing.TokenUsage, token_usage_data)
  IO.puts("Created #{length(token_usage_data)} token usage records")
end

# Create bundles with artifacts
bundle_types = [:app, :ipa, :xcarchive]

platforms_combinations = [
  [:ios, :ios_simulator],
  [:macos],
  [:ios, :ios_simulator, :macos],
  [:watchos, :watchos_simulator],
  [:tvos, :tvos_simulator],
  [:visionos, :visionos_simulator]
]

git_branches = ["main", "develop", "feature/new-ui", "feature/caching", "hotfix/memory-leak"]

bundle_names = [
  "TuistApp",
  "TuistInternalApp"
]

IO.puts("Generating #{seed_config.bundles} bundles...")

Enum.map(1..seed_config.bundles, fn index ->
  bundle_id = UUIDv7.generate()
  bundle_name = Enum.random(bundle_names)
  bundle_type = Enum.random(bundle_types)
  supported_platforms = Enum.random(platforms_combinations)
  git_branch = Enum.random(git_branches)

  git_commit_sha =
    1..40
    |> Enum.map(fn _ -> Enum.random(~c"0123456789abcdef") end)
    |> List.to_string()

  inserted_at =
    DateTime.new!(
      Date.add(DateTime.utc_now(), -Enum.random(0..90)),
      Time.new!(
        Enum.random(0..23),
        Enum.random(0..59),
        Enum.random(0..59)
      )
    )

  artifacts = [
    %{
      artifact_type: :directory,
      path: "#{bundle_name}.#{"app"}",
      size: 0,
      shasum: :sha256 |> :crypto.hash("#{bundle_name}-root-#{index}") |> Base.encode16(case: :lower)
    },
    %{
      artifact_type: :file,
      path: "#{bundle_name}.#{"app"}/Info.plist",
      size: Enum.random(1000..3000),
      shasum: :sha256 |> :crypto.hash("#{bundle_name}-info-#{index}") |> Base.encode16(case: :lower)
    },
    %{
      artifact_type: :binary,
      path: "#{bundle_name}.#{"app"}/#{bundle_name}",
      size: Enum.random(1_000_000..50_000_000),
      shasum: :sha256 |> :crypto.hash("#{bundle_name}-binary-#{index}") |> Base.encode16(case: :lower)
    },
    %{
      artifact_type: :directory,
      path: "#{bundle_name}.app/Assets.car",
      size: 0,
      shasum: :sha256 |> :crypto.hash("#{bundle_name}-assets-dir-#{index}") |> Base.encode16(case: :lower)
    },
    %{
      artifact_type: :asset,
      path: "#{bundle_name}.app/Assets.car/Contents.json",
      size: Enum.random(50_000..500_000),
      shasum: :sha256 |> :crypto.hash("#{bundle_name}-assets-#{index}") |> Base.encode16(case: :lower)
    },
    # Localization
    %{
      artifact_type: :directory,
      path: "#{bundle_name}.app/en.lproj",
      size: 0,
      shasum: :sha256 |> :crypto.hash("#{bundle_name}-localization-dir-#{index}") |> Base.encode16(case: :lower)
    },
    %{
      artifact_type: :localization,
      path: "#{bundle_name}.app/en.lproj/Localizable.strings",
      size: Enum.random(1000..10_000),
      shasum: :sha256 |> :crypto.hash("#{bundle_name}-localization-#{index}") |> Base.encode16(case: :lower)
    },
    # Fonts
    %{
      artifact_type: :font,
      path: "#{bundle_name}.app/Fonts/CustomFont.ttf",
      size: Enum.random(50_000..200_000),
      shasum: :sha256 |> :crypto.hash("#{bundle_name}-font-#{index}") |> Base.encode16(case: :lower)
    }
  ]

  {:ok, bundle} =
    Bundles.create_bundle(%{
      id: bundle_id,
      name: bundle_name,
      app_bundle_id: "dev.tuist.#{String.downcase(bundle_name)}",
      install_size: Enum.sum(Enum.map(artifacts, & &1.size)),
      download_size: Enum.random(500_000..20_000_000),
      supported_platforms: supported_platforms,
      version: "#{Enum.random(1..3)}.#{Enum.random(0..9)}.#{Enum.random(0..9)}",
      git_branch: git_branch,
      git_commit_sha: git_commit_sha,
      git_ref: if(git_branch == "main", do: nil, else: "refs/heads/#{git_branch}"),
      type: bundle_type,
      project_id: tuist_project.id,
      uploaded_by_account_id: organization.account.id,
      inserted_at: inserted_at,
      artifacts: artifacts
    })

  bundle
end)

# Create Slack installation for the organization
slack_installation =
  if slack_access_token = Environment.get([:slack, :access_token]) do
    case Repo.get_by(Installation, account_id: organization.account.id) do
      nil ->
        %Installation{}
        |> Installation.changeset(%{
          account_id: organization.account.id,
          team_id: "T061C1JGAHH",
          team_name: "Tuist Company",
          access_token: slack_access_token,
          bot_user_id: "U0A5N3H2RJM"
        })
        |> Repo.insert!()

      installation ->
        installation
    end
  else
    IO.puts("Skipping Slack installation (slack.access_token not set in secrets)")
    nil
  end

# Update tuist_project with Slack report settings (only if Slack is configured)
if slack_installation do
  tuist_project
  |> Project.update_changeset(%{
    slack_channel_id: "C0A598PACRG",
    slack_channel_name: "test",
    report_frequency: :daily,
    report_days_of_week: [1, 2, 3, 4, 5],
    report_schedule_time: ~U[2024-01-01 09:00:00Z],
    report_timezone: "Europe/Berlin",
    # Flaky test alert settings
    flaky_test_alerts_enabled: true,
    flaky_test_alerts_slack_channel_id: "C0A598PACRG",
    flaky_test_alerts_slack_channel_name: "test"
  })
  |> Repo.update!()

  IO.puts("Updated tuist project with Slack report and flaky test alert settings")
end

# Create alert rules for the tuist project (only if Slack is configured)
if slack_installation do
  alert_rules_data = [
    %{
      name: "Build Duration P90 Alert",
      category: :build_run_duration,
      metric: :p90,
      deviation_percentage: 20.0,
      rolling_window_size: 7,
      slack_channel_id: "C0A598PACRG",
      slack_channel_name: "test"
    },
    %{
      name: "Test Duration P50 Alert",
      category: :test_run_duration,
      metric: :p50,
      deviation_percentage: 15.0,
      rolling_window_size: 14,
      slack_channel_id: "C0A598PACRG",
      slack_channel_name: "test"
    },
    %{
      name: "Cache Hit Rate Alert",
      category: :cache_hit_rate,
      metric: :average,
      deviation_percentage: 10.0,
      rolling_window_size: 7,
      slack_channel_id: "C0A598PACRG",
      slack_channel_name: "test"
    }
  ]

  alert_rules =
    Enum.map(alert_rules_data, fn rule_data ->
      case Repo.get_by(AlertRule, project_id: tuist_project.id, name: rule_data.name) do
        nil ->
          %AlertRule{}
          |> AlertRule.changeset(Map.put(rule_data, :project_id, tuist_project.id))
          |> Repo.insert!()

        existing_rule ->
          existing_rule
      end
    end)

  IO.puts("Created #{length(alert_rules)} alert rules")

  # Create sample alerts for the first alert rule
  first_alert_rule = List.first(alert_rules)

  if Repo.aggregate(from(a in Alert, where: a.alert_rule_id == ^first_alert_rule.id), :count) == 0 do
    sample_alerts =
      Enum.map(1..5, fn i ->
        inserted_at =
          DateTime.utc_now()
          |> DateTime.add(-i * 24 * 3600, :second)
          |> DateTime.truncate(:second)

        %{
          id: UUIDv7.generate(),
          alert_rule_id: first_alert_rule.id,
          previous_value: 30_000.0 + Enum.random(0..5000),
          current_value: 40_000.0 + Enum.random(0..10_000),
          inserted_at: inserted_at,
          updated_at: inserted_at
        }
      end)

    Repo.insert_all(Alert, sample_alerts)
    IO.puts("Created #{length(sample_alerts)} sample alerts")
  end
end

IO.puts("")
IO.puts("=== Seed Complete (scale: #{seed_scale}) ===")
IO.puts("Generated:")
IO.puts("  - #{seed_config.build_runs} build runs")
IO.puts("  - #{seed_config.test_runs} test runs")
IO.puts("  - #{seed_config.command_events} command events")
IO.puts("  - #{seed_config.previews} previews")
IO.puts("  - #{seed_config.bundles} bundles")
IO.puts("")
IO.puts("To generate production-like volumes, run:")
IO.puts("  SEED_SCALE=medium mix run priv/repo/seeds.exs")
IO.puts("")
IO.puts("To generate 2x production volumes (staging/canary load testing), run:")
IO.puts("  SEED_SCALE=large mix run priv/repo/seeds.exs")
