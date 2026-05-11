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

    attrs =
      %{
        account_id: Keyword.get(opts, :account_id, account.account.id),
        installation_id:
          if Keyword.has_key?(opts, :installation_id) do
            Keyword.get(opts, :installation_id)
          else
            "#{TuistTestSupport.Utilities.unique_integer()}"
          end,
        html_url: Keyword.get(opts, :html_url),
        client_url: Keyword.get(opts, :client_url),
        app_id: Keyword.get(opts, :app_id),
        app_slug: Keyword.get(opts, :app_slug),
        client_id: Keyword.get(opts, :client_id),
        client_secret: Keyword.get(opts, :client_secret),
        private_key: Keyword.get(opts, :private_key),
        webhook_secret: Keyword.get(opts, :webhook_secret)
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Map.new()

    %GitHubAppInstallation{}
    |> GitHubAppInstallation.changeset(attrs)
    |> Repo.insert!()
    |> Repo.preload(Keyword.get(opts, :preload, []))
  end
end
