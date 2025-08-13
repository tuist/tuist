defmodule Tuist.QATest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias QA.Agent
  alias Tuist.Authentication
  alias Tuist.QA
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.QAFixtures

  describe "test/1" do
    test "successfully runs QA test and returns completed status" do
      # Given
      app_build = Repo.preload(AppBuildsFixtures.app_build_fixture(), preview: [project: :account])

      prompt = "Test the login feature"

      expect(Storage, :generate_download_url, fn _ -> "https://example.com/preview.zip" end)

      expect(Authentication, :encode_and_sign, fn _account, claims, _opts ->
        {:ok, "test-jwt-token", claims}
      end)

      expect(Tuist.Environment, :namespace_enabled?, fn -> false end)

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
      {:ok, qa_run} =
        QA.test(%{
          app_build: app_build,
          prompt: prompt
        })

      # Then
      assert qa_run.prompt == prompt
    end

    test "successfully runs QA test in namespace when namespace is enabled" do
      # Given
      app_build = Repo.preload(AppBuildsFixtures.app_build_fixture(), preview: [project: :account])
      account = app_build.preview.project.account
      prompt = "Test the login feature"

      expect(Storage, :generate_download_url, fn _ -> "https://example.com/preview.zip" end)

      expect(Authentication, :encode_and_sign, fn _account, claims, _opts ->
        {:ok, "test-jwt-token", claims}
      end)

      expect(Tuist.Environment, :namespace_enabled?, fn -> true end)

      expect(Tuist.Accounts, :create_namespace_tenant_for_account, fn ^account ->
        {:ok, Map.put(account, :tenant_id, "test-tenant-123")}
      end)

      expect(Tuist.Namespace, :create_instance_with_ssh_connection, fn "test-tenant-123" ->
        {:ok,
         %{
           ssh_connection: %{},
           instance: %{id: "instance-123"},
           tenant_token: "tenant-token-456"
         }}
      end)

      expect(Tuist.SSHClient, :transfer_file, fn _ssh_connection,
                                                 "/app/bin/qa",
                                                 "/usr/local/bin/qa",
                                                 [permissions: 0o100755] ->
        :ok
      end)

      expect(Tuist.SSHClient, :run_command, fn _ssh_connection, command ->
        assert String.contains?(command, "brew install facebook/fb/idb-companion")
        assert String.contains?(command, "pipx install fb-idb")
        assert String.contains?(command, "qa --preview-url")
        assert String.contains?(command, "Test the login feature")
        assert String.contains?(command, "--auth-token test-jwt-token")
        {:ok, "QA test completed successfully"}
      end)

      expect(Tuist.Namespace, :destroy_instance, fn "instance-123", "tenant-token-456" ->
        :ok
      end)

      # When
      {:ok, qa_run} =
        QA.test(%{
          app_build: app_build,
          prompt: prompt
        })

      # Then
      assert qa_run.prompt == prompt
    end

    test "handles existing tenant when namespace is enabled" do
      # Given
      app_build = Repo.preload(AppBuildsFixtures.app_build_fixture(), preview: [project: :account])
      account = Map.put(app_build.preview.project.account, :tenant_id, "existing-tenant-456")
      app_build = put_in(app_build.preview.project.account, account)
      prompt = "Test the login feature"

      expect(Storage, :generate_download_url, fn _ -> "https://example.com/preview.zip" end)

      expect(Authentication, :encode_and_sign, fn _account, claims, _opts ->
        {:ok, "test-jwt-token", claims}
      end)

      expect(Tuist.Environment, :namespace_enabled?, fn -> true end)

      expect(Tuist.Namespace, :create_instance_with_ssh_connection, fn "existing-tenant-456" ->
        {:ok,
         %{
           ssh_connection: %{},
           instance: %{id: "instance-789"},
           tenant_token: "tenant-token-789"
         }}
      end)

      expect(Tuist.SSHClient, :transfer_file, fn _ssh_connection,
                                                 "/app/bin/qa",
                                                 "/usr/local/bin/qa",
                                                 [permissions: 0o100755] ->
        :ok
      end)

      expect(Tuist.SSHClient, :run_command, fn _ssh_connection, _command ->
        {:ok, "QA test completed successfully"}
      end)

      expect(Tuist.Namespace, :destroy_instance, fn "instance-789", "tenant-token-789" ->
        :ok
      end)

      # When
      {:ok, qa_run} =
        QA.test(%{
          app_build: app_build,
          prompt: prompt
        })

      # Then
      assert qa_run.prompt == prompt
    end

    test "runs agent test when namespace is disabled" do
      # Given
      app_build = Repo.preload(AppBuildsFixtures.app_build_fixture(), preview: [project: :account])

      prompt = "Test the login feature"

      expect(Storage, :generate_download_url, fn _ -> "https://example.com/preview.zip" end)

      expect(Authentication, :encode_and_sign, fn _account, claims, _opts ->
        {:ok, "test-jwt-token", claims}
      end)

      expect(Tuist.Environment, :namespace_enabled?, fn -> false end)

      expect(Agent, :test, fn attrs, opts ->
        assert attrs.preview_url == "https://example.com/preview.zip"
        assert attrs.prompt == prompt
        assert opts[:anthropic_api_key]
        :ok
      end)

      # When
      {:ok, qa_run} =
        QA.test(%{
          app_build: app_build,
          prompt: prompt
        })

      # Then
      assert qa_run.prompt == prompt
      assert qa_run.status == "pending"
    end

    test "destroys namespace instance even when running the SSH command fails" do
      # Given
      app_build = AppBuildsFixtures.app_build_fixture(preload: [preview: [project: :account]])
      account = app_build.preview.project.account
      prompt = "Test the login feature"

      expect(Storage, :generate_download_url, fn _ -> "https://example.com/preview.zip" end)

      expect(Authentication, :encode_and_sign, fn _account, claims, _opts ->
        {:ok, "test-jwt-token", claims}
      end)

      expect(Tuist.Environment, :namespace_enabled?, fn -> true end)

      expect(Tuist.Accounts, :create_namespace_tenant_for_account, fn ^account ->
        {:ok, Map.put(account, :tenant_id, "test-tenant-123")}
      end)

      expect(Tuist.Namespace, :create_instance_with_ssh_connection, fn "test-tenant-123" ->
        {:ok,
         %{
           ssh_connection: %{},
           instance: %{id: "instance-123"},
           tenant_token: "tenant-token-456"
         }}
      end)

      expect(Tuist.SSHClient, :transfer_file, fn _ssh_connection,
                                                 "/app/bin/qa",
                                                 "/usr/local/bin/qa",
                                                 [permissions: 0o100755] ->
        :ok
      end)

      expect(Tuist.SSHClient, :run_command, fn _ssh_connection, _command ->
        {:error, "Command execution failed"}
      end)

      expect(Tuist.Namespace, :destroy_instance, fn "instance-123", "tenant-token-456" ->
        :ok
      end)

      # When
      result =
        QA.test(%{
          app_build: app_build,
          prompt: prompt
        })

      # Then
      assert {:error, "Command execution failed"} == result
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
      assert {:error, "Token creation failed"} == result
    end
  end

  describe "create_qa_run/1" do
    test "creates a QA run with valid attributes" do
      # Given
      app_build = AppBuildsFixtures.app_build_fixture()

      # When
      {:ok, qa_run} = QA.create_qa_run(%{app_build_id: app_build.id, prompt: "Test the login feature", status: "pending"})

      # Then
      assert qa_run.app_build_id == app_build.id
      assert qa_run.prompt == "Test the login feature"
      assert qa_run.status == "pending"
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

  describe "create_qa_step/1" do
    test "creates a QA run step with valid attributes" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      # When
      {:ok, qa_step} =
        QA.create_qa_step(%{
          qa_run_id: qa_run.id,
          summary: "Successfully logged in",
          description: "User successfully entered credentials and accessed the main screen",
          issues: []
        })

      # Then
      assert qa_step.qa_run_id == qa_run.id
      assert qa_step.summary == "Successfully logged in"
      assert qa_step.description == "User successfully entered credentials and accessed the main screen"
      assert qa_step.issues == []
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

      # When
      {:ok, screenshot} =
        QA.create_qa_screenshot(%{qa_run_id: qa_run.id, file_name: "login_screen", title: "Login Screen Screenshot"})

      # Then
      assert screenshot.qa_run_id == qa_run.id
      assert screenshot.file_name == "login_screen"
      assert screenshot.title == "Login Screen Screenshot"
    end

    test "creates a screenshot with optional qa_step_id" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()
      qa_step = QAFixtures.qa_step_fixture(qa_run_id: qa_run.id)

      # When
      {:ok, screenshot} =
        QA.create_qa_screenshot(%{
          qa_run_id: qa_run.id,
          qa_step_id: qa_step.id,
          file_name: "error_dialog",
          title: "Error Dialog Screenshot"
        })

      # Then
      assert screenshot.qa_run_id == qa_run.id
      assert screenshot.qa_step_id == qa_step.id
      assert screenshot.file_name == "error_dialog"
      assert screenshot.title == "Error Dialog Screenshot"
    end
  end

  describe "update_screenshots_with_step_id/2" do
    test "updates screenshots without step_id to have the given step_id" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()
      qa_step = QAFixtures.qa_step_fixture(qa_run_id: qa_run.id)
      other_step = QAFixtures.qa_step_fixture(qa_run_id: qa_run.id)

      {:ok, screenshot1} =
        QA.create_qa_screenshot(%{qa_run_id: qa_run.id, file_name: "screenshot1", title: "Screenshot 1"})

      {:ok, screenshot2} =
        QA.create_qa_screenshot(%{qa_run_id: qa_run.id, file_name: "screenshot2", title: "Screenshot 2"})

      {:ok, screenshot3} =
        QA.create_qa_screenshot(%{
          qa_run_id: qa_run.id,
          qa_step_id: other_step.id,
          file_name: "screenshot3",
          title: "Screenshot 3"
        })

      # When
      {updated_count, _} = QA.update_screenshots_with_step_id(qa_run.id, qa_step.id)

      # Then
      assert updated_count == 2
      assert Repo.get!(QA.Screenshot, screenshot1.id).qa_step_id == qa_step.id
      assert Repo.get!(QA.Screenshot, screenshot2.id).qa_step_id == qa_step.id
      assert Repo.get!(QA.Screenshot, screenshot3.id).qa_step_id == other_step.id
    end

    test "returns 0 when no screenshots need updating" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()
      qa_step = QAFixtures.qa_step_fixture(qa_run_id: qa_run.id)

      # When
      {updated_count, _} = QA.update_screenshots_with_step_id(qa_run.id, qa_step.id)

      # Then
      assert updated_count == 0
    end
  end

  describe "screenshot_storage_key/1" do
    test "generates correct storage key for screenshot" do
      # Given
      qa_run_id = Ecto.UUID.generate()

      # When
      storage_key =
        QA.screenshot_storage_key(%{
          account_handle: "TestAccount",
          project_handle: "TestProject",
          qa_run_id: qa_run_id,
          file_name: "login_screen"
        })

      # Then
      assert storage_key == "testaccount/testproject/qa/screenshots/#{qa_run_id}/login_screen.png"
    end

    test "generates correct storage key with special characters in name" do
      # Given
      qa_run_id = Ecto.UUID.generate()

      # When
      storage_key =
        QA.screenshot_storage_key(%{
          account_handle: "MyAccount",
          project_handle: "MyProject",
          qa_run_id: qa_run_id,
          file_name: "screen_with-special_chars"
        })

      # Then
      assert storage_key == "myaccount/myproject/qa/screenshots/#{qa_run_id}/screen_with-special_chars.png"
    end
  end

  describe "find_pending_qa_runs_for_app_build/1" do
    test "returns pending QA runs for app build with iOS simulator support" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_provider: :github,
          vcs_repository_full_handle: "testaccount/testproject"
        )

      preview = AppBuildsFixtures.preview_fixture(project: project)

      app_build =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          supported_platforms: [:ios_simulator]
        )

      {:ok, qa_run1} =
        QA.create_qa_run(%{
          app_build_id: nil,
          status: "pending",
          vcs_repository_full_handle: "testaccount/testproject",
          vcs_provider: :github,
          git_ref: preview.git_ref,
          prompt: "Test prompt 1"
        })

      {:ok, qa_run2} =
        QA.create_qa_run(%{
          app_build_id: nil,
          status: "pending",
          vcs_repository_full_handle: "testaccount/testproject",
          vcs_provider: :github,
          git_ref: preview.git_ref,
          prompt: "Test prompt 2"
        })

      {:ok, _qa_run_with_build} =
        QA.create_qa_run(%{
          app_build_id: app_build.id,
          status: "pending",
          vcs_repository_full_handle: "testaccount/testproject",
          vcs_provider: :github,
          git_ref: preview.git_ref,
          prompt: "Test prompt 3"
        })

      {:ok, _qa_run_completed} =
        QA.create_qa_run(%{
          app_build_id: nil,
          status: "completed",
          vcs_repository_full_handle: "testaccount/testproject",
          vcs_provider: :github,
          git_ref: preview.git_ref,
          prompt: "Test prompt 4"
        })

      {:ok, _qa_run_different_repo} =
        QA.create_qa_run(%{
          app_build_id: nil,
          status: "pending",
          vcs_repository_full_handle: "other/repo",
          vcs_provider: :github,
          git_ref: preview.git_ref,
          prompt: "Test prompt 5"
        })

      {:ok, _qa_run_different_ref} =
        QA.create_qa_run(%{
          app_build_id: nil,
          status: "pending",
          vcs_repository_full_handle: "testaccount/testproject",
          vcs_provider: :github,
          git_ref: "refs/pull/456/merge",
          prompt: "Test prompt 6"
        })

      # When
      result = QA.find_pending_qa_runs_for_app_build(app_build)

      # Then
      assert result |> Enum.sort_by(& &1.inserted_at) |> Enum.map(& &1.id) == [qa_run1.id, qa_run2.id]
    end

    test "returns empty list when no pending QA runs exist" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_provider: :github,
          vcs_repository_full_handle: "testaccount/testproject"
        )

      preview = AppBuildsFixtures.preview_fixture(project: project)

      app_build =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          supported_platforms: [:ios_simulator]
        )

      # When
      result = QA.find_pending_qa_runs_for_app_build(app_build)

      # Then
      assert result == []
    end

    test "returns empty list when project has no repository URL" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_provider: nil,
          vcs_repository_full_handle: nil
        )

      preview = AppBuildsFixtures.preview_fixture(project: project)

      app_build =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          supported_platforms: [:ios_simulator]
        )

      # When
      result = QA.find_pending_qa_runs_for_app_build(app_build)

      # Then
      assert result == []
    end

    test "returns empty list when preview has no git_ref" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_provider: :github,
          vcs_repository_full_handle: "testaccount/testproject"
        )

      preview = AppBuildsFixtures.preview_fixture(project: project, git_ref: nil)

      app_build =
        AppBuildsFixtures.app_build_fixture(
          preview: preview,
          supported_platforms: [:ios_simulator]
        )

      # Create pending QA runs that should not be returned
      {:ok, _qa_run} =
        QA.create_qa_run(%{
          app_build_id: nil,
          status: "pending",
          vcs_repository_full_handle: "testaccount/testproject",
          vcs_provider: :github,
          git_ref: "refs/heads/main",
          prompt: "Test prompt"
        })

      # When
      result = QA.find_pending_qa_runs_for_app_build(app_build)

      # Then
      assert result == []
    end
  end

  describe "screenshot/2" do
    test "returns screenshot when it exists and qa_run_id is provided" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()
      screenshot = QAFixtures.screenshot_fixture(qa_run: qa_run, file_name: "test_screenshot", title: "Test Screenshot")

      # When
      result = QA.screenshot(screenshot.id, qa_run_id: qa_run.id)

      # Then
      assert {:ok, returned_screenshot} = result
      assert returned_screenshot.id == screenshot.id
    end

    test "returns error when screenshot exists but qa_run_id doesn't match" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()
      other_qa_run = QAFixtures.qa_run_fixture()
      screenshot = QAFixtures.screenshot_fixture(qa_run: qa_run)

      # When
      result = QA.screenshot(screenshot.id, qa_run_id: other_qa_run.id)

      # Then
      assert result == {:error, :not_found}
    end

    test "returns screenshot when it exists and qa_run_id is not provided" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()
      screenshot = QAFixtures.screenshot_fixture(qa_run: qa_run, file_name: "any_screenshot", title: "Any Screenshot")

      # When
      result = QA.screenshot(screenshot.id)

      # Then
      assert {:ok, returned_screenshot} = result
      assert returned_screenshot.id == screenshot.id
    end

    test "returns error when screenshot doesn't exist" do
      # Given
      non_existent_id = Ecto.UUID.generate()
      qa_run = QAFixtures.qa_run_fixture()

      # When
      result = QA.screenshot(non_existent_id, qa_run_id: qa_run.id)

      # Then
      assert result == {:error, :not_found}
    end
  end

  describe "post_vcs_test_summary/1" do
    test "successfully posts VCS comment for PR with QA run summary" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          name: "TestProject",
          vcs_repository_full_handle: "testaccount/testproject",
          vcs_provider: :github
        )

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          git_ref: "refs/pull/123/merge",
          git_commit_sha: "abc123def456"
        )

      app_build = AppBuildsFixtures.app_build_fixture(preview: preview)

      qa_run =
        QAFixtures.qa_run_fixture(
          app_build: app_build,
          summary: "Test run completed successfully",
          prompt: "Test the login functionality"
        )

      step1 =
        QAFixtures.qa_step_fixture(
          qa_run: qa_run,
          summary: "Login step",
          description: "User successfully logged in",
          issues: ["Login button not visible"]
        )

      step2 =
        QAFixtures.qa_step_fixture(
          qa_run: qa_run,
          summary: "Navigation step",
          description: "User navigated to main screen",
          issues: []
        )

      screenshot1 =
        QAFixtures.screenshot_fixture(
          qa_run: qa_run,
          qa_step: step1,
          file_name: "screenshot1",
          title: "Screenshot 1"
        )

      screenshot2 =
        QAFixtures.screenshot_fixture(
          qa_run: qa_run,
          qa_step: step2,
          file_name: "screenshot2",
          title: "Screenshot 2"
        )

      expected_body = """
      ### 🤖 QA Test Summary
      **Prompt:** Test the login functionality
      **Preview:** [#{preview.display_name}](http://localhost:8080/#{project.account.name}/#{project.name}/previews/#{preview.id})
      **Commit:** [abc123def](https://github.com/testaccount/testproject/commit/abc123def456)

      Test run completed successfully

      <details>
      <summary>🚶 QA Steps</summary>


      #### 1. Login step

      User successfully logged in

      **⚠️ Issues Found:**
      1. Login button not visible


      <details>
      <summary>1. Screenshot 1</summary>

      <img src="http://localhost:8080/#{project.account.name}/#{project.name}/qa/runs/#{qa_run.id}/screenshots/#{screenshot1.id}" alt="Screenshot 1" width="500" />
      </details>


      #### 2. Navigation step

      User navigated to main screen

      <details>
      <summary>1. Screenshot 2</summary>

      <img src="http://localhost:8080/#{project.account.name}/#{project.name}/qa/runs/#{qa_run.id}/screenshots/#{screenshot2.id}" alt="Screenshot 2" width="500" />
      </details>


      </details>

      """

      expect(VCS, :create_comment, fn %{
                                        repository_full_handle: "testaccount/testproject",
                                        git_ref: "refs/pull/123/merge",
                                        body: body,
                                        project: _project
                                      } ->
        assert body == expected_body
        :ok
      end)

      # When
      result = QA.post_vcs_test_summary(qa_run)

      # Then
      assert :ok == result
    end

    test "updates existing VCS comment when issue_comment_id exists" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          name: "TestProject",
          vcs_repository_full_handle: "testaccount/testproject",
          vcs_provider: :github
        )

      preview =
        AppBuildsFixtures.preview_fixture(
          project: project,
          git_ref: "refs/pull/123/merge",
          git_commit_sha: "abc123def456"
        )

      app_build = AppBuildsFixtures.app_build_fixture(preview: preview)

      {:ok, qa_run} =
        QA.create_qa_run(%{
          app_build_id: app_build.id,
          summary: "Test run completed successfully",
          prompt: "Test the login functionality",
          issue_comment_id: 98_765
        })

      expect(VCS, :update_comment, fn %{
                                        repository_full_handle: "testaccount/testproject",
                                        comment_id: 98_765,
                                        body: _body,
                                        project: _project
                                      } ->
        :ok
      end)

      # When
      result = QA.post_vcs_test_summary(qa_run)

      # Then
      assert :ok == result
    end
  end
end
