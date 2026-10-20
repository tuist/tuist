defmodule Atlas.POCsFixtures do
  @moduledoc false

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.POCs
  alias Atlas.Repo

  def poc_fixture(user) do
    suffix = System.unique_integer([:positive])

    account =
      %Account{}
      |> Account.changeset(%{account_key: "poc-test:#{suffix}", name: "Example #{suffix}", segment: :prospect})
      |> Repo.insert!()

    {:ok, poc} = POCs.create_poc(%{"account_id" => account.id, "title" => "Platform evaluation"}, user)
    poc
  end
end
