alias Tuist.Accounts
alias Tuist.AppBuilds.AppBuild
alias Tuist.AppBuilds.Preview
alias Tuist.Billing
alias Tuist.Billing.Subscription
alias Tuist.Bundles
alias Tuist.CommandEvents.Event
alias Tuist.IngestRepo
alias Tuist.Projects
alias Tuist.Projects.Project
alias Tuist.QA
alias Tuist.QA.Log
alias Tuist.QA.Run
alias Tuist.Repo
alias Tuist.Runs.Build
alias Tuist.Runs.Test

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

builds =
  Enum.map(1..2000, fn _ ->
    status = Enum.random([:success, :failure])
    is_ci = Enum.random([true, false])
    scheme = Enum.random(["App", "AppTests"])
    xcode_version = Enum.random(["12.4", "13.0", "13.2"])
    macos_version = Enum.random(["11.2.3", "12.3.4", "13.4.5"])

    model_identifier =
      Enum.random(["MacBookPro14,2", "MacBookPro15,1", "MacBookPro10,2", "Macmini8,1"])

    configuration = Enum.random(["Debug", "Release"])

    account_id = if is_ci, do: organization.account.id, else: user.account.id

    inserted_at =
      DateTime.new!(
        Date.add(DateTime.utc_now(), -Enum.random(0..400)),
        Time.new!(
          Enum.random(0..23),
          Enum.random(0..59),
          Enum.random(0..59)
        )
      )

    total_tasks = Enum.random(50..200)
    remote_hits = Enum.random(0..div(total_tasks, 2))
    local_hits = Enum.random(0..(total_tasks - remote_hits))

    %{
      id: UUIDv7.generate(),
      duration: Enum.random(10_000..100_000),
      macos_version: macos_version,
      xcode_version: xcode_version,
      is_ci: is_ci,
      model_identifier: model_identifier,
      project_id: tuist_project.id,
      account_id: account_id,
      scheme: scheme,
      configuration: configuration,
      inserted_at: inserted_at,
      status: status,
      cacheable_tasks_count: total_tasks,
      cacheable_task_remote_hits_count: remote_hits,
      cacheable_task_local_hits_count: local_hits
    }
  end)

{_count, build_records} = Repo.insert_all(Build, builds, returning: [:id])

generate_cache_key = fn _build_id, _task_type, _index ->
  # Generate base64-like content similar to the real example
  # Real keys are mostly alphanumeric with occasional + / = _ - characters
  content =
    1..88
    |> Enum.map(fn i ->
      case rem(i, 20) do
        # 85% alphanumeric characters
        x when x < 17 ->
          Enum.random([
            Enum.random(?A..?Z),
            Enum.random(?a..?z),
            Enum.random(?0..?9)
          ])

        # 15% special base64 characters
        _ ->
          Enum.random([?+, ?/, ?=, ?_, ?-])
      end
    end)
    |> List.to_string()

  "0~#{content}"
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

generate_cas_node_id = fn ->
  # Generate realistic CAS node IDs (base64-like strings)
  content =
    1..64
    |> Enum.map(fn _ ->
      Enum.random([
        Enum.random(?A..?Z),
        Enum.random(?a..?z),
        Enum.random(?0..?9),
        ?+,
        ?/,
        ?=
      ])
    end)
    |> List.to_string()

  content
end

generate_checksum = fn ->
  # Generate SHA256-like checksums
  1..64
  |> Enum.map(fn _ -> Enum.random(~c"0123456789abcdef") end)
  |> List.to_string()
end

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

cas_outputs =
  Enum.flat_map(builds, fn build ->
    # Generate 5-25 CAS operations per build
    operation_count = Enum.random(5..25)

    Enum.map(1..operation_count, fn _i ->
      operation = Enum.random(["download", "upload"])
      size = Enum.random(1024..50_000_000)
      # 1KB to 50MB
      compressed_size = trunc(size * (0.3 + :rand.uniform() * 0.6))
      # 30-90% compression
      duration = Enum.random(100..30_000)

      %{
        build_run_id: build.id,
        node_id: generate_cas_node_id.(),
        checksum: generate_checksum.(),
        size: size,
        duration: duration,
        compressed_size: compressed_size,
        operation: operation,
        type: Enum.random(cas_file_types),
        inserted_at: DateTime.to_naive(build.inserted_at)
      }
    end)
  end)

cas_outputs
|> Enum.chunk_every(1000)
|> Enum.each(fn chunk ->
  IngestRepo.insert_all(Tuist.Runs.CASOutput, chunk)
end)

# Generate CAS events based on CAS outputs
# CAS events track upload/download actions for analytics
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

cas_events
|> Enum.chunk_every(1000)
|> Enum.each(fn chunk ->
  IngestRepo.insert_all(Tuist.Cache.CASEvent, chunk)
end)

# Group CAS outputs by build_id for later use
cas_outputs_by_build = Enum.group_by(cas_outputs, & &1.build_run_id)

cacheable_tasks =
  build_records
  |> Enum.map(& &1.id)
  |> Enum.shuffle()
  |> Enum.take(500)
  |> Enum.flat_map(fn build_id ->
    build = Enum.find(builds, &(&1.id == build_id))
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

cacheable_tasks
|> Enum.chunk_every(1000)
|> Enum.each(fn chunk ->
  IngestRepo.insert_all(Tuist.Runs.CacheableTask, chunk)
end)

branches = [
  "main",
  "develop",
  "feature/wearables",
  "feature/new-ui",
  "bugfix/crash-fix",
  "release/v2.0",
  "hotfix/security"
]

tests =
  Enum.map(1..1500, fn _ ->
    status = Enum.random(["success", "failure"])
    is_ci = Enum.random([true, false])
    scheme = Enum.random(["AppTests", "FrameworkTests", "UITests"])
    xcode_version = Enum.random(["12.4", "13.0", "13.2"])
    macos_version = Enum.random(["11.2.3", "12.3.4", "13.4.5"])

    model_identifier =
      Enum.random(["MacBookPro14,2", "MacBookPro15,1", "MacBookPro10,2", "Macmini8,1"])

    account_id = if is_ci, do: organization.account.id, else: user.account.id

    ran_at =
      DateTime.utc_now()
      |> Date.add(-Enum.random(0..400))
      |> DateTime.new!(
        Time.new!(
          Enum.random(0..23),
          Enum.random(0..59),
          Enum.random(0..59),
          Enum.random(0..999_999)
        )
      )
      |> DateTime.to_naive()

    inserted_at =
      DateTime.utc_now()
      |> Date.add(-Enum.random(0..400))
      |> DateTime.new!(
        Time.new!(
          Enum.random(0..23),
          Enum.random(0..59),
          Enum.random(0..59),
          Enum.random(0..999_999)
        )
      )
      |> DateTime.to_naive()

    git_branch = Enum.random(branches)

    ci_run_id = if is_ci, do: "#{Enum.random(19_000_000_000..20_000_000_000)}", else: ""

    %{
      id: UUIDv7.generate(),
      duration: Enum.random(5_000..60_000),
      macos_version: macos_version,
      xcode_version: xcode_version,
      is_ci: is_ci,
      model_identifier: model_identifier,
      scheme: scheme,
      status: status,
      git_branch: git_branch,
      git_commit_sha:
        Enum.random([
          "a1b2c3d4e5f6",
          "f6e5d4c3b2a1",
          "123456789abc",
          "abcdef123456"
        ]),
      git_ref: "refs/heads/#{git_branch}",
      ran_at: ran_at,
      project_id: tuist_project.id,
      account_id: account_id,
      inserted_at: inserted_at,
      ci_run_id: ci_run_id,
      ci_project_handle: if(is_ci, do: "tuist/tuist", else: ""),
      ci_host: "",
      ci_provider: if(is_ci, do: "github")
    }
  end)

IngestRepo.insert_all(Test, tests)

# Generate test modules, suites, cases, and failures similar to how builds generate cacheable tasks
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

# Select a subset of test runs to generate detailed data for (similar to builds)
selected_tests = tests |> Enum.shuffle() |> Enum.take(800)

test_module_runs =
  Enum.flat_map(selected_tests, fn test ->
    # Each test run has 2-4 test modules
    module_count = Enum.random(2..4)

    Enum.map(1..module_count, fn _ ->
      module_name = Enum.random(module_names)
      # Inherit status from test run, but sometimes modules can succeed even if test failed
      module_status = if test.status == "success", do: 0, else: Enum.random([0, 0, 1])
      suite_count = Enum.random(2..5)
      case_count = Enum.random(10..50)
      module_duration = Enum.random(1_000..10_000)
      avg_duration = div(module_duration, max(case_count, 1))

      %{
        id: UUIDv7.generate(),
        name: module_name,
        test_run_id: test.id,
        status: module_status,
        duration: module_duration,
        test_suite_count: suite_count,
        test_case_count: case_count,
        avg_test_case_duration: avg_duration,
        inserted_at: test.inserted_at
      }
    end)
  end)

test_module_runs
|> Enum.chunk_every(1000)
|> Enum.each(fn chunk ->
  IngestRepo.insert_all(Tuist.Runs.TestModuleRun, chunk)
end)

# Generate test suite runs
test_suite_runs =
  Enum.flat_map(test_module_runs, fn module_run ->
    # Create the number of suites specified in test_suite_count
    suite_count = module_run.test_suite_count
    test_run = Enum.find(tests, &(&1.id == module_run.test_run_id))

    Enum.map(1..suite_count, fn _ ->
      suite_name = Enum.random(suite_names)
      # Inherit status from module, but allow some variation
      suite_status =
        if module_run.status == 0 do
          Enum.random([0, 0, 0, 0, 2])
        else
          Enum.random([0, 0, 1, 2])
        end

      case_count =
        Enum.random(
          max(1, div(module_run.test_case_count, suite_count) - 2)..(div(module_run.test_case_count, suite_count) + 2)
        )

      suite_duration = Enum.random(500..div(module_run.duration, suite_count))
      avg_duration = if case_count > 0, do: div(suite_duration, case_count), else: 0

      %{
        id: UUIDv7.generate(),
        name: suite_name,
        test_run_id: test_run.id,
        test_module_run_id: module_run.id,
        status: suite_status,
        duration: suite_duration,
        test_case_count: max(case_count, 1),
        avg_test_case_duration: avg_duration,
        inserted_at: module_run.inserted_at
      }
    end)
  end)

test_suite_runs
|> Enum.chunk_every(1000)
|> Enum.each(fn chunk ->
  IngestRepo.insert_all(Tuist.Runs.TestSuiteRun, chunk)
end)

# Create test cases first with all unique combinations of (module_name, suite_name, test_case_name)
# This creates the test_cases and returns a map of {name, module_name, suite_name} => test_case_id
test_case_definitions =
  for module_name <- module_names,
      suite_name <- suite_names,
      test_case_name <- test_case_names do
    %{
      name: test_case_name,
      module_name: module_name,
      suite_name: suite_name,
      status: Enum.random(["success", "failure", "skipped"]),
      duration: Enum.random(10..500),
      ran_at: NaiveDateTime.utc_now()
    }
  end

test_case_id_map = Tuist.Runs.create_test_cases(tuist_project.id, test_case_definitions)

# Convert to a list of test cases with their IDs for easy random selection
test_cases_with_ids =
  Enum.map(test_case_id_map, fn {{name, module_name, suite_name}, id} ->
    %{id: id, name: name, module_name: module_name, suite_name: suite_name}
  end)

# Generate test case runs by selecting from existing test cases
test_case_runs =
  Enum.flat_map(test_suite_runs, fn suite_run ->
    case_count = suite_run.test_case_count
    module_run = Enum.find(test_module_runs, &(&1.id == suite_run.test_module_run_id))
    test_run = Enum.find(tests, &(&1.id == suite_run.test_run_id))

    # Filter test cases matching this module and suite
    matching_test_cases =
      Enum.filter(test_cases_with_ids, fn tc ->
        tc.module_name == module_run.name && tc.suite_name == suite_run.name
      end)

    # If no exact match, use all test cases (fallback)
    available_test_cases = if Enum.empty?(matching_test_cases), do: test_cases_with_ids, else: matching_test_cases

    Enum.map(1..case_count, fn _ ->
      test_case = Enum.random(available_test_cases)

      case_status =
        if suite_run.status == 0 do
          Enum.random([0, 0, 0, 0, 0, 0, 0, 0, 1, 2])
        else
          Enum.random([0, 0, 1, 2])
        end

      case_duration = Enum.random(10..max(10, div(suite_run.duration, max(case_count, 1)) * 2))

      %{
        id: UUIDv7.generate(),
        name: test_case.name,
        test_run_id: suite_run.test_run_id,
        test_module_run_id: suite_run.test_module_run_id,
        test_suite_run_id: suite_run.id,
        test_case_id: test_case.id,
        project_id: test_run.project_id,
        is_ci: test_run.is_ci,
        scheme: test_run.scheme,
        account_id: test_run.account_id,
        ran_at: test_run.ran_at,
        git_branch: test_run.git_branch,
        status: case_status,
        duration: case_duration,
        module_name: test_case.module_name,
        suite_name: test_case.suite_name,
        inserted_at: suite_run.inserted_at
      }
    end)
  end)

test_case_runs
|> Enum.chunk_every(1000)
|> Enum.each(fn chunk ->
  IngestRepo.insert_all(Tuist.Runs.TestCaseRun, chunk)
end)

# Generate test case failures for failed test cases
test_case_failures =
  test_case_runs
  |> Enum.filter(&(&1.status == 1))
  |> Enum.flat_map(fn test_case_run ->
    # Each failed test case has 1-3 failures
    failure_count = Enum.random(1..3)

    Enum.map(1..failure_count, fn _ ->
      issue_type = Enum.random(["error_thrown", "assertion_failure"])
      message = Enum.random(failure_messages)
      path = Enum.random(paths)
      line_number = Enum.random(10..500)

      %{
        id: UUIDv7.generate(),
        test_case_run_id: test_case_run.id,
        message: message,
        path: path,
        line_number: line_number,
        issue_type: issue_type,
        inserted_at: test_case_run.inserted_at
      }
    end)
  end)

test_case_failures
|> Enum.chunk_every(1000)
|> Enum.each(fn chunk ->
  IngestRepo.insert_all(Tuist.Runs.TestCaseFailure, chunk)
end)

command_events =
  Enum.map(1..8000, fn _event ->
    names = ["test", "cache", "generate"]
    name = Enum.random(names)
    status = Enum.random([0, 1])
    is_ci = Enum.random([true, false])
    user_id = if is_ci, do: nil, else: user.id

    cacheable_targets = [
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

    remote_cache_target_hits = Enum.take(cacheable_targets, Enum.random(0..14))

    local_cache_target_hits =
      cacheable_targets
      |> Enum.reverse()
      |> Enum.take(Enum.random(0..(14 - length(remote_cache_target_hits))))

    test_targets =
      if name == "test" do
        [
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
      else
        []
      end

    remote_test_target_hits = Enum.take(test_targets, Enum.random(0..14))

    local_test_target_hits =
      test_targets
      |> Enum.reverse()
      |> Enum.take(Enum.random(0..(14 - length(remote_test_target_hits))))

    created_at =
      NaiveDateTime.new!(
        Date.add(DateTime.utc_now(), -Enum.random(0..400)),
        Time.new!(
          Enum.random(0..23),
          Enum.random(0..59),
          Enum.random(0..59),
          Enum.random(0..999_999)
        )
      )

    ran_at = created_at

    %{
      id: UUIDv7.generate(),
      name: name,
      duration: Enum.random(10_000..100_000),
      tuist_version: "4.1.0",
      project_id: tuist_project.id,
      cacheable_targets: cacheable_targets,
      local_cache_target_hits: local_cache_target_hits,
      remote_cache_target_hits: remote_cache_target_hits,
      test_targets: test_targets,
      local_test_target_hits: local_test_target_hits,
      remote_test_target_hits: remote_test_target_hits,
      swift_version: "5.2",
      macos_version: "10.15",
      subcommand: "",
      command_arguments: "",
      is_ci: is_ci,
      user_id: user_id,
      client_id: "client-id",
      status: status,
      error_message: nil,
      preview_id: nil,
      git_ref: nil,
      git_commit_sha: nil,
      git_branch: nil,
      created_at: created_at,
      updated_at: created_at,
      ran_at: ran_at,
      build_run_id: nil
    }
  end)

command_events
|> Enum.chunk_every(1000)
|> Enum.each(fn chunk ->
  IngestRepo.insert_all(Event, chunk)
end)

# Generate XcodeGraphs for generate command events (for Compilation Optimizations tab)
generate_events = Enum.filter(command_events, fn event -> event.name == "generate" end)

project_names = [
  "App",
  "Framework",
  "Core",
  "UI",
  "Networking",
  "Database",
  "Analytics",
  "Authentication"
]

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

generate_hash = fn ->
  1..64
  |> Enum.map(fn _ -> Enum.random(~c"0123456789abcdef") end)
  |> List.to_string()
end

xcode_graphs_data =
  generate_events
  |> Enum.take(100)
  |> Enum.map(fn event ->
    xcode_graph_id = UUIDv7.generate()
    inserted_at = NaiveDateTime.truncate(event.created_at, :second)

    %{
      id: xcode_graph_id,
      name: "Workspace",
      command_event_id: event.id,
      binary_build_duration: Enum.random(10_000..300_000),
      inserted_at: inserted_at,
      event: event
    }
  end)

xcode_graphs_data
|> Enum.map(fn graph ->
  Map.delete(graph, :event)
end)
|> Enum.chunk_every(1000)
|> Enum.each(fn chunk ->
  IngestRepo.insert_all(Tuist.Xcode.XcodeGraph, chunk)
end)

xcode_projects_data =
  Enum.flat_map(xcode_graphs_data, fn graph ->
    project_count = Enum.random(2..5)

    Enum.map(1..project_count, fn i ->
      project_name = Enum.at(project_names, rem(i - 1, length(project_names)))

      %{
        id: UUIDv7.generate(),
        name: project_name,
        path: "/#{project_name}/#{project_name}.xcodeproj",
        xcode_graph_id: graph.id,
        command_event_id: graph.event.id,
        inserted_at: graph.inserted_at
      }
    end)
  end)

xcode_projects_data
|> Enum.chunk_every(50)
|> Enum.each(fn chunk ->
  IngestRepo.insert_all(Tuist.Xcode.XcodeProject, chunk)
end)

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

destination_types = [
  "iphone",
  "ipad",
  "mac",
  "apple_watch",
  "apple_tv",
  "apple_vision"
]

generate_subhash = fn ->
  1..32
  |> Enum.map(fn _ -> Enum.random(~c"0123456789abcdef") end)
  |> List.to_string()
end

xcode_targets_data =
  Enum.flat_map(xcode_projects_data, fn project ->
    target_count = Enum.random(3..8)

    Enum.map(1..target_count, fn i ->
      target_name = Enum.at(target_names, rem(i - 1, length(target_names)))

      binary_cache_hit = Enum.random([:miss, :local, :remote])

      hit_value =
        case binary_cache_hit do
          :miss -> 0
          :local -> 1
          :remote -> 2
        end

      # Randomly decide if this is an external target (10% chance)
      is_external = Enum.random(1..10) == 1

      # Generate random destinations (1-3)
      destinations = Enum.take_random(destination_types, Enum.random(1..3))

      # Generate random additional strings (0-3)
      additional_strings =
        if Enum.random([true, false]) do
          Enum.map(1..Enum.random(1..3), fn _ ->
            "CUSTOM_FLAG_#{Enum.random(1..100)}"
          end)
        else
          []
        end

      %{
        id: UUIDv7.generate(),
        name: "#{project.name}_#{target_name}",
        binary_cache_hash: generate_hash.(),
        binary_cache_hit: hit_value,
        binary_build_duration: Enum.random(1000..30_000),
        selective_testing_hash: nil,
        selective_testing_hit: 0,
        xcode_project_id: project.id,
        command_event_id: project.command_event_id,
        inserted_at: project.inserted_at,
        product: Enum.random(product_types),
        bundle_id: "com.tuist.#{String.downcase(project.name)}.#{String.downcase(target_name)}",
        product_name: target_name,
        destinations: destinations,
        # Subhashes
        external_hash: if(is_external, do: generate_subhash.(), else: ""),
        sources_hash: if(is_external, do: "", else: generate_subhash.()),
        resources_hash: if(not is_external and Enum.random([true, false]), do: generate_subhash.(), else: ""),
        copy_files_hash: if(not is_external and Enum.random([true, false, false]), do: generate_subhash.(), else: ""),
        core_data_models_hash:
          if(not is_external and Enum.random([true, false, false, false]), do: generate_subhash.(), else: ""),
        target_scripts_hash: if(not is_external and Enum.random([true, false, false]), do: generate_subhash.(), else: ""),
        environment_hash: if(is_external, do: "", else: generate_subhash.()),
        headers_hash: if(not is_external and Enum.random([true, false, false]), do: generate_subhash.(), else: ""),
        deployment_target_hash: if(is_external, do: "", else: generate_subhash.()),
        info_plist_hash: if(not is_external and Enum.random([true, false]), do: generate_subhash.(), else: ""),
        entitlements_hash: if(not is_external and Enum.random([true, false, false]), do: generate_subhash.(), else: ""),
        dependencies_hash: if(is_external, do: "", else: generate_subhash.()),
        project_settings_hash: if(is_external, do: "", else: generate_subhash.()),
        target_settings_hash: if(is_external, do: "", else: generate_subhash.()),
        buildable_folders_hash:
          if(not is_external and Enum.random([true, false, false, false]), do: generate_subhash.(), else: ""),
        additional_strings: additional_strings
      }
    end)
  end)

xcode_targets_data
|> Enum.chunk_every(50)
|> Enum.each(fn chunk ->
  IngestRepo.insert_all(Tuist.Xcode.XcodeTarget, chunk)
end)

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

test_previews =
  Enum.map(1..40, fn _index ->
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

  IngestRepo.insert_all(Log, processed_logs)
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

Enum.map(1..20, fn index ->
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
