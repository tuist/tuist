alias TuistCloud.Accounts
alias TuistCloud.Projects
alias TuistCloud.CommandEvents
alias TuistCloud.Time

email = "tuist@tuist.io"
password = "tuistrocks"

account =
  Accounts.get_user_by_email(email) ||
    Accounts.create_user(email, password: password, confirmed_at: NaiveDateTime.utc_now())

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

CommandEvents.create_command_event(%{
  name: "build",
  duration: 20000,
  tuist_version: "4.1.0",
  project_id: tuist_cloud_acceptance_tests_project.id,
  cacheable_targets: ["A", "B"],
  local_cache_target_hits: [""],
  remote_cache_target_hits: ["B"],
  swift_version: "5.2",
  macos_version: "10.15",
  subcommand: "",
  command_arguments: [],
  is_ci: false,
  client_id: "client-id",
  created_at: Time.utc_now()
})

CommandEvents.create_command_event(%{
  name: "build",
  duration: 34000,
  tuist_version: "4.1.0",
  project_id: tuist_cloud_acceptance_tests_project.id,
  cacheable_targets: ["A", "B", "C"],
  local_cache_target_hits: [""],
  remote_cache_target_hits: ["B"],
  swift_version: "5.2",
  macos_version: "10.15",
  subcommand: "",
  command_arguments: [],
  is_ci: false,
  client_id: "client-id",
  created_at: NaiveDateTime.new!(Date.add(Time.utc_now(), -1), ~T[14:00:00.000])
})

CommandEvents.create_command_event(%{
  name: "build",
  duration: 41000,
  tuist_version: "4.1.0",
  project_id: tuist_cloud_acceptance_tests_project.id,
  cacheable_targets: ["A", "B", "C"],
  local_cache_target_hits: [""],
  remote_cache_target_hits: ["B"],
  swift_version: "5.2",
  macos_version: "10.15",
  subcommand: "",
  command_arguments: [],
  is_ci: false,
  client_id: "client-id",
  created_at: NaiveDateTime.new!(Date.add(Time.utc_now(), -6), ~T[14:00:00.000])
})

CommandEvents.create_command_event(%{
  name: "build",
  duration: 78000,
  tuist_version: "4.1.0",
  project_id: tuist_cloud_acceptance_tests_project.id,
  cacheable_targets: ["A", "B", "C"],
  local_cache_target_hits: [""],
  remote_cache_target_hits: ["B"],
  swift_version: "5.2",
  macos_version: "10.15",
  subcommand: "",
  command_arguments: [],
  is_ci: false,
  client_id: "client-id",
  created_at: NaiveDateTime.new!(Date.add(Time.utc_now(), -32), ~T[14:00:00.000])
})
