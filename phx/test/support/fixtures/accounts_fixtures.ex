defmodule TuistCloud.AccountsFixtures do
  @moduledoc false

  alias TuistCloud.Accounts
  alias TuistCloud.TestUtilities

  def user_fixture(opts \\ []) do
    email = Keyword.get(opts, :email, "#{TestUtilities.unique_integer()}@cloud.tuist.io")
    Accounts.create_user(email)
  end

  def organization_fixture(opts \\ []) do
    name = Keyword.get(opts, :name, "#{TestUtilities.unique_integer()}")
    Accounts.create_organization(%{name: name})
  end
end
