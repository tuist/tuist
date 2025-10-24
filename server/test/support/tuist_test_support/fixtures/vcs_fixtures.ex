defmodule TuistTestSupport.Fixtures.VCSFixtures do
  @moduledoc false

  alias Tuist.Repo
  alias Tuist.VCS.GitHubAppInstallation
  alias TuistTestSupport.Fixtures.AccountsFixtures

  def github_app_installation_fixture(opts \\ []) do
    account =
      opts
      |> Keyword.get_lazy(:account, fn ->
        AccountsFixtures.user_fixture()
      end)
      |> Repo.preload([:account])

    %GitHubAppInstallation{}
    |> GitHubAppInstallation.changeset(%{
      account_id: Keyword.get(opts, :account_id, account.account.id),
      installation_id: Keyword.get(opts, :installation_id, "#{TuistTestSupport.Utilities.unique_integer()}"),
      html_url: Keyword.get(opts, :html_url)
    })
    |> Repo.insert!()
    |> Repo.preload(Keyword.get(opts, :preload, []))
  end
end
