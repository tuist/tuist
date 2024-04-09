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

tuist_cloud_acceptance_tests_project =
  Projects.get_project_by_slug("tuist/tuist-cloud-acceptance-tests") ||
    Projects.create_project(%{name: "tuist-cloud-acceptance-tests", account: %{id: account.id}},
      token: "tuist-cloud-acceptance-tests"
    )

CommandEvents.create_command_event(%{
  name: "build",
  duration: 20000,
  tuist_version: "4.1.0",
  project: %{id: tuist_cloud_acceptance_tests_project.id},
  cacheable_targets: "A;B",
  local_cache_target_hits: "",
  remote_cache_target_hits: "B",
  created_at: Time.utc_now()
})

CommandEvents.create_command_event(%{
  name: "build",
  duration: 34000,
  tuist_version: "4.1.0",
  project: %{id: tuist_cloud_acceptance_tests_project.id},
  cacheable_targets: "A;B;C",
  local_cache_target_hits: "",
  remote_cache_target_hits: "B",
  created_at: NaiveDateTime.new!(Date.add(Time.utc_now(), -1), ~T[14:00:00.000])
})

CommandEvents.create_command_event(%{
  name: "build",
  duration: 41000,
  tuist_version: "4.1.0",
  project: %{id: tuist_cloud_acceptance_tests_project.id},
  cacheable_targets: "A;B;C",
  local_cache_target_hits: "",
  remote_cache_target_hits: "B",
  created_at: NaiveDateTime.new!(Date.add(Time.utc_now(), -6), ~T[14:00:00.000])
})

CommandEvents.create_command_event(%{
  name: "build",
  duration: 78000,
  tuist_version: "4.1.0",
  project: %{id: tuist_cloud_acceptance_tests_project.id},
  cacheable_targets: "A;B;C",
  local_cache_target_hits: "",
  remote_cache_target_hits: "B",
  created_at: NaiveDateTime.new!(Date.add(Time.utc_now(), -32), ~T[14:00:00.000])
})
