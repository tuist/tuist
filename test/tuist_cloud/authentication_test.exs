defmodule TuistCloud.AuthenticationTest do
  use TuistCloud.DataCase
  alias TuistCloud.Authentication
  alias TuistCloud.TestUtilities
  alias TuistCloud.AccountsFixtures

  test "authenticated_subject returns nil if the project or user associated to the token doesn't exist" do
    # Given
    token = TestUtilities.unique_integer() |> Integer.to_string()

    # When
    result = Authentication.authenticated_subject(token)

    # Then
    assert result == nil
  end

  test "authenticated_subject returns the user associated to the token" do
    # Given
    user = AccountsFixtures.user_fixture()

    # When/Then
    assert Authentication.authenticated_subject(user.token) == {:user, user}
  end

  test "authenticated_subject returns the project associated to the token" do
    # Given
    project = TuistCloud.ProjectsFixtures.project_fixture()

    # When/Then
    assert Authentication.authenticated_subject(project.token) == {:project, project}
  end
end
