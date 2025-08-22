alias Tuist.Accounts
alias Tuist.AppBuilds.AppBuild
alias Tuist.AppBuilds.Preview
alias Tuist.Billing
alias Tuist.Billing.Subscription
alias Tuist.CommandEvents
alias Tuist.CommandEvents.Clickhouse.Event
alias Tuist.IngestRepo
alias Tuist.Projects
alias Tuist.Projects.Project
alias Tuist.QA
alias Tuist.QA.Log
alias Tuist.QA.Run
alias Tuist.Repo
alias Tuist.Runs.Build
alias Tuist.Xcode

# Stubs
email = "tuistrocks@tuist.dev"
password = "tuistrocks"

FunWithFlags.enable(:clickhouse_events)

_account =
  if is_nil(Accounts.get_user_by_email(email)) do
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
  else
    Accounts.get_user_by_email(email)
  end

user = Accounts.get_user_by_email(email)

organization =
  if Accounts.get_organization_by_handle("tuist") do
    Accounts.get_organization_by_handle("tuist")
  else
    {:ok, organization} =
      Accounts.create_organization(%{name: "tuist", creator: user}, setup_billing: false)

    organization
  end

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
      inserted_at: inserted_at,
      status: status
    }
  end)

Repo.insert_all(Build, builds)

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
          Enum.random(0..999)
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

test_command_events =
  Enum.filter(command_events, &(&1.name == "test"))

test_command_events
|> Enum.shuffle()
|> Enum.take(100)
|> Enum.map(fn command_event ->
  name = "test#{System.unique_integer([:positive])}"

  module_name =
    Enum.random(["ModuleOne", "ModuleTwo", "ModuleThree", "ModuleFour", "ModuleFive"])

  identifier = "#{module_name}/#{name}"
  test_case = CommandEvents.get_test_case_by_identifier(identifier)

  test_case =
    if is_nil(test_case) do
      CommandEvents.create_test_case(
        %{
          name: name,
          module_name: module_name,
          identifier: identifier,
          project_identifier: "AppTests/AppTests.xcodeproj",
          project_id: tuist_project.id
        },
        flaky: Enum.random([true, false, false, false, false])
      )
    else
      test_case
    end

  {:ok, _graph} =
    Xcode.create_xcode_graph(%{
      command_event: command_event,
      xcode_graph: %{
        name: "Graph",
        binary_build_duration: Enum.random(1_000..1_800_000),
        projects: [
          %{
            "name" => name,
            "path" => module_name,
            "targets" => [
              %{
                "name" => "target-#{System.unique_integer([:positive])}",
                "binary_cache_metadata" => %{
                  "hash" => "binary-cache-hash-#{System.unique_integer([:positive])}",
                  "hit" => "miss"
                }
              }
            ]
          }
        ]
      }
    })

  Tuist.Xcode.XcodeGraph.Buffer.flush()
  Tuist.Xcode.XcodeProject.Buffer.flush()
  Tuist.Xcode.XcodeTarget.Buffer.flush()

  xcode_targets =
    command_event.id
    |> Xcode.xcode_targets_for_command_event()
    |> Enum.map(& &1.id)

  for _ <- 1..100 do
    CommandEvents.create_test_case_run(
      %{
        status: Enum.random([:success, :failure]),
        test_case_id: test_case.id,
        command_event_id: command_event.id,
        xcode_target_id: Enum.random(xcode_targets)
      },
      flaky: Enum.random([test_case.flaky, false, false, false])
    )
  end
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

branches = [
  "main",
  "develop",
  "feature/wearables",
  "feature/new-ui",
  "bugfix/crash-fix",
  "release/v2.0",
  "hotfix/security"
]

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

    %{
      display_name: "MyApp",
      bundle_identifier: bundle_identifier,
      version: version,
      supported_platforms: supported_platforms,
      git_branch: git_branch,
      git_commit_sha: git_commit_sha,
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

    app_build_attrs = %{
      preview_id: preview.id,
      type: build_type,
      supported_platforms: build_platforms
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

qa_summaries = [
  "All tests passed successfully. The app flows work as expected.",
  "Found minor UI issues in the onboarding flow. Overall functionality is good.",
  "Critical bug discovered in the payment process. Needs immediate attention.",
  "App performance is excellent. All accessibility features work correctly.",
  "Login functionality has some edge case issues that need addressing.",
  "Great user experience overall. Minor improvements suggested for navigation.",
  "App crashes when handling large datasets. Memory optimization needed.",
  "Perfect implementation of dark mode. All UI elements adapt correctly.",
  "Push notifications work but delivery timing could be improved.",
  "Offline mode works well but sync process could be faster."
]

selected_app_builds = Enum.take_random(app_builds, 25)

qa_runs =
  Enum.map(selected_app_builds, fn app_build ->
    status = Enum.random(qa_statuses)
    prompt = Enum.random(qa_prompts)

    git_refs = ["main", "develop", "feature/new-ui", "feature/qa-testing", "release/v1.2.0"]
    vcs_providers = [:github]

    repository_handles = [
      "tuist/tuist",
      "tuist/example-app",
      "tuist/ios-sample",
      "company/mobile-app",
      "org/customer-app"
    ]

    inserted_at =
      DateTime.new!(
        Date.add(DateTime.utc_now(), -Enum.random(0..30)),
        Time.new!(
          Enum.random(0..23),
          Enum.random(0..59),
          Enum.random(0..59)
        )
      )

    %{
      id: UUIDv7.generate(),
      app_build_id: app_build.id,
      prompt: prompt,
      status: status,
      vcs_repository_full_handle: Enum.random(repository_handles),
      vcs_provider: Enum.random(vcs_providers),
      git_ref: Enum.random(git_refs),
      issue_comment_id: if(Enum.random([true, false]), do: Enum.random(1000..9999)),
      inserted_at: inserted_at,
      updated_at: inserted_at
    }
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
