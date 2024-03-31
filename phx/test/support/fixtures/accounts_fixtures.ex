defmodule TuistCloud.AccountsFixtures do
  @moduledoc false

  alias TuistCloud.Accounts
  alias TuistCloud.TestUtilities

  def user_fixture() do
    Accounts.create_user("#{TestUtilities.unique_integer()}@cloud.tuist.io")
  end

  def organization_fixture() do
    Accounts.create_organization(%{name: "#{TestUtilities.unique_integer()}"})
  end
end
