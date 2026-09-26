# Seeds a side-by-side view: one Xcode build and one Mix (Elixir) build,
# both under the local dev tuistrocks user, so the two dashboard overview
# pages can be compared. Idempotent-ish: reuses the tuistrocks user and its
# project if they already exist, otherwise creates them.
#
# Run with `mix run priv/repo/seed_mix_analytics.exs`.

alias Tuist.Accounts
alias Tuist.Builds, as: Builds
alias Tuist.CommandEvents
alias Tuist.Mix, as: MixAnalytics
alias Tuist.Projects
alias Tuist.Projects.Project
alias Tuist.Repo

email = "tuistrocks@tuist.dev"

user =
  case Accounts.get_user_by_email(email) do
    {:ok, user} ->
      user

    {:error, :not_found} ->
      {:ok, user} =
        Accounts.create_user(email,
          password: "tuistrocks",
          confirmed_at: NaiveDateTime.utc_now(),
          setup_billing: false
        )

      user
  end

user = Repo.preload(user, :account)
account = user.account

project =
  Repo.get_by(Project, account_id: account.id, name: "analytics-demo") ||
    Projects.create_project!(%{name: "analytics-demo", account: %{id: account.id}}, build_system: :xcode)

now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)

xcode_build_id = UUIDv7.generate()

{:ok, xcode_build} =
  Builds.create_build(%{
    id: xcode_build_id,
    project_id: project.id,
    account_id: account.id,
    duration: 152_340,
    macos_version: "26.0",
    xcode_version: "16.2",
    is_ci: true,
    model_identifier: "MacBookPro18,3",
    scheme: "App",
    configuration: "Debug",
    status: "success",
    category: "incremental",
    git_branch: "main",
    git_commit_sha: "deadbeefcafefacefeedcafedeadbeefcafefeed",
    git_ref: "refs/heads/main",
    git_remote_url_origin: "git@github.com:tuistrocks/analytics-demo.git",
    ci_provider: "github",
    ci_run_id: "12345",
    ci_project_handle: "tuistrocks/analytics-demo",
    custom_tags: ["nightly", "release"],
    custom_values: %{"ticket" => "PROJ-42"},
    ran_at: now
  })

# Seed a couple of Xcode issues so the "Errors and Warnings" card renders.
Tuist.IngestRepo.insert_all(Tuist.Builds.BuildIssue, [
  %{
    build_run_id: xcode_build.id,
    type: "warning",
    target: "App",
    project: "App",
    title: "Unused variable 'foo'",
    signature: "warn-1",
    step_type: "swift_compilation",
    path: "Sources/App/Foo.swift",
    message: "Initialization of immutable value 'foo' was never used",
    starting_line: 12,
    ending_line: 12,
    starting_column: 5,
    ending_column: 8,
    inserted_at: DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.truncate(:second)
  }
])

mix_build_id = UUIDv7.generate()

{:ok, ^mix_build_id} =
  MixAnalytics.create_build(%{
    id: mix_build_id,
    project_id: project.id,
    account_id: account.id,
    duration_ms: 24_180,
    status: "failure",
    is_ci: true,
    elixir_version: "1.20.2",
    otp_version: "29",
    mix_env: "test",
    git_branch: "main",
    git_commit_sha: "deadbeefcafefacefeedcafedeadbeefcafefeed",
    git_ref: "refs/heads/main",
    git_remote_url_origin: "git@github.com:tuistrocks/analytics-demo.git",
    ci_provider: "github",
    ci_run_id: "12345",
    ci_project_handle: "tuistrocks/analytics-demo",
    ci_host: "https://github.com",
    contract_version: "0.1",
    custom_tags: ["nightly", "release"],
    custom_values: %{"ticket" => "PROJ-42"},
    started_at: now,
    diagnostics: [
      %{
        severity: "warning",
        file: "lib/greeter.ex",
        module: "Greeter",
        message: "variable \"name\" is unused (if the variable is not meant to be used, prefix it with an underscore)",
        line: 12,
        column: 5,
        compiler: "elixir"
      },
      %{
        severity: "warning",
        file: "lib/greeter.ex",
        module: "Greeter",
        message: "function greet_all/0 is unused",
        line: 20,
        column: 3,
        compiler: "elixir"
      },
      %{
        severity: "error",
        file: "lib/parser.ex",
        module: "Parser",
        message: "undefined function tokenize/1",
        line: 44,
        column: 10,
        compiler: "elixir"
      }
    ],
    machine_metrics:
      for i <- 0..5 do
        %{
          timestamp: :os.system_time(:millisecond) / 1_000 + i,
          cpu_usage_percent: 30.0 + i * 5.0,
          memory_used_bytes: 4_500_000_000 + i * 200_000_000,
          memory_total_bytes: 16_000_000_000,
          network_bytes_in: 0,
          network_bytes_out: 0,
          disk_bytes_read: 0,
          disk_bytes_written: 0
        }
      end
  })

# Force a flush so every row is visible immediately for the dashboard
Tuist.Mix.Build.Buffer.flush()
Tuist.Mix.Diagnostic.Buffer.flush()
Tuist.Builds.BuildMachineMetric.Buffer.flush()

base = "#{Tuist.Environment.app_url(route_type: :app)}/#{account.name}/#{project.name}"

IO.puts("")
IO.puts("Seeded side-by-side analytics runs for #{account.name}/#{project.name}")
IO.puts("  Xcode build overview: #{base}/builds/build-runs/#{xcode_build.id}")
IO.puts("  Mix build overview:   #{base}/builds/mix-builds/#{mix_build_id}")
IO.puts("")
