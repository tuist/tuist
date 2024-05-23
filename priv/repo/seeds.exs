alias TuistCloud.Accounts
alias TuistCloud.Projects
alias TuistCloud.CommandEvents

email = "tuist@tuist.io"
password = "tuistrocks"

account =
  Accounts.get_user_by_email(email) ||
    Accounts.create_user(email, password: password, confirmed_at: NaiveDateTime.utc_now())

user = Accounts.get_user_by_email(email)

_tuist_project =
  Projects.get_project_by_slug("tuist/tuist") ||
    Projects.create_project(%{name: "tuist", account: %{id: account.id}}, token: "tuist")

_tuist_project =
  with {:ok, project} <- Projects.get_project_by_slug("tuist/tuist") do
    project
  else
    {:error, _} ->
      Projects.create_project(%{name: "tuist", account: %{id: account.id}},
        token: "tuist"
      )
  end

tuist_cloud_acceptance_tests_project =
  with {:ok, project} <- Projects.get_project_by_slug("tuist/tuist-cloud-acceptance-tests") do
    project
  else
    {:error, _} ->
      Projects.create_project(%{name: "tuist-cloud-acceptance-tests", account: %{id: account.id}},
        token: "tuist-cloud-acceptance-tests"
      )
  end

org_account =
  if Accounts.get_organization_account_by_name("tuist-org") do
    Accounts.get_organization_account_by_name("tuist-org").organization
  else
    Accounts.create_organization(%{name: "tuist-org", creator: user})
  end

_org_project =
  Projects.get_project_by_slug("tuist-org/tuist") ||
    Projects.create_project(%{name: "tuist", account: %{id: org_account.id}}, token: "tuist")

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

  CommandEvents.create_command_event(
    %{
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
      error_message: nil
    },
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
  )
end
