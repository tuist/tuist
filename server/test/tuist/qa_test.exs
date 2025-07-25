defmodule Tuist.QATest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.Accounts
  alias Tuist.QA
  alias Tuist.QA.Agent
  alias Tuist.QA.Run
  alias Tuist.Storage
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.QAFixtures

  describe "test/1" do
    test "successfully runs QA test and returns completed status" do
      # Given
      app_build = AppBuildsFixtures.app_build_fixture()

      prompt = "Test the login feature"

      expect(Storage, :generate_download_url, fn _ -> "https://example.com/preview.zip" end)

      expect(Accounts, :create_account_token, fn %{account: _, scopes: _} ->
        {:ok, {%{}, "test-auth-token"}}
      end)

      expect(Agent, :test, fn %{
                                preview_url: "https://example.com/preview.zip",
                                bundle_identifier: "dev.tuist.app",
                                prompt: ^prompt,
                                server_url: _,
                                run_id: _,
                                auth_token: "test-auth-token"
                              } ->
        :ok
      end)

      # When
      result =
        QA.test(%{
          app_build: app_build,
          prompt: prompt
        })

      # Then
      assert {:ok, "completed"} = result

      # Verify QA run was created and updated
      qa_runs = Tuist.Repo.all(Run)
      assert length(qa_runs) == 1

      qa_run = List.first(qa_runs)
      assert qa_run.app_build_id == app_build.id
      assert qa_run.prompt == prompt
      assert qa_run.status == "completed"
    end

    test "returns failed status when agent test fails" do
      # Given
      app_build = Tuist.Repo.preload(AppBuildsFixtures.app_build_fixture(), preview: [project: :account])

      prompt = "Test the login feature"

      expect(Storage, :generate_download_url, fn _ -> "https://example.com/preview.zip" end)

      expect(Accounts, :create_account_token, fn %{account: _, scopes: _} ->
        {:ok, {%{}, "test-auth-token"}}
      end)

      expect(Agent, :test, fn _ -> {:error, "Agent test failed"} end)

      # When
      result =
        QA.test(%{
          app_build: app_build,
          prompt: prompt
        })

      # Then
      assert {:ok, "failed"} = result

      # Verify QA run status was updated to failed
      qa_runs = Tuist.Repo.all(Run)
      assert length(qa_runs) == 1

      qa_run = List.first(qa_runs)
      assert qa_run.status == "failed"
    end

    test "returns error when auth token creation fails" do
      # Given
      app_build = AppBuildsFixtures.app_build_fixture()

      expect(Storage, :generate_download_url, fn _ -> "https://example.com/preview.zip" end)

      expect(Accounts, :create_account_token, fn _ ->
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
        summary: "Successfully logged in"
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
        summary: "Test summary"
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
end
