defmodule TuistCloud.ProjectsFixtures do
  @moduledoc false

  import TuistCloud.TestUtilities
  alias TuistCloud.Repo
  alias TuistCloud.Projects
  alias TuistCloud.Projects.Project

  @spec project_fixture(attrs :: [{:account_id, String.t()}]) :: Project.t()
  def project_fixture(attrs \\ []) do
    account_id =
      Keyword.get_lazy(attrs, :account_id, fn ->
        organization_id = TuistCloud.AccountsFixtures.organization_fixture().id

        Repo.get_by!(TuistCloud.Accounts.Account,
          owner_type: "Organization",
          owner_id: organization_id
        ).id
      end)

    Projects.create_project(%{
      name: "#{unique_integer()}",
      account: %{id: account_id}
    })
  end
end
