defmodule Tuist.QATest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Authentication
  alias Tuist.QA
  alias Tuist.QA.Agent
  alias Tuist.Repo
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.QAFixtures

  describe "test/1" do
    test "successfully runs QA test and returns completed status" do
      # Given
      app_build = Repo.preload(AppBuildsFixtures.app_build_fixture(), preview: [project: :account])

      prompt = "Test the login feature"

      expect(Storage, :generate_download_url, fn _ -> "https://example.com/preview.zip" end)

      expect(Authentication, :encode_and_sign, fn _account, claims, opts ->
        assert claims["type"] == "account"
        assert claims["scopes"] == ["project_qa_run_update", "project_qa_run_step_create", "project_qa_screenshot_create"]
        assert claims["project_id"] == app_build.preview.project.id
        assert Keyword.get(opts, :token_type) == :access
        assert Keyword.get(opts, :ttl) == {1, :hour}
        {:ok, "test-jwt-token", claims}
      end)

      expect(Agent, :test, fn %{
                                preview_url: "https://example.com/preview.zip",
                                bundle_identifier: "dev.tuist.app",
                                prompt: ^prompt,
                                server_url: _,
                                run_id: _,
                                auth_token: "test-jwt-token"
                              },
                              _opts ->
        :ok
      end)

      # When
      result =
        QA.test(%{
          app_build: app_build,
          prompt: prompt
        })

      # Then
      assert :ok = result
    end

    test "returns failed status when agent test fails" do
      # Given
      app_build = Repo.preload(AppBuildsFixtures.app_build_fixture(), preview: [project: :account])

      prompt = "Test the login feature"

      expect(Storage, :generate_download_url, fn _ -> "https://example.com/preview.zip" end)

      expect(Authentication, :encode_and_sign, fn _account, claims, opts ->
        assert claims["type"] == "account"
        assert claims["scopes"] == ["project_qa_run_update", "project_qa_run_step_create", "project_qa_screenshot_create"]
        assert claims["project_id"] == app_build.preview.project.id
        assert Keyword.get(opts, :token_type) == :access
        assert Keyword.get(opts, :ttl) == {1, :hour}
        {:ok, "test-jwt-token", claims}
      end)

      expect(Agent, :test, fn _, _ -> {:error, "Agent test failed"} end)

      # When
      result =
        QA.test(%{
          app_build: app_build,
          prompt: prompt
        })

      # Then
      assert {:error, "Agent test failed"} = result
    end

    test "returns error when auth token creation fails" do
      # Given
      app_build = Repo.preload(AppBuildsFixtures.app_build_fixture(), preview: [project: :account])

      expect(Storage, :generate_download_url, fn _ -> "https://example.com/preview.zip" end)

      expect(Authentication, :encode_and_sign, fn _account, _claims, _opts ->
        {:error, "Token creation failed"}
      end)

      # When
      result =
        QA.test(%{
          app_build: app_build,
          prompt: "Test prompt"
        })

      # Then
      assert {:error, "Token creation failed"} = result
    end
  end

  describe "create_qa_run/1" do
    test "creates a QA run with valid attributes" do
      # Given
      app_build = AppBuildsFixtures.app_build_fixture()

      attrs = %{
        app_build_id: app_build.id,
        prompt: "Test the login feature",
        status: "pending"
      }

      # When
      {:ok, qa_run} = QA.create_qa_run(attrs)

      # Then
      assert qa_run.app_build_id == app_build.id
      assert qa_run.prompt == "Test the login feature"
      assert qa_run.status == "pending"
      assert qa_run.id
      assert qa_run.inserted_at
      assert qa_run.updated_at
    end

    test "returns error with invalid attributes" do
      # Given
      attrs = %{
        prompt: "Test prompt"
        # Missing required app_build_id
      }

      # When
      {:error, changeset} = QA.create_qa_run(attrs)

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).app_build_id
    end
  end

  describe "update_qa_run/2" do
    test "updates a QA run with valid attributes" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      # When
      {:ok, updated_qa_run} = QA.update_qa_run(qa_run, %{status: "completed"})

      # Then
      assert updated_qa_run.status == "completed"
    end
  end

  describe "create_qa_run_step/1" do
    test "creates a QA run step with valid attributes" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      attrs = %{
        qa_run_id: qa_run.id,
        summary: "Successfully logged in",
        description: "User successfully entered credentials and accessed the main screen",
        issues: []
      }

      # When
      {:ok, qa_run_step} = QA.create_qa_run_step(attrs)

      # Then
      assert qa_run_step.qa_run_id == qa_run.id
      assert qa_run_step.summary == "Successfully logged in"
      assert qa_run_step.id
      assert qa_run_step.inserted_at
    end

    test "returns error with invalid attributes" do
      # Given
      attrs = %{
        summary: "Test summary",
        description: "Test description",
        issues: []
        # Missing required qa_run_id
      }

      # When
      {:error, changeset} = QA.create_qa_run_step(attrs)

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).qa_run_id
    end
  end

  describe "qa_run/1" do
    test "returns QA run when it exists" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      # When
      {:ok, got} = QA.qa_run(qa_run.id)

      # Then
      assert got.id == qa_run.id
    end

    test "returns not found error when QA run does not exist" do
      # Given
      non_existent_id = Ecto.UUID.generate()

      # When
      result = QA.qa_run(non_existent_id)

      # Then
      assert {:error, :not_found} = result
    end
  end

  describe "create_qa_screenshot/1" do
    test "creates a screenshot with valid attributes" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      attrs = %{
        qa_run_id: qa_run.id,
        file_name: "login_screen",
        title: "Login Screen Screenshot"
      }

      # When
      {:ok, screenshot} = QA.create_qa_screenshot(attrs)

      # Then
      assert screenshot.qa_run_id == qa_run.id
      assert screenshot.file_name == "login_screen"
      assert screenshot.title == "Login Screen Screenshot"
      assert screenshot.id
      assert screenshot.inserted_at
      assert screenshot.updated_at
    end

    test "creates a screenshot with optional qa_run_step_id" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()
      qa_run_step = QAFixtures.qa_run_step_fixture(qa_run_id: qa_run.id)

      attrs = %{
        qa_run_id: qa_run.id,
        qa_run_step_id: qa_run_step.id,
        file_name: "error_dialog",
        title: "Error Dialog Screenshot"
      }

      # When
      {:ok, screenshot} = QA.create_qa_screenshot(attrs)

      # Then
      assert screenshot.qa_run_id == qa_run.id
      assert screenshot.qa_run_step_id == qa_run_step.id
      assert screenshot.file_name == "error_dialog"
      assert screenshot.title == "Error Dialog Screenshot"
    end

    test "returns error with invalid attributes" do
      # Given
      attrs = %{
        file_name: "test_screenshot",
        title: "Test Screenshot"
        # Missing required qa_run_id
      }

      # When
      {:error, changeset} = QA.create_qa_screenshot(attrs)

      # Then
      assert changeset.valid? == false
      assert "can't be blank" in errors_on(changeset).qa_run_id
    end
  end

  describe "update_screenshots_with_step_id/2" do
    test "updates screenshots without step_id to have the given step_id" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()
      qa_run_step = QAFixtures.qa_run_step_fixture(qa_run_id: qa_run.id)

      # Create screenshots without step_id
      {:ok, screenshot1} = QA.create_qa_screenshot(%{qa_run_id: qa_run.id, file_name: "screenshot1", title: "Screenshot 1"})
      {:ok, screenshot2} = QA.create_qa_screenshot(%{qa_run_id: qa_run.id, file_name: "screenshot2", title: "Screenshot 2"})

      # Create a screenshot with a different step_id that shouldn't be updated
      other_step = QAFixtures.qa_run_step_fixture(qa_run_id: qa_run.id)

      {:ok, screenshot3} =
        QA.create_qa_screenshot(%{
          qa_run_id: qa_run.id,
          qa_run_step_id: other_step.id,
          file_name: "screenshot3",
          title: "Screenshot 3"
        })

      # When
      {updated_count, _} = QA.update_screenshots_with_step_id(qa_run.id, qa_run_step.id)

      # Then
      assert updated_count == 2

      # Verify the screenshots were updated
      screenshot1_updated = Repo.get!(QA.Screenshot, screenshot1.id)
      screenshot2_updated = Repo.get!(QA.Screenshot, screenshot2.id)
      screenshot3_updated = Repo.get!(QA.Screenshot, screenshot3.id)

      assert screenshot1_updated.qa_run_step_id == qa_run_step.id
      assert screenshot2_updated.qa_run_step_id == qa_run_step.id
      # Should remain unchanged
      assert screenshot3_updated.qa_run_step_id == other_step.id
    end

    test "returns 0 when no screenshots need updating" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()
      qa_run_step = QAFixtures.qa_run_step_fixture(qa_run_id: qa_run.id)

      # When
      {updated_count, _} = QA.update_screenshots_with_step_id(qa_run.id, qa_run_step.id)

      # Then
      assert updated_count == 0
    end
  end

  describe "screenshot_storage_key/1" do
    test "generates correct storage key for screenshot" do
      # Given
      qa_run_id = Ecto.UUID.generate()
      name = "login_screen"
      account_handle = "TestAccount"
      project_handle = "TestProject"

      # When
      storage_key =
        QA.screenshot_storage_key(%{
          account_handle: account_handle,
          project_handle: project_handle,
          qa_run_id: qa_run_id,
          file_name: name
        })

      # Then
      assert storage_key == "testaccount/testproject/qa/screenshots/#{qa_run_id}/#{name}.png"
    end

    test "generates correct storage key with special characters in name" do
      # Given
      qa_run_id = Ecto.UUID.generate()
      name = "screen_with-special_chars"
      account_handle = "MyAccount"
      project_handle = "MyProject"

      # When
      storage_key =
        QA.screenshot_storage_key(%{
          account_handle: account_handle,
          project_handle: project_handle,
          qa_run_id: qa_run_id,
          file_name: name
        })

      # Then
      assert storage_key == "myaccount/myproject/qa/screenshots/#{qa_run_id}/#{name}.png"
    end
  end
end
