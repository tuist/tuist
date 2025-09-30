defmodule Tuist.GitHubAppInstallations.GitHubAppInstallationTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.GitHubAppInstallations.GitHubAppInstallation
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "changeset/2" do
    test "is valid with valid attributes" do
      # Given
      account = AccountsFixtures.account_fixture()

      # When
      changeset =
        GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
          account_id: account.id,
          installation_id: "12345"
        })

      # Then
      assert changeset.valid?
    end

    test "is invalid without account_id" do
      # When
      changeset =
        GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
          installation_id: "12345"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).account_id
    end

    test "is invalid without installation_id" do
      # Given
      account = AccountsFixtures.account_fixture()

      # When
      changeset =
        GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
          account_id: account.id
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).installation_id
    end

    test "is invalid with non-existent account_id" do
      # Given
      non_existent_id = 99_999

      # When
      changeset =
        GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
          account_id: non_existent_id,
          installation_id: "12345"
        })

      # Then
      assert changeset.valid?

      # When
      assert {:error, changeset_with_error} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset_with_error).account_id
    end

    test "enforces unique constraint on account_id" do
      # Given
      account = AccountsFixtures.account_fixture()

      {:ok, _existing_installation} =
        Repo.insert(
          GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
            account_id: account.id,
            installation_id: "12345"
          })
        )

      # When
      changeset =
        GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
          account_id: account.id,
          installation_id: "67890"
        })

      # Then
      assert {:error, changeset_with_error} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset_with_error).account_id
    end

    test "enforces unique constraint on installation_id" do
      # Given
      account1 = AccountsFixtures.account_fixture()
      account2 = AccountsFixtures.account_fixture()

      {:ok, _existing_installation} =
        Repo.insert(
          GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
            account_id: account1.id,
            installation_id: "12345"
          })
        )

      # When
      changeset =
        GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
          account_id: account2.id,
          installation_id: "12345"
        })

      # Then
      assert {:error, changeset_with_error} = Repo.insert(changeset)
      assert "has already been taken" in errors_on(changeset_with_error).installation_id
    end
  end

  describe "update_changeset/2" do
    test "is valid with html_url" do
      # Given
      account = AccountsFixtures.account_fixture()

      {:ok, installation} =
        Repo.insert(
          GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
            account_id: account.id,
            installation_id: "12345"
          })
        )

      # When
      changeset =
        GitHubAppInstallation.update_changeset(installation, %{
          html_url: "https://github.com/settings/installations/12345"
        })

      # Then
      assert changeset.valid?
    end

    test "is valid without any attributes" do
      # Given
      account = AccountsFixtures.account_fixture()

      {:ok, installation} =
        Repo.insert(
          GitHubAppInstallation.changeset(%GitHubAppInstallation{}, %{
            account_id: account.id,
            installation_id: "12345"
          })
        )

      # When
      changeset = GitHubAppInstallation.update_changeset(installation, %{})

      # Then
      assert changeset.valid?
    end
  end
end
