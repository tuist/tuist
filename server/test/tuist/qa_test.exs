defmodule Tuist.QATest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Ecto.Association.NotLoaded
  alias LangChain.Chains.LLMChain
  alias LangChain.Message
  alias LangChain.Message.ContentPart
  alias Runner.QA.Agent
  alias Tuist.Authentication
  alias Tuist.QA
  alias Tuist.QA.LaunchArgumentGroup
  alias Tuist.QA.Run
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.VCS
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures
  alias TuistTestSupport.Fixtures.QAFixtures

  describe "test/1" do
    test "successfully runs QA test and returns completed status" do
      # Given
      app_build =
        Repo.preload(AppBuildsFixtures.app_build_fixture(), preview: [project: :account])

      prompt = "Test the login feature"

      expect(Storage, :generate_download_url, fn _object_key, _actor ->
        "https://example.com/preview.zip"
      end)

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
                                auth_token: "test-jwt-token",
                                account_handle: _,
                                project_handle: _
                              },
                              _opts ->
        :ok
      end)

      # When
      {:ok, qa_run} =
        QA.create_qa_run(%{
          app_build_id: app_build.id,
          prompt: prompt,
          status: "pending"
        })

      {:ok, updated_qa_run} = QA.test(qa_run)

      # Then
      assert updated_qa_run.prompt == prompt
    end

    test "successfully runs QA test in namespace when namespace is enabled" do
      # Given
      app_build =
        Repo.preload(AppBuildsFixtures.app_build_fixture(), preview: [project: :account])

      account = app_build.preview.project.account
      prompt = "Test the login feature"

      expect(Storage, :generate_download_url, fn _object_key, _actor ->
        "https://example.com/preview.zip"
      end)

      expect(Authentication, :encode_and_sign, fn _account, claims, _opts ->
        {:ok, "test-jwt-token", claims}
      end)

      expect(Tuist.Environment, :namespace_enabled?, fn -> true end)

      expect(Tuist.Accounts, :create_namespace_tenant_for_account, fn ^account ->
        {:ok, Map.put(account, :namespace_tenant_id, "test-tenant-123")}
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
                                                 "/app/bin/runner",
                                                 "/usr/local/bin/runner",
                                                 [permissions: 0o100755] ->
        :ok
      end)

      expect(Tuist.SSHClient, :run_command, fn _ssh_connection, command ->
        assert String.contains?(command, "runner qa --preview-url")
        {:ok, "QA test completed successfully"}
      end)

      expect(Tuist.Namespace, :destroy_instance, fn "instance-123", "tenant-token-456" ->
        :ok
      end)

      # When
      {:ok, qa_run} =
        QA.create_qa_run(%{
          app_build_id: app_build.id,
          prompt: prompt,
          status: "pending"
        })

      {:ok, updated_qa_run} = QA.test(qa_run)

      # Then
      assert updated_qa_run.prompt == prompt
    end

    test "handles existing tenant when namespace is enabled" do
      # Given
      account =
        AccountsFixtures.user_fixture().account

      {:ok, account} =
        account
        |> Tuist.Accounts.Account.update_changeset(%{namespace_tenant_id: "existing-tenant-456"})
        |> Repo.update()

      project = ProjectsFixtures.project_fixture(account_id: account.id)

      preview = AppBuildsFixtures.preview_fixture(project: project)

      app_build = AppBuildsFixtures.app_build_fixture(preview: preview)

      prompt = "Test the login feature"

      expect(Storage, :generate_download_url, fn _object_key, _actor ->
        "https://example.com/preview.zip"
      end)

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
                                                 "/app/bin/runner",
                                                 "/usr/local/bin/runner",
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
        QA.create_qa_run(%{
          app_build_id: app_build.id,
          prompt: prompt,
          status: "pending"
        })

      {:ok, updated_qa_run} = QA.test(qa_run)

      # Then
      assert updated_qa_run.prompt == prompt
    end

    test "runs agent test when namespace is disabled" do
      # Given
      app_build =
        Repo.preload(AppBuildsFixtures.app_build_fixture(), preview: [project: :account])

      prompt = "Test the login feature"

      expect(Storage, :generate_download_url, fn _object_key, _actor ->
        "https://example.com/preview.zip"
      end)

      expect(Authentication, :encode_and_sign, fn _account, claims, _opts ->
        {:ok, "test-jwt-token", claims}
      end)

      expect(Tuist.Environment, :namespace_enabled?, fn -> false end)
      stub(Tuist.Environment, :anthropic_api_key, fn -> "test-anthropic-api-key" end)
      stub(Tuist.Environment, :openai_api_key, fn -> "test-openai-api-key" end)

      expect(Agent, :test, fn attrs, opts ->
        assert attrs.preview_url == "https://example.com/preview.zip"
        assert attrs.prompt == prompt
        assert opts[:anthropic_api_key]
        :ok
      end)

      # When
      {:ok, qa_run} =
        QA.create_qa_run(%{
          app_build_id: app_build.id,
          prompt: prompt,
          status: "pending"
        })

      {:ok, updated_qa_run} = QA.test(qa_run)

      # Then
      assert updated_qa_run.prompt == prompt
      assert qa_run.status == "pending"
    end

    test "destroys namespace instance even when running the SSH command fails" do
      # Given
      app_build = AppBuildsFixtures.app_build_fixture(preload: [preview: [project: :account]])
      account = app_build.preview.project.account
      prompt = "Test the login feature"

      expect(Storage, :generate_download_url, fn _object_key, _actor ->
        "https://example.com/preview.zip"
      end)

      expect(Authentication, :encode_and_sign, fn _account, claims, _opts ->
        {:ok, "test-jwt-token", claims}
      end)

      expect(Tuist.Environment, :namespace_enabled?, fn -> true end)

      expect(Tuist.Accounts, :create_namespace_tenant_for_account, fn ^account ->
        {:ok, Map.put(account, :namespace_tenant_id, "test-tenant-123")}
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
                                                 "/app/bin/runner",
                                                 "/usr/local/bin/runner",
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
      {:ok, qa_run} =
        QA.create_qa_run(%{
          app_build_id: app_build.id,
          prompt: prompt,
          status: "pending"
        })

      result = QA.test(qa_run)

      # Then
      assert {:error, "Command execution failed"} == result
    end

    test "returns error when auth token creation fails" do
      # Given
      app_build =
        Repo.preload(AppBuildsFixtures.app_build_fixture(), preview: [project: :account])

      expect(Storage, :generate_download_url, fn _object_key, _actor ->
        "https://example.com/preview.zip"
      end)

      expect(Authentication, :encode_and_sign, fn _account, _claims, _opts ->
        {:error, "Token creation failed"}
      end)

      # When
      {:ok, qa_run} =
        QA.create_qa_run(%{
          app_build_id: app_build.id,
          prompt: "Test prompt",
          status: "pending"
        })

      result = QA.test(qa_run)

      # Then
      assert {:error, "Token creation failed"} == result
    end

    test "includes app context when project has launch argument groups and app description" do
      # Given
      app_build =
        Repo.preload(AppBuildsFixtures.app_build_fixture(), preview: [project: :account])

      project = app_build.preview.project

      {:ok, project} =
        project
        |> Tuist.Projects.Project.update_changeset(%{
          qa_app_description: "Test iOS shopping app with user authentication",
          qa_email: "test@example.com",
          qa_password: "testpassword123"
        })
        |> Repo.update()

      {:ok, login_group} =
        %LaunchArgumentGroup{}
        |> LaunchArgumentGroup.create_changeset(%{
          project_id: project.id,
          name: "login-credentials",
          description: "Skip login with prefilled credentials",
          value: "--email user@example.com --password test123"
        })
        |> Repo.insert()

      {:ok, _debug_group} =
        %LaunchArgumentGroup{}
        |> LaunchArgumentGroup.create_changeset(%{
          project_id: project.id,
          name: "debug-mode",
          description: "Enable debug logging",
          value: "--debug --verbose"
        })
        |> Repo.insert()

      prompt = "Test the login feature"

      expect(Storage, :generate_download_url, fn _, _actor ->
        "https://example.com/preview.zip"
      end)

      expect(Authentication, :encode_and_sign, fn _account, claims, _opts ->
        {:ok, "test-jwt-token", claims}
      end)

      expect(Tuist.Environment, :namespace_enabled?, fn -> false end)
      expect(Tuist.Environment, :anthropic_api_key, 2, fn -> "test-anthropic-key" end)

      expect(LLMChain, :new!, fn %{llm: _llm} -> %LLMChain{} end)

      expect(LLMChain, :add_messages, fn chain, messages ->
        assert length(messages) == 2
        assert %Message{role: :system} = List.first(messages)
        assert %Message{role: :user} = List.last(messages)
        chain
      end)

      expect(LLMChain, :run, fn _chain, _opts ->
        {:ok,
         %LLMChain{
           last_message: %Message{
             content: [%ContentPart{content: "login-credentials"}]
           }
         }}
      end)

      expect(Agent, :test, fn attrs, _opts ->
        assert attrs.launch_arguments == "--email user@example.com --password test123"
        assert attrs.app_description == "Test iOS shopping app with user authentication"
        assert attrs.email == "test@example.com"
        assert attrs.password == "testpassword123"
        :ok
      end)

      # When
      {:ok, qa_run} =
        QA.create_qa_run(%{
          app_build_id: app_build.id,
          prompt: prompt,
          status: "pending"
        })

      {:ok, updated_qa_run} = QA.test(qa_run)

      # Then
      assert updated_qa_run.prompt == prompt
      assert updated_qa_run.app_description == "Test iOS shopping app with user authentication"
      assert updated_qa_run.email == "test@example.com"
      assert updated_qa_run.password == "testpassword123"

      assert updated_qa_run.launch_argument_groups == [
               %{
                 "name" => login_group.name,
                 "value" => login_group.value,
                 "description" => login_group.description
               }
             ]
    end

    test "selects multiple launch argument groups" do
      # Given
      app_build =
        Repo.preload(AppBuildsFixtures.app_build_fixture(), preview: [project: :account])

      project = app_build.preview.project

      {:ok, _login_group} =
        %LaunchArgumentGroup{}
        |> LaunchArgumentGroup.create_changeset(%{
          project_id: project.id,
          name: "login-credentials",
          description: "Skip login with prefilled credentials",
          value: "--email user@example.com --password test123"
        })
        |> Repo.insert()

      {:ok, _debug_group} =
        %LaunchArgumentGroup{}
        |> LaunchArgumentGroup.create_changeset(%{
          project_id: project.id,
          name: "debug-mode",
          description: "Enable debug logging",
          value: "--debug --verbose"
        })
        |> Repo.insert()

      prompt = "Test the login feature with debug mode enabled"

      expect(Storage, :generate_download_url, fn _, _actor ->
        "https://example.com/preview.zip"
      end)

      expect(Authentication, :encode_and_sign, fn _account, claims, _opts ->
        {:ok, "test-jwt-token", claims}
      end)

      expect(Tuist.Environment, :namespace_enabled?, fn -> false end)
      expect(Tuist.Environment, :anthropic_api_key, 2, fn -> "test-anthropic-key" end)

      expect(LLMChain, :new!, fn %{llm: _llm} -> %LLMChain{} end)

      expect(LLMChain, :add_messages, fn chain, _messages -> chain end)

      expect(LLMChain, :run, fn _chain, _opts ->
        {:ok,
         %LLMChain{
           last_message: %Message{
             content: [%ContentPart{content: "login-credentials, debug-mode"}]
           }
         }}
      end)

      expect(Agent, :test, fn attrs, _opts ->
        assert attrs.launch_arguments ==
                 "--email user@example.com --password test123 --debug --verbose"

        :ok
      end)

      # When
      {:ok, qa_run} =
        QA.create_qa_run(%{
          app_build_id: app_build.id,
          prompt: prompt,
          status: "pending"
        })

      {:ok, updated_qa_run} = QA.test(qa_run)

      # Then
      assert updated_qa_run.prompt == prompt
    end

    test "handles empty launch arguments when no groups match" do
      # Given
      app_build =
        Repo.preload(AppBuildsFixtures.app_build_fixture(), preview: [project: :account])

      project = app_build.preview.project

      {:ok, _special_group} =
        %LaunchArgumentGroup{}
        |> LaunchArgumentGroup.create_changeset(%{
          project_id: project.id,
          name: "special-feature",
          description: "Enable special feature",
          value: "--special-feature"
        })
        |> Repo.insert()

      prompt = "Test basic navigation"

      expect(Storage, :generate_download_url, fn _, _actor ->
        "https://example.com/preview.zip"
      end)

      expect(Authentication, :encode_and_sign, fn _account, claims, _opts ->
        {:ok, "test-jwt-token", claims}
      end)

      expect(Tuist.Environment, :namespace_enabled?, fn -> false end)
      expect(Tuist.Environment, :anthropic_api_key, 2, fn -> "test-anthropic-key" end)

      expect(LLMChain, :new!, fn %{llm: _llm} -> %LLMChain{} end)

      expect(LLMChain, :add_messages, fn chain, _messages -> chain end)

      expect(LLMChain, :run, fn _chain, _opts ->
        {:ok,
         %LLMChain{
           last_message: %Message{
             content: [%ContentPart{content: ""}]
           }
         }}
      end)

      expect(Agent, :test, fn attrs, _opts ->
        assert attrs.launch_arguments == ""
        :ok
      end)

      # When
      {:ok, qa_run} =
        QA.create_qa_run(%{
          app_build_id: app_build.id,
          prompt: prompt,
          status: "pending"
        })

      {:ok, updated_qa_run} = QA.test(qa_run)

      # Then
      assert updated_qa_run.prompt == prompt
    end

    test "doesn't try to select launch argument group when project doesn't have any" do
      # Given
      app_build =
        Repo.preload(AppBuildsFixtures.app_build_fixture(), preview: [project: :account])

      prompt = "Test the app"

      expect(Storage, :generate_download_url, fn _, _actor ->
        "https://example.com/preview.zip"
      end)

      expect(Authentication, :encode_and_sign, fn _account, claims, _opts ->
        {:ok, "test-jwt-token", claims}
      end)

      expect(Tuist.Environment, :namespace_enabled?, fn -> false end)

      expect(Agent, :test, fn attrs, _opts ->
        assert attrs.launch_arguments == ""
        :ok
      end)

      # When
      {:ok, qa_run} =
        QA.create_qa_run(%{
          app_build_id: app_build.id,
          prompt: prompt,
          status: "pending"
        })

      {:ok, updated_qa_run} = QA.test(qa_run)

      # Then
      assert updated_qa_run.prompt == prompt
    end
  end

  describe "create_qa_run/1" do
    test "creates a QA run with valid attributes" do
      # Given
      app_build = AppBuildsFixtures.app_build_fixture()

      # When
      {:ok, qa_run} =
        QA.create_qa_run(%{
          app_build_id: app_build.id,
          prompt: "Test the login feature",
          status: "pending"
        })

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
          action: "Tap on Tuist label",
          result: "User successfully entered credentials and accessed the main screen",
          issues: []
        })

      # Then
      assert qa_step.qa_run_id == qa_run.id
      assert qa_step.action == "Tap on Tuist label"

      assert qa_step.result ==
               "User successfully entered credentials and accessed the main screen"

      assert qa_step.issues == []
    end
  end

  describe "step/1" do
    test "returns QA step when it exists" do
      # Given
      qa_step = QAFixtures.qa_step_fixture()

      # When
      {:ok, retrieved_step} = QA.step(qa_step.id)

      # Then
      assert retrieved_step == qa_step
    end

    test "returns not found error when QA step does not exist" do
      # Given
      non_existent_id = UUIDv7.generate()

      # When
      result = QA.step(non_existent_id)

      # Then
      assert {:error, :not_found} = result
    end
  end

  describe "update_step/2" do
    test "updates a QA step with valid attributes" do
      # Given
      qa_step = QAFixtures.qa_step_fixture(action: "Initial action", issues: [])

      # When
      {:ok, updated_step} =
        QA.update_step(qa_step, %{
          action: "Updated action",
          result: "Updated result",
          issues: ["Issue 1", "Issue 2"]
        })

      # Then
      assert updated_step.id == qa_step.id
      assert updated_step.action == "Updated action"
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
      non_existent_id = UUIDv7.generate()

      # When
      result = QA.qa_run(non_existent_id)

      # Then
      assert {:error, :not_found} = result
    end
  end

  describe "qa_run_for_ops/1" do
    test "returns QA run with project and account info when it exists" do
      # Given
      project = ProjectsFixtures.project_fixture(name: "TestProject")
      preview = AppBuildsFixtures.preview_fixture(project: project)
      app_build = AppBuildsFixtures.app_build_fixture(preview: preview)

      qa_run =
        QAFixtures.qa_run_fixture(app_build: app_build, prompt: "Test prompt", status: "running")

      # When
      result = QA.qa_run_for_ops(qa_run.id)

      # Then
      assert %{
               id: qa_run_id,
               project_name: project_name,
               account_name: account_name,
               status: "running",
               prompt: "Test prompt",
               inserted_at: inserted_at
             } = result

      assert qa_run_id == qa_run.id
      assert project_name == project.name
      assert account_name == project.account.name
      assert %DateTime{} = inserted_at
    end

    test "returns nil when QA run does not exist" do
      # Given
      non_existent_id = UUIDv7.generate()

      # When
      result = QA.qa_run_for_ops(non_existent_id)

      # Then
      assert result == nil
    end
  end

  describe "logs_for_run/1" do
    test "returns empty list when no logs exist for QA run" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      # When
      logs = QA.logs_for_run(qa_run.id)

      # Then
      assert logs == []
    end
  end

  describe "qa_runs_chart_data/0" do
    test "returns chart data for last 30 days with zero fill" do
      # Given
      today = Date.utc_today()
      three_days_ago = Date.add(today, -3)

      qa_run = QAFixtures.qa_run_fixture()

      three_days_ago_datetime = DateTime.new!(three_days_ago, ~T[12:00:00], "Etc/UTC")

      Repo.update_all(from(q in Run, where: q.id == ^qa_run.id),
        set: [inserted_at: three_days_ago_datetime]
      )

      # When
      chart_data = QA.qa_runs_chart_data()

      # Then
      assert length(chart_data) == 31

      three_days_ago_str = Date.to_string(three_days_ago)

      three_days_ago_entry =
        Enum.find(chart_data, fn [date, _count] ->
          date == three_days_ago_str
        end)

      assert [^three_days_ago_str, 1] = three_days_ago_entry

      today_str = Date.to_string(today)

      today_entry =
        Enum.find(chart_data, fn [date, _count] ->
          date == today_str
        end)

      assert [^today_str, 0] = today_entry
    end

    test "returns all zeros when no QA runs in last 30 days" do
      # When
      chart_data = QA.qa_runs_chart_data()

      # Then
      assert length(chart_data) == 31
      assert Enum.all?(chart_data, fn [_date, count] -> count == 0 end)
    end
  end

  describe "projects_usage_chart_data/0" do
    test "returns cumulative unique project counts" do
      # Given
      project1 = ProjectsFixtures.project_fixture()
      project2 = ProjectsFixtures.project_fixture()

      preview1 = AppBuildsFixtures.preview_fixture(project: project1)
      preview2 = AppBuildsFixtures.preview_fixture(project: project2)

      app_build1 = AppBuildsFixtures.app_build_fixture(preview: preview1)
      app_build2 = AppBuildsFixtures.app_build_fixture(preview: preview2)

      _qa_run1 = QAFixtures.qa_run_fixture(app_build: app_build1)
      _qa_run2 = QAFixtures.qa_run_fixture(app_build: app_build2)

      # When
      chart_data = QA.projects_usage_chart_data()

      # Then
      assert length(chart_data) == 31

      # Last day should show 2 unique projects
      [_last_date, last_count] = List.last(chart_data)
      assert last_count == 2
    end

    test "returns all zeros when no QA runs" do
      # When
      chart_data = QA.projects_usage_chart_data()

      # Then
      assert length(chart_data) == 31
      assert Enum.all?(chart_data, fn [_date, count] -> count == 0 end)
    end
  end

  describe "recent_qa_runs/0" do
    test "returns recent QA runs with project info" do
      # Given
      project = ProjectsFixtures.project_fixture(name: "TestProject")
      preview = AppBuildsFixtures.preview_fixture(project: project)
      app_build = AppBuildsFixtures.app_build_fixture(preview: preview)

      _qa_run1 =
        QAFixtures.qa_run_fixture(app_build: app_build, status: "failed", prompt: "Test prompt 1")

      _qa_run2 =
        QAFixtures.qa_run_fixture(
          app_build: app_build,
          status: "completed",
          prompt: "Test prompt 2"
        )

      _qa_run3 =
        QAFixtures.qa_run_fixture(
          app_build: app_build,
          status: "running",
          prompt: "Test prompt 3"
        )

      # When
      recent_runs = QA.recent_qa_runs()

      # Then
      assert length(recent_runs) == 3

      # All runs should be returned regardless of status
      statuses = Enum.map(recent_runs, & &1.status)
      assert "failed" in statuses
      assert "completed" in statuses
      assert "running" in statuses
    end

    test "returns empty list when no QA runs exist" do
      # When
      recent_runs = QA.recent_qa_runs()

      # Then
      assert recent_runs == []
    end

    test "limits results to 50 most recent runs" do
      # Given
      project = ProjectsFixtures.project_fixture()
      preview = AppBuildsFixtures.preview_fixture(project: project)
      app_build = AppBuildsFixtures.app_build_fixture(preview: preview)

      Enum.each(1..60, fn i ->
        status = Enum.random(["completed", "failed", "running", "pending"])
        QAFixtures.qa_run_fixture(app_build: app_build, status: status, prompt: "Test #{i}")
      end)

      # When
      recent_runs = QA.recent_qa_runs()

      # Then
      assert length(recent_runs) == 50
    end
  end

  describe "create_qa_recording/1" do
    test "creates a recording" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()
      started_at = DateTime.utc_now()

      # When
      {:ok, recording} =
        QA.create_qa_recording(%{
          qa_run_id: qa_run.id,
          started_at: started_at,
          duration: 120_000
        })

      # Then
      assert recording.qa_run_id == qa_run.id
      assert recording.started_at == DateTime.truncate(started_at, :second)
      assert recording.duration == 120_000
    end
  end

  describe "recording_storage_key/1" do
    test "generates correct storage key for recording" do
      # Given
      qa_run_id = UUIDv7.generate()

      # When
      storage_key =
        QA.recording_storage_key(%{
          account_handle: "TestAccount",
          project_handle: "TestProject",
          qa_run_id: qa_run_id
        })

      # Then
      assert storage_key == "testaccount/testproject/qa/#{qa_run_id}/recording.mp4"
    end

    test "downcases account and project handles" do
      # Given
      qa_run_id = UUIDv7.generate()

      # When
      storage_key =
        QA.recording_storage_key(%{
          account_handle: "MixedCASE-Account",
          project_handle: "MiXeD-Project",
          qa_run_id: qa_run_id
        })

      # Then
      assert storage_key == "mixedcase-account/mixed-project/qa/#{qa_run_id}/recording.mp4"
    end
  end

  describe "create_qa_screenshot/1" do
    test "creates a screenshot with valid attributes" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      # When
      {:ok, screenshot} =
        QA.create_qa_screenshot(%{
          qa_run_id: qa_run.id
        })

      # Then
      assert screenshot.qa_run_id == qa_run.id
    end

    test "creates a screenshot with optional qa_step_id" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()
      qa_step = QAFixtures.qa_step_fixture(qa_run_id: qa_run.id)

      # When
      {:ok, screenshot} =
        QA.create_qa_screenshot(%{
          qa_run_id: qa_run.id,
          qa_step_id: qa_step.id
        })

      # Then
      assert screenshot.qa_run_id == qa_run.id
      assert screenshot.qa_step_id == qa_step.id
    end
  end

  describe "update_screenshots_with_step_id/2" do
    test "updates screenshots without step_id to have the given step_id" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()
      qa_step = QAFixtures.qa_step_fixture(qa_run_id: qa_run.id)
      other_step = QAFixtures.qa_step_fixture(qa_run_id: qa_run.id)

      {:ok, screenshot1} =
        QA.create_qa_screenshot(%{
          qa_run_id: qa_run.id,
          file_name: "screenshot1",
          title: "Screenshot 1"
        })

      {:ok, screenshot2} =
        QA.create_qa_screenshot(%{
          qa_run_id: qa_run.id,
          file_name: "screenshot2",
          title: "Screenshot 2"
        })

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
      qa_run_id = UUIDv7.generate()
      screenshot_id = UUIDv7.generate()

      # When
      storage_key =
        QA.screenshot_storage_key(%{
          account_handle: "TestAccount",
          project_handle: "TestProject",
          qa_run_id: qa_run_id,
          screenshot_id: screenshot_id
        })

      # Then
      assert storage_key ==
               "testaccount/testproject/qa/#{qa_run_id}/screenshots/#{screenshot_id}.png"
    end
  end

  describe "find_pending_qa_runs_for_app_build/1" do
    test "returns pending QA runs for app build with iOS simulator support" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            provider: :github,
            repository_full_handle: "testaccount/testproject"
          ]
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
          git_ref: preview.git_ref,
          prompt: "Test prompt 1"
        })

      {:ok, qa_run2} =
        QA.create_qa_run(%{
          app_build_id: nil,
          status: "pending",
          git_ref: preview.git_ref,
          prompt: "Test prompt 2"
        })

      {:ok, _qa_run_with_build} =
        QA.create_qa_run(%{
          app_build_id: app_build.id,
          status: "pending",
          git_ref: preview.git_ref,
          prompt: "Test prompt 3"
        })

      {:ok, _qa_run_completed} =
        QA.create_qa_run(%{
          app_build_id: nil,
          status: "completed",
          git_ref: preview.git_ref,
          prompt: "Test prompt 4"
        })

      {:ok, qa_run_different_repo} =
        QA.create_qa_run(%{
          app_build_id: nil,
          status: "pending",
          git_ref: preview.git_ref,
          prompt: "Test prompt 5"
        })

      {:ok, _qa_run_different_ref} =
        QA.create_qa_run(%{
          app_build_id: nil,
          status: "pending",
          git_ref: "refs/pull/456/merge",
          prompt: "Test prompt 6"
        })

      # When
      result = QA.find_pending_qa_runs_for_app_build(app_build)

      # Then
      assert result |> Enum.sort_by(& &1.inserted_at) |> Enum.map(& &1.id) == [
               qa_run1.id,
               qa_run2.id,
               qa_run_different_repo.id
             ]
    end

    test "returns empty list when no pending QA runs exist" do
      # Given
      project =
        ProjectsFixtures.project_fixture(
          vcs_connection: [
            provider: :github,
            repository_full_handle: "testaccount/testproject"
          ]
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
      project = ProjectsFixtures.project_fixture()

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
          vcs_connection: [
            provider: :github,
            repository_full_handle: "testaccount/testproject"
          ]
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

      screenshot =
        QAFixtures.screenshot_fixture(
          qa_run: qa_run,
          file_name: "test_screenshot",
          title: "Test Screenshot"
        )

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

      screenshot =
        QAFixtures.screenshot_fixture(
          qa_run: qa_run,
          file_name: "any_screenshot",
          title: "Any Screenshot"
        )

      # When
      result = QA.screenshot(screenshot.id)

      # Then
      assert {:ok, returned_screenshot} = result
      assert returned_screenshot.id == screenshot.id
    end

    test "returns error when screenshot doesn't exist" do
      # Given
      non_existent_id = UUIDv7.generate()
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
          vcs_connection: [
            repository_full_handle: "testaccount/testproject",
            provider: :github
          ]
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
          prompt: "Test the login functionality"
        )

      step1 =
        QAFixtures.qa_step_fixture(
          qa_run: qa_run,
          action: "Login step",
          result: "User Tap on Tuist label",
          issues: ["Login button not visible"]
        )

      step2 =
        QAFixtures.qa_step_fixture(
          qa_run: qa_run,
          action: "Navigation step",
          result: "User navigated to main screen",
          issues: []
        )

      screenshot1 =
        QAFixtures.screenshot_fixture(
          qa_run: qa_run,
          qa_step: step1
        )

      screenshot2 =
        QAFixtures.screenshot_fixture(
          qa_run: qa_run,
          qa_step: step2
        )

      expected_body = """
      ### 🤖 QA Test Summary
      **Prompt:** Test the login functionality
      **Issues:** ⚠️ 1
      **Preview:** [#{preview.display_name}](http://localhost:8080/#{project.account.name}/#{project.name}/previews/#{preview.id})
      **Commit:** [abc123def](https://github.com/testaccount/testproject/commit/abc123def456)
      **QA Session:** [View detailed results](http://localhost:8080/#{project.account.name}/#{project.name}/qa/#{qa_run.id})



      🚶 QA Steps


      <details>
      <summary>1. ⚠️ Login step</summary>

      User Tap on Tuist label

      **⚠️ Issues Found:**
      1. Login button not visible


      <img src="http://localhost:8080/#{project.account.name}/#{project.name}/qa/runs/#{qa_run.id}/screenshots/#{screenshot1.id}" alt="Screenshot 1" width="500" />
      </details>


      <details>
      <summary>2.  Navigation step</summary>

      User navigated to main screen

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
          vcs_connection: [
            repository_full_handle: "testaccount/testproject",
            provider: :github
          ]
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

  describe "list_qa_runs_for_project/3" do
    test "returns QA runs with preloaded associations" do
      # Given
      project = ProjectsFixtures.project_fixture()
      preview = AppBuildsFixtures.preview_fixture(project: project)
      app_build = AppBuildsFixtures.app_build_fixture(preview: preview)
      qa_run = QAFixtures.qa_run_fixture(app_build: app_build, prompt: "Test login")
      _qa_step = QAFixtures.qa_step_fixture(qa_run: qa_run, action: "Login attempt")

      # When
      {results, _meta} =
        QA.list_qa_runs_for_project(project, %{}, preload: [app_build: [preview: []], run_steps: []])

      # Then
      assert [result] = results
      assert result.id == qa_run.id

      refute match?(%NotLoaded{}, result.app_build)
      refute match?(%NotLoaded{}, result.app_build.preview)
      refute match?(%NotLoaded{}, result.run_steps)
    end

    test "analytics functions handle empty data" do
      empty_project = ProjectsFixtures.project_fixture()

      runs_result = QA.qa_runs_analytics(empty_project.id)
      issues_result = QA.qa_issues_analytics(empty_project.id)
      duration_result = QA.qa_duration_analytics(empty_project.id)

      assert %{
               count: 0,
               trend: runs_trend,
               values: values,
               dates: dates
             } = runs_result

      assert runs_trend == 0.0
      assert runs_trend == 0.0
      assert length(values) == 11
      assert length(dates) == 11

      assert %{
               count: 0,
               trend: issues_trend,
               values: values,
               dates: dates
             } = issues_result

      assert issues_trend == 0.0
      assert length(values) == 11
      assert length(dates) == 11

      assert %{
               total_average_duration: 0,
               trend: duration_trend,
               values: values,
               dates: dates
             } = duration_result

      assert duration_trend == 0.0
      assert length(values) == 11
      assert length(dates) == 11

      assert %{
               count: 0,
               trend: +0.0,
               values: values,
               dates: dates
             } = issues_result

      assert length(values) == 11
      assert length(dates) == 11

      assert %{
               total_average_duration: 0,
               trend: +0.0,
               values: values,
               dates: dates
             } = duration_result

      assert length(values) == 11
      assert length(dates) == 11
    end
  end

  describe "prepare_logs_with_metadata/1" do
    test "adds screenshot metadata to logs with screenshots" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      log_data =
        Jason.encode!(%{
          "name" => "screenshot",
          "content" => [
            %{
              "type" => "text",
              "content" =>
                Jason.encode!(%{
                  "screenshot_id" => "test-screenshot-123",
                  "qa_run_id" => qa_run.id,
                  "account_handle" => "test-account",
                  "project_handle" => "test-project"
                })
            }
          ]
        })

      logs = [
        %{
          id: UUIDv7.generate(),
          qa_run_id: qa_run.id,
          type: :tool_call,
          data: log_data,
          timestamp: ~N[2024-01-01 10:00:00]
        }
      ]

      # When
      result = QA.prepare_logs_with_metadata(logs)

      # Then
      assert [processed_log] = result

      assert processed_log.screenshot_metadata == %{
               screenshot_id: "test-screenshot-123",
               qa_run_id: qa_run.id,
               account_handle: "test-account",
               project_handle: "test-project"
             }
    end

    test "adds nil screenshot metadata to logs without screenshots" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      log_data = Jason.encode!(%{"message" => "Regular log message"})

      logs = [
        %{
          id: UUIDv7.generate(),
          qa_run_id: qa_run.id,
          type: :message,
          data: log_data,
          timestamp: ~N[2024-01-01 10:00:00]
        }
      ]

      # When
      result = QA.prepare_logs_with_metadata(logs)

      # Then
      assert [processed_log] = result
      assert processed_log.screenshot_metadata == nil
    end

    test "handles action tool logs with screenshots" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      log_data =
        Jason.encode!(%{
          "name" => "tap",
          "content" => [
            %{
              "type" => "text",
              "content" =>
                Jason.encode!(%{
                  "screenshot_id" => "action-screenshot-456",
                  "qa_run_id" => qa_run.id,
                  "account_handle" => "test-account",
                  "project_handle" => "test-project"
                })
            }
          ]
        })

      logs = [
        %{
          id: UUIDv7.generate(),
          qa_run_id: qa_run.id,
          type: :tool_call,
          data: log_data,
          timestamp: ~N[2024-01-01 10:00:00]
        }
      ]

      # When
      result = QA.prepare_logs_with_metadata(logs)

      # Then
      assert [processed_log] = result
      assert processed_log.screenshot_metadata.screenshot_id == "action-screenshot-456"
    end
  end

  describe "format_logs_for_display/2" do
    test "formats logs for display without filtering" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      logs = [
        %{
          id: UUIDv7.generate(),
          qa_run_id: qa_run.id,
          type: :message,
          data: Jason.encode!(%{"message" => "Test message"}),
          timestamp: ~N[2024-01-01 10:30:45],
          screenshot_metadata: nil
        },
        %{
          id: UUIDv7.generate(),
          qa_run_id: qa_run.id,
          type: :usage,
          data: Jason.encode!(%{"input" => 100, "output" => 50}),
          timestamp: ~N[2024-01-01 10:31:00],
          screenshot_metadata: nil
        }
      ]

      # When
      result = QA.format_logs_for_display(logs)

      # Then
      assert [
               %{type: "ASSISTANT", message: "Test message", timestamp: "10:30:45"},
               %{type: "TOKENS", message: "100/50", timestamp: "10:31:00"}
             ] = result
    end

    test "filters out usage logs when hide_usage_logs is true" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      logs = [
        %{
          id: UUIDv7.generate(),
          qa_run_id: qa_run.id,
          type: :message,
          data: Jason.encode!(%{"message" => "Test message"}),
          timestamp: ~N[2024-01-01 10:30:45],
          screenshot_metadata: nil
        },
        %{
          id: UUIDv7.generate(),
          qa_run_id: qa_run.id,
          type: :usage,
          data: Jason.encode!(%{"input" => 100, "output" => 50}),
          timestamp: ~N[2024-01-01 10:31:00],
          screenshot_metadata: nil
        }
      ]

      # When
      result = QA.format_logs_for_display(logs, hide_usage_logs: true)

      # Then
      assert length(result) == 1

      [message_log] = result
      assert message_log.type == "ASSISTANT"
      assert message_log.message == "Test message"
    end

    test "adds context to tool logs" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      log_data =
        Jason.encode!(%{
          "name" => "screenshot",
          "arguments" => %{"device" => "iPhone"}
        })

      logs = [
        %{
          id: UUIDv7.generate(),
          qa_run_id: qa_run.id,
          type: :tool_call,
          data: log_data,
          timestamp: ~N[2024-01-01 10:30:45],
          screenshot_metadata: nil
        }
      ]

      # When
      result = QA.format_logs_for_display(logs)

      # Then
      assert [formatted_log] = result
      assert formatted_log.type == "TOOL"
      assert formatted_log.message == "screenshot"
      assert formatted_log.context.json_data =~ "screenshot"
      assert formatted_log.context.json_data =~ "iPhone"
    end

    test "adds screenshot image URLs when screenshot metadata exists" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      logs = [
        %{
          id: UUIDv7.generate(),
          qa_run_id: qa_run.id,
          type: :tool_call,
          data: Jason.encode!(%{"name" => "screenshot"}),
          timestamp: ~N[2024-01-01 10:30:45],
          screenshot_metadata: %{
            screenshot_id: "screenshot-789",
            qa_run_id: qa_run.id,
            account_handle: "test-account",
            project_handle: "test-project"
          }
        }
      ]

      # When
      result = QA.format_logs_for_display(logs)

      # Then
      assert [formatted_log] = result

      assert formatted_log.image ==
               "/test-account/test-project/qa/runs/#{qa_run.id}/screenshots/screenshot-789"
    end

    test "handles various log message formats" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      logs = [
        # Message log
        %{
          id: UUIDv7.generate(),
          qa_run_id: qa_run.id,
          type: :message,
          data: Jason.encode!(%{"message" => "Simple message"}),
          timestamp: ~N[2024-01-01 10:00:00],
          screenshot_metadata: nil
        },
        # Tool call with type and name
        %{
          id: UUIDv7.generate(),
          qa_run_id: qa_run.id,
          type: :tool_call,
          data: Jason.encode!(%{"type" => "call", "name" => "tap_element"}),
          timestamp: ~N[2024-01-01 10:01:00],
          screenshot_metadata: nil
        },
        # Tool result
        %{
          id: UUIDv7.generate(),
          qa_run_id: qa_run.id,
          type: :tool_call_result,
          data: Jason.encode!(%{"type" => "result", "name" => "tap_result"}),
          timestamp: ~N[2024-01-01 10:02:00],
          screenshot_metadata: nil
        },
        # Tool with arguments
        %{
          id: UUIDv7.generate(),
          qa_run_id: qa_run.id,
          type: :tool_call,
          data: Jason.encode!(%{"arguments" => %{"x" => 100}, "name" => "click"}),
          timestamp: ~N[2024-01-01 10:03:00],
          screenshot_metadata: nil
        }
      ]

      # When
      result = QA.format_logs_for_display(logs)

      # Then
      assert [
               %{type: "ASSISTANT", message: "Simple message"},
               %{type: "TOOL", message: "tap_element"},
               %{type: "RESULT", message: "tap_result"},
               %{type: "TOOL", message: "click"}
             ] = result
    end
  end

  describe "prepare_log_with_metadata/1" do
    test "processes a single log with screenshot metadata" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      log_data =
        Jason.encode!(%{
          "name" => "screenshot",
          "content" => [
            %{
              "type" => "text",
              "content" =>
                Jason.encode!(%{
                  "screenshot_id" => "single-screenshot-123",
                  "qa_run_id" => qa_run.id,
                  "account_handle" => "test-account",
                  "project_handle" => "test-project"
                })
            }
          ]
        })

      log = %{
        id: UUIDv7.generate(),
        qa_run_id: qa_run.id,
        type: :tool_call,
        data: log_data,
        timestamp: ~N[2024-01-01 10:00:00]
      }

      # When
      result = QA.prepare_log_with_metadata(log)

      # Then
      assert result.screenshot_metadata == %{
               screenshot_id: "single-screenshot-123",
               qa_run_id: qa_run.id,
               account_handle: "test-account",
               project_handle: "test-project"
             }
    end

    test "processes a single log without screenshot metadata" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      log = %{
        id: UUIDv7.generate(),
        qa_run_id: qa_run.id,
        type: :message,
        data: Jason.encode!(%{"message" => "Simple message"}),
        timestamp: ~N[2024-01-01 10:00:00]
      }

      # When
      result = QA.prepare_log_with_metadata(log)

      # Then
      assert result.screenshot_metadata == nil
    end
  end

  describe "create_launch_argument_group/1" do
    test "creates a launch argument group with valid attributes" do
      # Given
      project = ProjectsFixtures.project_fixture()

      # When
      {:ok, launch_argument_group} =
        QA.create_launch_argument_group(%{
          project_id: project.id,
          name: "test-group",
          description: "Test launch argument group",
          value: "--test-arg value"
        })

      # Then
      assert launch_argument_group.project_id == project.id
      assert launch_argument_group.name == "test-group"
      assert launch_argument_group.description == "Test launch argument group"
      assert launch_argument_group.value == "--test-arg value"
    end
  end

  describe "update_launch_argument_group/2" do
    test "updates a launch argument group with valid attributes" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, launch_argument_group} =
        QA.create_launch_argument_group(%{
          project_id: project.id,
          name: "original-name",
          description: "Original description",
          value: "--original"
        })

      # When
      {:ok, updated_group} =
        QA.update_launch_argument_group(launch_argument_group, %{
          name: "updated-name",
          description: "Updated description",
          value: "--updated"
        })

      # Then
      assert updated_group.name == "updated-name"
      assert updated_group.description == "Updated description"
      assert updated_group.value == "--updated"
      assert updated_group.project_id == project.id
    end
  end

  describe "delete_launch_argument_group/1" do
    test "deletes a launch argument group successfully" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, launch_argument_group} =
        QA.create_launch_argument_group(%{
          project_id: project.id,
          name: "to-delete",
          description: "Will be deleted",
          value: "--delete-me"
        })

      # When
      {:ok, deleted_group} = QA.delete_launch_argument_group(launch_argument_group)

      # Then
      assert deleted_group.id == launch_argument_group.id
      assert {:error, :not_found} = QA.get_launch_argument_group(launch_argument_group.id)
    end
  end

  describe "get_launch_argument_group/1" do
    test "returns launch argument group when it exists" do
      # Given
      project = ProjectsFixtures.project_fixture()

      {:ok, launch_argument_group} =
        QA.create_launch_argument_group(%{
          project_id: project.id,
          name: "get-test",
          description: "Test for get",
          value: "--get-test"
        })

      # When
      {:ok, got} = QA.get_launch_argument_group(launch_argument_group.id)

      # Then
      assert got.id == launch_argument_group.id
    end

    test "returns not found error when launch argument group does not exist" do
      # Given
      non_existent_id = UUIDv7.generate()

      # When
      result = QA.get_launch_argument_group(non_existent_id)

      # Then
      assert {:error, :not_found} = result
    end
  end

  describe "enqueue_test_worker/1" do
    test "enqueues TestWorker job with correct qa_run_id" do
      # Given
      qa_run = QAFixtures.qa_run_fixture()

      expect(Tuist.QA.Workers.TestWorker, :new, fn args ->
        assert args == %{"qa_run_id" => qa_run.id}
        %Oban.Job{args: args, worker: "Tuist.QA.Workers.TestWorker"}
      end)

      expect(Oban, :insert, fn %Oban.Job{args: args} ->
        assert args == %{"qa_run_id" => qa_run.id}
        {:ok, %Oban.Job{id: 1, args: args}}
      end)

      # When
      result = QA.enqueue_test_worker(qa_run)

      # Then
      assert {:ok, %Oban.Job{id: 1, args: %{"qa_run_id" => qa_run_id}}} = result
      assert qa_run_id == qa_run.id
    end
  end
end
