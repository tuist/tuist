defmodule Tuist.GitHubAppInstallationsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.GitHub.Client
  alias Tuist.GitHubAppInstallations
  alias Tuist.GitHubAppInstallations.GitHubAppInstallation
  alias Tuist.GitHubStateToken
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "get_by_installation_id/1" do
    test "returns the GitHub app installation when it exists" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "12345"

      {:ok, github_app_installation} =
        %GitHubAppInstallation{}
        |> GitHubAppInstallation.changeset(%{
          account_id: account.id,
          installation_id: installation_id
        })
        |> Repo.insert()

      # When
      result = GitHubAppInstallations.get_by_installation_id(installation_id)

      # Then
      assert {:ok, fetched_installation} = result
      assert fetched_installation.id == github_app_installation.id
      assert fetched_installation.installation_id == installation_id
      assert fetched_installation.account_id == account.id
    end

    test "returns error when GitHub app installation does not exist" do
      # Given
      non_existent_installation_id = "99999"

      # When
      result = GitHubAppInstallations.get_by_installation_id(non_existent_installation_id)

      # Then
      assert result == {:error, :not_found}
    end
  end

  describe "delete/1" do
    test "successfully deletes a GitHub app installation" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "67890"

      {:ok, github_app_installation} =
        %GitHubAppInstallation{}
        |> GitHubAppInstallation.changeset(%{
          account_id: account.id,
          installation_id: installation_id
        })
        |> Repo.insert()

      # When
      result = GitHubAppInstallations.delete(github_app_installation)

      # Then
      assert {:ok, deleted_installation} = result
      assert deleted_installation.id == github_app_installation.id

      # Verify it's actually deleted
      assert GitHubAppInstallations.get_by_installation_id(installation_id) == {:error, :not_found}
    end

    test "returns error when trying to delete stale installation" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account

      {:ok, github_app_installation} =
        %GitHubAppInstallation{}
        |> GitHubAppInstallation.changeset(%{
          account_id: account.id,
          installation_id: "temp-id"
        })
        |> Repo.insert()

      # Delete it first to make it stale
      {:ok, _} = Repo.delete(github_app_installation)

      # When
      result = GitHubAppInstallations.delete(github_app_installation)

      # Then
      assert {:error, changeset} = result
      assert changeset.errors[:id] == {"is stale", [stale: true]}
    end
  end

  describe "update/2" do
    test "successfully updates a GitHub app installation with html_url" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "11111"
      html_url = "https://github.com/organizations/tuist/settings/installations/11111"

      {:ok, github_app_installation} =
        %GitHubAppInstallation{}
        |> GitHubAppInstallation.changeset(%{
          account_id: account.id,
          installation_id: installation_id
        })
        |> Repo.insert()

      # When
      result = GitHubAppInstallations.update(github_app_installation, %{html_url: html_url})

      # Then
      assert {:ok, updated_installation} = result
      assert updated_installation.html_url == html_url
      assert updated_installation.installation_id == installation_id
      assert updated_installation.account_id == account.id
    end

    test "returns error with invalid data" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account

      {:ok, github_app_installation} =
        %GitHubAppInstallation{}
        |> GitHubAppInstallation.changeset(%{
          account_id: account.id,
          installation_id: "22222"
        })
        |> Repo.insert()

      # When
      result = GitHubAppInstallations.update(github_app_installation, %{html_url: 123})

      # Then
      assert {:error, changeset} = result
      assert changeset.errors[:html_url] == {"is invalid", [type: :string, validation: :cast]}
    end
  end

  describe "create/1" do
    test "successfully creates a GitHub app installation with valid attributes" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "54321"

      attrs = %{
        account_id: account.id,
        installation_id: installation_id
      }

      # When
      result = GitHubAppInstallations.create(attrs)

      # Then
      assert {:ok, github_app_installation} = result
      assert github_app_installation.account_id == account.id
      assert github_app_installation.installation_id == installation_id
    end
  end

  describe "get_repositories/1" do
    test "calls GitHub client with installation_id and returns repositories" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "repo_test_123"

      {:ok, github_app_installation} =
        GitHubAppInstallations.create(%{
          account_id: account.id,
          installation_id: installation_id
        })

      expected_repositories = [
        %{"name" => "repo1", "full_name" => "tuist/repo1"},
        %{"name" => "repo2", "full_name" => "tuist/repo2"}
      ]

      expect(Client, :get_installation_repositories, fn ^installation_id ->
        {:ok, expected_repositories}
      end)

      # When
      result = GitHubAppInstallations.get_repositories(github_app_installation)

      # Then
      assert {:ok, repositories} = result
      assert repositories == expected_repositories
    end

    test "returns error when GitHub client fails" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      installation_id = "error_test_456"

      {:ok, github_app_installation} =
        GitHubAppInstallations.create(%{
          account_id: account.id,
          installation_id: installation_id
        })

      error_message = "GitHub API error"

      expect(Client, :get_installation_repositories, fn ^installation_id ->
        {:error, error_message}
      end)

      # When
      result = GitHubAppInstallations.get_repositories(github_app_installation)

      # Then
      assert {:error, ^error_message} = result
    end
  end

  describe "get_github_app_installation_url/1" do
    test "generates GitHub app installation URL with state token for account" do
      # Given
      user = AccountsFixtures.user_fixture()
      account = user.account
      app_name = "test-tuist-app"
      state_token = "encrypted_state_token"

      expect(Tuist.Environment, :github_app_name, fn -> app_name end)

      expect(GitHubStateToken, :generate_token, fn account_id ->
        assert account_id == account.id
        state_token
      end)

      # When
      result = GitHubAppInstallations.get_github_app_installation_url(account)

      # Then
      expected_url = "https://github.com/apps/#{app_name}/installations/new?state=#{state_token}"
      assert result == expected_url
    end
  end
end
