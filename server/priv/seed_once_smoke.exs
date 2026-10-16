# Seed a Once smoke-test project and mint an account token so the local
# reporter can post invocation summaries against the running dev server.
# Run in an already-started node with:
#   MIX_ENV=dev mix run priv/seed_once_smoke.exs
alias Tuist.Accounts
alias Tuist.Projects
alias Tuist.Repo

email = "once-smoke@tuist.dev"

user =
  case Accounts.get_user_by_email(email) do
    {:error, :not_found} ->
      {:ok, user} = Accounts.create_user(email, password: "tuistrocks")
      user

    {:ok, user} ->
      user
  end

user = Repo.preload(user, :account)
account = user.account

project =
  case Repo.get_by(Projects.Project, name: "mise-once", account_id: account.id) do
    nil ->
      {:ok, project} =
        Projects.create_project(%{name: "mise-once", account: account}, build_system: :once)

      project

    project ->
      project
  end

{:ok, {_token, full_token}} =
  Accounts.create_account_token(%{
    account: account,
    scopes: ["ci"],
    name: "once-smoke",
    all_projects: true
  })

IO.puts("SMOKE_TUIST_URL=http://localhost:8285")
IO.puts("SMOKE_ACCOUNT_HANDLE=#{account.name}")
IO.puts("SMOKE_PROJECT_HANDLE=#{project.name}")
IO.puts("SMOKE_PROJECT_ID=#{project.id}")
IO.puts("SMOKE_ACCOUNT_TOKEN=#{full_token}")
