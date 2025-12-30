defmodule Tuist.Accounts.AccountTokenProjectTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Accounts.AccountTokenProject
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  describe "create_changeset/1" do
    test "ensures account_token_id is present" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      got = AccountTokenProject.create_changeset(%{project_id: project.id})

      # Then
      assert "can't be blank" in errors_on(got).account_token_id
    end

    test "ensures project_id is present" do
      # Given
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      token = AccountsFixtures.account_token_fixture(account: account)

      # When
      got = AccountTokenProject.create_changeset(%{account_token_id: token.id})

      # Then
      assert "can't be blank" in errors_on(got).project_id
    end

    test "is valid when all required fields are present" do
      # Given
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      token = AccountsFixtures.account_token_fixture(account: account)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      # When
      got =
        AccountTokenProject.create_changeset(%{
          account_token_id: token.id,
          project_id: project.id
        })

      # Then
      assert got.valid?
    end

    test "enforces unique constraint on account_token_id and project_id" do
      # Given
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      token = AccountsFixtures.account_token_fixture(account: account)
      project = ProjectsFixtures.project_fixture(account_id: account.id)

      {:ok, _} =
        Repo.insert(
          AccountTokenProject.create_changeset(%{
            account_token_id: token.id,
            project_id: project.id
          })
        )

      # When
      {:error, got} =
        Repo.insert(
          AccountTokenProject.create_changeset(%{
            account_token_id: token.id,
            project_id: project.id
          })
        )

      # Then
      assert "has already been taken" in errors_on(got).account_token_id
    end

    test "enforces foreign key constraint on account_token_id" do
      # Given
      project = ProjectsFixtures.project_fixture()
      non_existent_token_id = UUIDv7.generate()

      # When
      {:error, got} =
        Repo.insert(
          AccountTokenProject.create_changeset(%{
            account_token_id: non_existent_token_id,
            project_id: project.id
          })
        )

      # Then
      assert "does not exist" in errors_on(got).account_token_id
    end

    test "enforces foreign key constraint on project_id" do
      # Given
      account = AccountsFixtures.user_fixture(preload: [:account]).account
      token = AccountsFixtures.account_token_fixture(account: account)
      non_existent_project_id = UUIDv7.generate()

      # When
      {:error, got} =
        Repo.insert(
          AccountTokenProject.create_changeset(%{
            account_token_id: token.id,
            project_id: non_existent_project_id
          })
        )

      # Then
      errors = errors_on(got).project_id
      assert "does not exist" in errors or "is invalid" in errors
    end
  end
end
