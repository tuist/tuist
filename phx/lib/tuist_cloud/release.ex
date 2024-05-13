defmodule TuistCloud.Release do
  @moduledoc ~S"""
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :tuist_cloud

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end

  def backfill_customer_id do
    Application.ensure_all_started(@app)

    TuistCloud.Repo.all(TuistCloud.Accounts.Account)
    |> Enum.filter(fn account -> account.customer_id == nil end)
    |> Enum.each(&backfill_account_customer_id/1)
  end

  defp backfill_account_customer_id(account) do
    user =
      if account.owner_type == "Organization" do
        organization = TuistCloud.Accounts.get_organization_by_id(account.owner_id)

        members = TuistCloud.Accounts.get_organization_members(organization, :admin)

        if Enum.empty?(members) do
          nil
        else
          hd(members)
        end
      else
        TuistCloud.Accounts.get_user!(account.owner_id)
      end

    if !is_nil(user) do
      customer_id = TuistCloud.Billing.create_customer(%{name: account.name, email: user.email})

      account
      |> Ecto.Changeset.change(customer_id: customer_id)
      |> TuistCloud.Repo.update!()
    end
  end
end
