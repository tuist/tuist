defmodule Tuist.ProjectsFixtures do
  @moduledoc false

  import Tuist.TestUtilities
  alias Tuist.Repo
  alias Tuist.Projects

  def project_fixture(opts \\ []) do
    account_id =
      Keyword.get_lazy(opts, :account_id, fn ->
        organization_id = Tuist.AccountsFixtures.organization_fixture().id

        Repo.get_by!(Tuist.Accounts.Account,
          organization_id: organization_id
        ).id
      end)

    name = Keyword.get(opts, :name, "#{unique_integer()}")
    created_at = Keyword.get(opts, :created_at, DateTime.utc_now())
    preloads = Keyword.get(opts, :preloads, [])

    Projects.create_project(
      %{
        name: name,
        account: %{id: account_id}
      },
      created_at: created_at,
      visibility: Keyword.get(opts, :visibility, :private),
      vcs_provider: Keyword.get(opts, :vcs_provider),
      vcs_repository_full_handle: Keyword.get(opts, :vcs_repository_full_handle),
      preloads: preloads
    )
    |> Repo.preload(Keyword.get(opts, :preloads, []))
  end
end
