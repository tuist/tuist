defmodule TuistTestSupport.Fixtures.ProjectsFixtures do
  @moduledoc false

  alias Tuist.Projects
  alias Tuist.Repo

  def project_fixture(opts \\ []) do
    account_id =
      Keyword.get_lazy(opts, :account_id, fn ->
        organization_id = TuistTestSupport.Fixtures.AccountsFixtures.organization_fixture().id

        Repo.get_by!(Tuist.Accounts.Account,
          organization_id: organization_id
        ).id
      end)

    name = Keyword.get(opts, :name, "#{TuistTestSupport.Utilities.unique_integer()}")
    created_at = Keyword.get(opts, :created_at, DateTime.utc_now())
    preload = Keyword.get(opts, :preload, [:account])

    %{
      name: name,
      account: %{id: account_id}
    }
    |> Projects.create_project!(
      created_at: created_at,
      visibility: Keyword.get(opts, :visibility, :private),
      vcs_provider: Keyword.get(opts, :vcs_provider),
      vcs_repository_full_handle: Keyword.get(opts, :vcs_repository_full_handle),
      default_previews_visibility: Keyword.get(opts, :default_previews_visibility, :private),
      preload: preload
    )
    |> Repo.preload(Keyword.get(opts, :preload, []))
  end
end
