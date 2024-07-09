defmodule TuistCloud.ProjectsFixtures do
  @moduledoc false

  import TuistCloud.TestUtilities
  alias TuistCloud.Repo
  alias TuistCloud.Projects

  def project_fixture(opts \\ []) do
    account_id =
      Keyword.get_lazy(opts, :account_id, fn ->
        organization_id = TuistCloud.AccountsFixtures.organization_fixture().id

        Repo.get_by!(TuistCloud.Accounts.Account,
          organization_id: organization_id
        ).id
      end)

    name = Keyword.get(opts, :name, "#{unique_integer()}")
    created_at = Keyword.get(opts, :created_at, DateTime.utc_now())

    Projects.create_project(
      %{
        name: name,
        account: %{id: account_id}
      },
      created_at: created_at,
      visibility: Keyword.get(opts, :visibility, :private)
    )
    |> Repo.preload(Keyword.get(opts, :preloads, []))
  end
end
