defmodule Tuist.QA.RunTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.QA.Run
  alias TuistTestSupport.Fixtures.AppBuildsFixtures

  describe "create_changeset/2" do
    test "is valid with valid attributes" do
      # Given
      app_build = AppBuildsFixtures.app_build_fixture()

      # When
      changeset =
        Run.create_changeset(%Run{}, %{
          app_build_id: app_build.id,
          prompt: "Test the login feature",
          status: "pending"
        })

      # Then
      assert changeset.valid?
    end

    test "is valid with all supported statuses" do
      # Given
      app_build = AppBuildsFixtures.app_build_fixture()

      valid_statuses = ["pending", "running", "completed", "failed"]

      for status <- valid_statuses do
        # When
        changeset =
          Run.create_changeset(%Run{}, %{
            app_build_id: app_build.id,
            prompt: "Test prompt",
            status: status
          })

        # Then
        assert changeset.valid?, "Status '#{status}' should be valid"
      end
    end

    test "is valid without app_build_id" do
      # When
      changeset =
        Run.create_changeset(%Run{}, %{
          prompt: "Test the login feature",
          status: "pending"
        })

      # Then
      assert changeset.valid? == true
    end

    test "is invalid without prompt" do
      # Given
      app_build = AppBuildsFixtures.app_build_fixture()

      # When
      changeset =
        Run.create_changeset(%Run{}, %{
          app_build_id: app_build.id,
          status: "pending"
        })

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).prompt
    end

    test "is valid without explicit status" do
      # Given
      app_build = AppBuildsFixtures.app_build_fixture()

      # When
      changeset =
        Run.create_changeset(%Run{}, %{
          app_build_id: app_build.id,
          prompt: "Test the login feature"
        })

      # Then
      assert changeset.valid?
    end

    test "is invalid with invalid status" do
      # Given
      app_build = AppBuildsFixtures.app_build_fixture()

      # When
      changeset =
        Run.create_changeset(%Run{}, %{
          app_build_id: app_build.id,
          prompt: "Test the login feature",
          status: "invalid_status"
        })

      # Then
      assert changeset.valid? == false
      assert "is invalid" in errors_on(changeset).status
    end

    test "is valid with provided status" do
      # Given
      app_build = AppBuildsFixtures.app_build_fixture()

      # When
      changeset =
        Run.create_changeset(%Run{}, %{
          app_build_id: app_build.id,
          prompt: "Test the login feature",
          status: "running"
        })

      # Then
      assert changeset.valid?
      assert changeset.changes.status == "running"
    end

    test "create_changeset sets status to provided value" do
      # Given
      app_build = AppBuildsFixtures.app_build_fixture()

      # When
      changeset =
        Run.create_changeset(%Run{}, %{
          app_build_id: app_build.id,
          prompt: "Test the login feature",
          status: "running"
        })

      # Then
      assert changeset.changes.status == "running"
    end

    test "create_changeset is invalid with non-existent app_build_id" do
      # Given
      non_existent_id = UUIDv7.generate()

      # When
      changeset =
        Run.create_changeset(%Run{}, %{
          app_build_id: non_existent_id,
          prompt: "Test the login feature",
          status: "pending"
        })

      # Then
      assert changeset.valid?

      # When
      assert {:error, changeset_with_error} = Repo.insert(changeset)
      assert "does not exist" in errors_on(changeset_with_error).app_build_id
    end
  end
end
