alias Tuist.Accounts
alias Tuist.Projects
alias Tuist.Projects.Project
alias Tuist.CommandEvents
import Ecto.Query, only: [from: 2]

# Stubs
email = "tuistrocks@tuist.io"
password = "tuistrocks"

account =
  Accounts.get_user_by_email(email)

account =
  if is_nil(account) do
    {:ok, account} =
      Accounts.create_user(email,
        password: password,
        confirmed_at: NaiveDateTime.utc_now(),
        setup_billing: false
      )

    account
  else
    account
  end

user = Accounts.get_user_by_email(email)

_public_project =
  case Projects.get_project_by_slug("tuist/public") do
    {:ok, %Project{} = project} ->
      project

    {:error, _} ->
      Projects.create_project(%{name: "public", account: %{id: account.id}},
        token: "public",
        visibility: :public
      )
  end

org_account =
  if Accounts.get_organization_account_by_name("tuist") do
    Accounts.get_organization_account_by_name("tuist")
  else
    organization =
      Accounts.create_organization(%{name: "tuist", creator: user}, setup_billing: false)
      |> Tuist.Repo.preload(:account)

    organization.account
  end

tuist_cloud_acceptance_tests_project =
  with {:ok, project} <- Projects.get_project_by_slug("tuist/ios_app_with_frameworks") do
    project
  else
    {:error, _} ->
      Projects.create_project(%{name: "ios_app_with_frameworks", account: %{id: org_account.id}})
  end

_org_project =
  Projects.get_project_by_slug("tuist/tuist") ||
    Projects.create_project(%{name: "tuist", account: %{id: org_account.id}})

for _event <- 1..10000 do
  names = ["build", "test", "cache", "generate"]
  name = Enum.random(names)
  status = Enum.random([:success, :failure])
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

  CommandEvents.create_command_event(%{
    name: name,
    duration: Enum.random(10000..100_000),
    tuist_version: "4.1.0",
    project_id: tuist_cloud_acceptance_tests_project.id,
    cacheable_targets: cacheable_targets,
    local_cache_target_hits: local_cache_target_hits,
    remote_cache_target_hits: remote_cache_target_hits,
    test_targets: test_targets,
    local_test_target_hits: local_test_target_hits,
    remote_test_target_hits: remote_test_target_hits,
    swift_version: "5.2",
    macos_version: "10.15",
    subcommand: "",
    command_arguments: [],
    is_ci: is_ci,
    user_id: user_id,
    client_id: "client-id",
    status: status,
    error_message: nil,
    preview_id: nil,
    git_ref: nil,
    git_commit_sha: nil,
    git_branch: nil,
    created_at:
      NaiveDateTime.new!(
        Date.add(DateTime.utc_now(), -Enum.random(0..400)),
        Time.new!(
          Enum.random(0..23),
          Enum.random(0..59),
          Enum.random(0..59),
          Enum.random(0..999_999)
        )
      )
  })
end

test_command_events =
  from(c in CommandEvents.Event, where: c.name == "test") |> Tuist.Repo.all()

test_cases =
  1..100
  |> Enum.map(fn index ->
    name = "test#{index}"

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
            project_id: tuist_cloud_acceptance_tests_project.id
          },
          flaky: Enum.random([true, false, false, false, false])
        )
      else
        test_case
      end

    for test_case_run_index <- 1..100 do
      CommandEvents.create_test_case_run(
        %{
          module_hash: "module-hash-#{test_case_run_index}",
          status: Enum.random([:success, :failure]),
          test_case_id: test_case.id,
          command_event_id: Enum.random(test_command_events).id
        },
        flaky: Enum.random([test_case.flaky, false, false, false])
      )
    end
  end)
