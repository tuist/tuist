defmodule TuistCloud.AccountsTest do
  alias TuistCloud.Accounts
  alias TuistCloud.AccountsFixtures
  use TuistCloud.DataCase

  test "admin? returns false if the user is not an admin" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()

    # When
    assert Accounts.admin?(user, organization) == false
  end

  test "admin? returns true if the user is the admin of the organization" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    Accounts.add_user_to_organization(user, organization, :admin)

    # When
    assert Accounts.admin?(user, organization) == true
  end

  test "user? returns false if the user is not an admin" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()

    # When
    assert Accounts.user?(user, organization) == false
  end

  test "user? returns true if the user is user of the organization" do
    # Given
    user = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture()
    Accounts.add_user_to_organization(user, organization, :user)

    # When
    assert Accounts.user?(user, organization) == true
  end
end
