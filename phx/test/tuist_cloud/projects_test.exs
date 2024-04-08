defmodule TuistCloud.ProjectsTest do
  alias TuistCloud.AccountsFixtures
  alias TuistCloud.ProjectsFixtures
  alias TuistCloud.Projects
  alias TuistCloud.Accounts
  use TuistCloud.DataCase

  test "returns command average duration" do
    # Given
    organization = AccountsFixtures.organization_fixture(name: "tuist")
    account = Accounts.get_account_from_organization(organization)
    project = ProjectsFixtures.project_fixture(name: "tuist-project", account_id: account.id)

    # When
    got = Projects.get_project_by_slug("tuist/tuist-project")

    # Then
    assert got == project
  end
end
