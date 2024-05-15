alias TuistCloud.Accounts
alias TuistCloud.Projects
alias TuistCloud.CommandEvents

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

for _event <- 1..10000 do
  names = ["build", "test", "cache", "generate"]
  name = Enum.random(names)
  cacheable_targets = ["A", "B", "C", "D", "E", "F"]
  remote_cache_target_hits = Enum.take(cacheable_targets, Enum.random(0..5))

  CommandEvents.create_command_event(
    %{
      name: name,
      duration: Enum.random(10000..100_000),
      tuist_version: "4.1.0",
      project_id: tuist_cloud_acceptance_tests_project.id,
      cacheable_targets: cacheable_targets,
      local_cache_target_hits: [""],
      remote_cache_target_hits: remote_cache_target_hits,
      swift_version: "5.2",
      macos_version: "10.15",
      subcommand: "",
      command_arguments: [],
      is_ci: false,
      client_id: "client-id"
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
