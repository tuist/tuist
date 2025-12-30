defmodule Tuist.Projects.VCSConnectionTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Projects.VCSConnection
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.VCSFixtures

  describe "changeset/2" do
    test "is valid with valid attributes" do
      # Given
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)
      user = AccountsFixtures.user_fixture()

      github_app_installation =
        VCSFixtures.github_app_installation_fixture(account_id: project.account.id)

      # When
      changeset =
        VCSConnection.changeset(%VCSConnection{}, %{
          project_id: project.id,
          provider: :github,
          repository_full_handle: "tuist/tuist",
          created_by_id: user.id,
          github_app_installation_id: github_app_installation.id
        })

      # Then
      assert changeset.valid?
    end

    test "is invalid without required fields" do
      # When
      changeset = VCSConnection.changeset(%VCSConnection{}, %{})

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).project_id
      assert "can't be blank" in errors_on(changeset).provider
      assert "can't be blank" in errors_on(changeset).repository_full_handle
      assert "can't be blank" in errors_on(changeset).github_app_installation_id
    end

    test "is valid without created_by_id" do
      # Given
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)

      github_app_installation =
        VCSFixtures.github_app_installation_fixture(account_id: project.account.id)

      # When
      changeset =
        VCSConnection.changeset(%VCSConnection{}, %{
          project_id: project.id,
          provider: :github,
          repository_full_handle: "tuist/tuist",
          github_app_installation_id: github_app_installation.id
        })

      # Then
      assert changeset.valid?
    end

    test "validates repository_full_handle format" do
      # Given
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)

      github_app_installation =
        VCSFixtures.github_app_installation_fixture(account_id: project.account.id)

      valid_handles = [
        "user/repo",
        "user-name/repo-name",
        "user.name/repo.name",
        "user_name/repo_name",
        "123/456",
        "a/b"
      ]

      for handle <- valid_handles do
        # When
        changeset =
          VCSConnection.changeset(%VCSConnection{}, %{
            project_id: project.id,
            provider: :github,
            repository_full_handle: handle,
            github_app_installation_id: github_app_installation.id
          })

        # Then
        assert changeset.valid?, "Handle '#{handle}' should be valid"
      end
    end

    test "rejects invalid repository_full_handle format" do
      # Given
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)

      github_app_installation =
        VCSFixtures.github_app_installation_fixture(account_id: project.account.id)

      invalid_handles = [
        "user",
        "user/",
        "/repo",
        "user/repo/extra",
        "user repo",
        "user@repo",
        "user/repo name",
        "user//repo"
      ]

      for handle <- invalid_handles do
        # When
        changeset =
          VCSConnection.changeset(%VCSConnection{}, %{
            project_id: project.id,
            provider: :github,
            repository_full_handle: handle,
            github_app_installation_id: github_app_installation.id
          })

        # Then
        assert changeset.valid? == false, "Handle '#{handle}' should be invalid"
        assert "has invalid format" in errors_on(changeset).repository_full_handle
      end
    end

    test "enforces unique constraint on project_id and provider combination" do
      # Given
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)
      user = AccountsFixtures.user_fixture()

      github_app_installation =
        VCSFixtures.github_app_installation_fixture(account_id: project.account.id)

      attrs = %{
        project_id: project.id,
        provider: :github,
        repository_full_handle: "tuist/tuist",
        created_by_id: user.id,
        github_app_installation_id: github_app_installation.id
      }

      {:ok, _connection} = %VCSConnection{} |> VCSConnection.changeset(attrs) |> Repo.insert()

      # When
      {:error, changeset} = %VCSConnection{} |> VCSConnection.changeset(attrs) |> Repo.insert()

      # Then
      assert "has already been taken" in errors_on(changeset).project_id
    end

    test "allows same provider for different projects" do
      # Given
      project1 = Repo.preload(ProjectsFixtures.project_fixture(), :account)
      project2 = Repo.preload(ProjectsFixtures.project_fixture(), :account)
      user = AccountsFixtures.user_fixture()

      github_app_installation1 =
        VCSFixtures.github_app_installation_fixture(account_id: project1.account.id)

      github_app_installation2 =
        VCSFixtures.github_app_installation_fixture(account_id: project2.account.id)

      # When
      {:ok, _connection1} =
        %VCSConnection{}
        |> VCSConnection.changeset(%{
          project_id: project1.id,
          provider: :github,
          repository_full_handle: "tuist/tuist",
          created_by_id: user.id,
          github_app_installation_id: github_app_installation1.id
        })
        |> Repo.insert()

      {:ok, _connection2} =
        %VCSConnection{}
        |> VCSConnection.changeset(%{
          project_id: project2.id,
          provider: :github,
          repository_full_handle: "tuist/other-repo",
          created_by_id: user.id,
          github_app_installation_id: github_app_installation2.id
        })
        |> Repo.insert()

      # Then - Both inserts should succeed
      assert true
    end

    test "validates foreign key constraint on project_id" do
      # Given
      non_existent_project_id = 999_999
      user = Repo.preload(AccountsFixtures.user_fixture(), :account)

      github_app_installation =
        VCSFixtures.github_app_installation_fixture(account_id: user.account.id)

      # When
      changeset =
        VCSConnection.changeset(%VCSConnection{}, %{
          project_id: non_existent_project_id,
          provider: :github,
          repository_full_handle: "tuist/tuist",
          created_by_id: user.id,
          github_app_installation_id: github_app_installation.id
        })

      # Then
      assert changeset.valid?
      {:error, changeset_with_error} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset_with_error).project_id
    end

    test "validates foreign key constraint on created_by_id" do
      # Given
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)
      non_existent_user_id = 999_999

      github_app_installation =
        VCSFixtures.github_app_installation_fixture(account_id: project.account.id)

      # When
      changeset =
        VCSConnection.changeset(%VCSConnection{}, %{
          project_id: project.id,
          provider: :github,
          repository_full_handle: "tuist/tuist",
          created_by_id: non_existent_user_id,
          github_app_installation_id: github_app_installation.id
        })

      # Then
      assert changeset.valid?
      {:error, changeset_with_error} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset_with_error).created_by_id
    end

    test "validates foreign key constraint on github_app_installation_id" do
      # Given
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)
      user = AccountsFixtures.user_fixture()
      non_existent_installation_id = UUIDv7.generate()

      # When
      changeset =
        VCSConnection.changeset(%VCSConnection{}, %{
          project_id: project.id,
          provider: :github,
          repository_full_handle: "tuist/tuist",
          created_by_id: user.id,
          github_app_installation_id: non_existent_installation_id
        })

      # Then
      assert changeset.valid?
      {:error, changeset_with_error} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset_with_error).github_app_installation_id
    end

    test "accepts only valid provider values" do
      project = Repo.preload(ProjectsFixtures.project_fixture(), :account)

      github_app_installation =
        VCSFixtures.github_app_installation_fixture(account_id: project.account.id)

      changeset =
        VCSConnection.changeset(%VCSConnection{}, %{
          project_id: project.id,
          provider: :github,
          repository_full_handle: "tuist/tuist",
          github_app_installation_id: github_app_installation.id
        })

      assert changeset.valid?

      changeset =
        VCSConnection.changeset(%VCSConnection{}, %{
          project_id: project.id,
          provider: :gitlab,
          repository_full_handle: "tuist/tuist",
          github_app_installation_id: github_app_installation.id
        })

      # Then
      assert changeset.valid? == false
      assert "is invalid" in errors_on(changeset).provider
    end
  end
end
