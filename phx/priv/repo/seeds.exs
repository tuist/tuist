alias TuistCloud.Accounts
alias TuistCloud.Projects

email = "tuist@tuist.io"
password = "tuistrocks"

account =
  Accounts.get_user_by_email(email) ||
    Accounts.create_user(email, password: password, confirmed_at: NaiveDateTime.utc_now())

_tuist_project =
  Projects.get_project_by_slug("tuist/tuist") ||
    Projects.create_project(%{name: "tuist", account: %{id: account.id}}, token: "tuist")

_tuist_cloud_acceptance_tests_project =
  Projects.get_project_by_slug("tuist/tuist-cloud-acceptance-tests") ||
    Projects.create_project(%{name: "tuist-cloud-acceptance-tests", account: %{id: account.id}},
      token: "tuist-cloud-acceptance-tests"
    )
