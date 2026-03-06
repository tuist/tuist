defmodule Tuist.MCP.ServerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Anubis.Server.Frame
  alias Tuist.Builds
  alias Tuist.Bundles
  alias Tuist.CommandEvents
  alias Tuist.MCP.Server
  alias Tuist.Projects
  alias Tuist.Tests
  alias Tuist.Tests.Analytics
  alias Tuist.Xcode

  describe "handle_request/2" do
    test "returns tools list" do
      request = %{"method" => "tools/list", "params" => %{}}

      assert {:reply, %{"tools" => tools}, _frame} = Server.handle_request(request, Frame.new())

      tool_names = tools |> Enum.map(& &1.name) |> Enum.sort()

      assert "list_xcode_builds" in tool_names
      assert "get_xcode_build" in tool_names
      assert "list_xcode_build_targets" in tool_names
      assert "list_xcode_build_files" in tool_names
      assert "list_xcode_build_issues" in tool_names
      assert "list_xcode_build_cache_tasks" in tool_names
      assert "list_xcode_build_cas_outputs" in tool_names
      assert "list_test_runs" in tool_names
      assert "list_test_module_runs" in tool_names
      assert "list_test_suite_runs" in tool_names
      assert "list_test_case_runs" in tool_names
      assert "list_test_cases" in tool_names
      assert "get_test_case" in tool_names
      assert "get_test_run" in tool_names
      assert "get_test_case_run" in tool_names
      assert "list_bundles" in tool_names
      assert "get_bundle" in tool_names
      assert "list_bundle_artifacts" in tool_names
      assert "list_generations" in tool_names
      assert "get_generation" in tool_names
      assert "list_cache_runs" in tool_names
      assert "get_cache_run" in tool_names
      assert "list_xcode_module_cache_targets" in tool_names
      assert "list_test_case_run_attachments" in tool_names
      assert "get_test_case_run_attachment" in tool_names
      assert "list_projects" in tool_names
    end

    test "returns prompts list" do
      request = %{"method" => "prompts/list", "params" => %{}}

      assert {:reply, %{"prompts" => prompts}, _frame} = Server.handle_request(request, Frame.new())

      prompt_names = prompts |> Enum.map(& &1.name) |> Enum.sort()

      assert "fix_flaky_test" in prompt_names
      assert "compare_builds" in prompt_names
      assert "compare_test_runs" in prompt_names
      assert "compare_bundles" in prompt_names
      assert "compare_test_case" in prompt_names
      assert "compare_generations" in prompt_names
      assert "compare_cache_runs" in prompt_names
    end

    test "calls list_projects tool" do
      stub(Projects, :list_accessible_projects, fn _subject, _opts -> [] end)

      request = %{
        "method" => "tools/call",
        "params" => %{"name" => "list_projects", "arguments" => %{}}
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      assert JSON.decode!(text) == []
    end

    test "returns error for unknown tool" do
      request = %{
        "method" => "tools/call",
        "params" => %{"name" => "nonexistent", "arguments" => %{}}
      }

      assert {:error, error, _frame} = Server.handle_request(request, Frame.new())

      assert error.code == -32_602
      assert error.message == "Invalid params"
      assert message(error) == "Tool not found: nonexistent"
    end

    test "returns error for unknown method" do
      request = %{"method" => "foo/bar", "params" => %{}}

      assert {:error, error, _frame} = Server.handle_request(request, Frame.new())

      assert error.code == -32_601
      assert error.message == "Method not found"
    end

    test "returns error for tools/call without required params" do
      request = %{"method" => "tools/call", "params" => %{}}

      assert {:error, error, _frame} = Server.handle_request(request, Frame.new())

      assert error.code == -32_602
      assert message(error) == "Missing required parameter: name."
    end

    test "returns error for prompts/get without name" do
      request = %{"method" => "prompts/get", "params" => %{}}

      assert {:error, error, _frame} = Server.handle_request(request, Frame.new())

      assert error.code == -32_602
      assert message(error) == "Missing required parameter: name."
    end

    test "returns error for unknown prompt" do
      request = %{
        "method" => "prompts/get",
        "params" => %{"name" => "nonexistent", "arguments" => %{}}
      }

      assert {:error, error, _frame} = Server.handle_request(request, Frame.new())

      assert error.code == -32_602
      assert error.message == "Invalid params"
      assert message(error) == "Prompt not found: nonexistent"
    end

    test "returns prompt messages for fix_flaky_test" do
      request = %{
        "method" => "prompts/get",
        "params" => %{
          "name" => "fix_flaky_test",
          "arguments" => %{"test_case_id" => "abc-123"}
        }
      }

      assert {:reply, %{"messages" => messages}, _frame} = Server.handle_request(request, Frame.new())

      assert length(messages) == 1
      assert hd(messages)["role"] == "user"
      assert hd(messages)["content"]["text"] =~ "Fix Flaky Test"
      assert hd(messages)["content"]["text"] =~ "abc-123"
    end
  end

  describe "tool authorization" do
    test "requires :test_read to list test cases" do
      project = %{id: "project-id", name: "project-name"}
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)

      expect(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_test_cases",
          "arguments" => %{"account_handle" => "acme", "project_handle" => "app"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:error, error, _frame} = Server.handle_request(request, frame)
      assert error.code == -32_602
      assert message(error) == "You do not have access to project: acme/app"
    end

    test "requires :test_read to read a test case by id" do
      project = %{id: "project-id", name: "project-name"}
      project_id = project.id
      stub(Tests, :get_test_case_by_id, fn "test-case-id" -> {:ok, %{project_id: project.id}} end)
      stub(Projects, :get_project_by_id, fn ^project_id -> project end)

      expect(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{"name" => "get_test_case", "arguments" => %{"test_case_id" => "test-case-id"}}
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:error, error, _frame} = Server.handle_request(request, frame)
      assert error.code == -32_602
      assert message(error) == "You do not have access to this resource."
    end

    test "requires :test_read to read a test case by identifier" do
      project = %{id: "project-id", name: "project-name"}

      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)

      expect(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_test_case",
          "arguments" => %{
            "account_handle" => "acme",
            "project_handle" => "app",
            "identifier" => "AuthTests/LoginSuite/testLogin"
          }
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:error, error, _frame} = Server.handle_request(request, frame)
      assert error.code == -32_602
      assert message(error) == "You do not have access to project: acme/app"
    end

    test "returns error when get_test_case is called without test_case_id or identifier" do
      request = %{
        "method" => "tools/call",
        "params" => %{"name" => "get_test_case", "arguments" => %{}}
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:error, error, _frame} = Server.handle_request(request, frame)
      assert error.code == -32_602

      assert message(error) ==
               "Provide either test_case_id, or identifier with account_handle and project_handle."
    end

    test "requires :test_read to read a test case run" do
      project = %{id: "project-id", name: "project-name"}
      project_id = project.id

      stub(Tests, :get_test_case_run_by_id, fn "run-id", [preload: [:failures, :repetitions]] ->
        {:ok, %{project_id: project.id}}
      end)

      stub(Projects, :get_project_by_id, fn ^project_id -> project end)

      expect(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{"name" => "get_test_case_run", "arguments" => %{"test_case_run_id" => "run-id"}}
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:error, error, _frame} = Server.handle_request(request, frame)
      assert error.code == -32_602
      assert message(error) == "You do not have access to this resource."
    end

    test "requires :test_read to read a test run" do
      project = %{id: "project-id", name: "project-name"}
      project_id = project.id
      stub(Tests, :get_test, fn "test-run-id" -> {:ok, %{id: "test-run-id", project_id: project.id}} end)
      stub(Projects, :get_project_by_id, fn ^project_id -> project end)

      expect(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{"name" => "get_test_run", "arguments" => %{"test_run_id" => "test-run-id"}}
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:error, error, _frame} = Server.handle_request(request, frame)
      assert error.code == -32_602
      assert message(error) == "You do not have access to this resource."
    end
  end

  describe "build tools" do
    test "calls list_builds tool" do
      project = %{id: 1, name: "app"}
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      stub(Builds, :list_build_runs, fn _attrs ->
        {[
           %{
             id: "build-1",
             duration: 5000,
             status: "success",
             category: "clean",
             scheme: "App",
             configuration: "Debug",
             is_ci: false,
             git_branch: "main",
             git_commit_sha: "abc123",
             cacheable_tasks_count: 10,
             cacheable_task_local_hits_count: 5,
             cacheable_task_remote_hits_count: 3,
             inserted_at: ~N[2024-01-01 12:00:00]
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_xcode_builds",
          "arguments" => %{"account_handle" => "acme", "project_handle" => "app"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert length(result["builds"]) == 1
      assert hd(result["builds"])["id"] == "build-1"
      assert hd(result["builds"])["duration"] == 5000
    end

    test "calls get_build tool" do
      project = %{id: 1, name: "app"}

      stub(Builds, :get_build, fn "build-1" ->
        %{
          id: "build-1",
          duration: 5000,
          status: "success",
          category: "clean",
          scheme: "App",
          configuration: "Debug",
          xcode_version: "15.0",
          macos_version: "14.0",
          model_identifier: "MacBookPro18,1",
          is_ci: false,
          git_branch: "main",
          git_commit_sha: "abc123",
          git_ref: "refs/heads/main",
          cacheable_tasks_count: 10,
          cacheable_task_local_hits_count: 5,
          cacheable_task_remote_hits_count: 3,
          project_id: 1,
          inserted_at: ~N[2024-01-01 12:00:00]
        }
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_xcode_build",
          "arguments" => %{"build_run_id" => "build-1"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert result["id"] == "build-1"
      assert result["duration"] == 5000
      assert result["xcode_version"] == "15.0"
    end

    test "calls list_build_targets tool" do
      project = %{id: 1, name: "app"}

      stub(Builds, :get_build, fn "build-1" ->
        %{id: "build-1", project_id: 1}
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      stub(Builds, :list_build_targets, fn _attrs ->
        {[
           %{
             name: "AppTarget",
             project: "App",
             build_duration: 3000,
             compilation_duration: 2500,
             status: "success"
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_xcode_build_targets",
          "arguments" => %{"build_run_id" => "build-1"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert length(result["targets"]) == 1
      assert hd(result["targets"])["name"] == "AppTarget"
      assert hd(result["targets"])["build_duration"] == 3000
    end

    test "calls list_build_files tool" do
      project = %{id: 1, name: "app"}

      stub(Builds, :get_build, fn "build-1" -> %{id: "build-1", project_id: 1} end)
      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      stub(Builds, :list_build_files, fn _attrs ->
        {[
           %{
             type: "swift",
             target: "AppTarget",
             project: "App",
             path: "Sources/App.swift",
             compilation_duration: 150
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_xcode_build_files",
          "arguments" => %{"build_run_id" => "build-1"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert length(result["files"]) == 1
      assert hd(result["files"])["path"] == "Sources/App.swift"
    end

    test "calls list_build_issues tool" do
      project = %{id: 1, name: "app"}

      stub(Builds, :get_build, fn "build-1" -> %{id: "build-1", project_id: 1} end)
      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      stub(Builds, :list_build_issues, fn "build-1" ->
        [
          %{
            type: "error",
            target: "AppTarget",
            project: "App",
            title: "Type mismatch",
            message: "Cannot convert Int to String",
            signature: "sig123",
            step_type: "swift_compilation",
            path: "Sources/App.swift",
            starting_line: 42,
            ending_line: 42,
            starting_column: 10,
            ending_column: 20
          }
        ]
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_xcode_build_issues",
          "arguments" => %{"build_run_id" => "build-1"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert length(result) == 1
      assert hd(result)["title"] == "Type mismatch"
    end

    test "calls list_build_cache_tasks tool" do
      project = %{id: 1, name: "app"}

      stub(Builds, :get_build, fn "build-1" -> %{id: "build-1", project_id: 1} end)
      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      stub(Builds, :list_cacheable_tasks, fn _attrs ->
        {[
           %{
             type: "swift",
             status: "hit_remote",
             key: "abc123",
             read_duration: 50.0,
             write_duration: nil,
             description: "AppTarget",
             cas_output_node_ids: ["node-1"]
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_xcode_build_cache_tasks",
          "arguments" => %{"build_run_id" => "build-1"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert length(result["tasks"]) == 1
      assert hd(result["tasks"])["status"] == "hit_remote"
    end

    test "calls list_build_cas_outputs tool" do
      project = %{id: 1, name: "app"}

      stub(Builds, :get_build, fn "build-1" -> %{id: "build-1", project_id: 1} end)
      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      stub(Builds, :list_cas_outputs, fn _attrs ->
        {[
           %{
             node_id: "node-1",
             checksum: "sha256abc",
             size: 1024,
             compressed_size: 512,
             duration: 100,
             operation: "download",
             type: "swift"
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_xcode_build_cas_outputs",
          "arguments" => %{"build_run_id" => "build-1"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert length(result["outputs"]) == 1
      assert hd(result["outputs"])["node_id"] == "node-1"
      assert hd(result["outputs"])["size"] == 1024
    end

    test "requires :build_read authorization" do
      project = %{id: 1, name: "app"}
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)

      expect(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_xcode_builds",
          "arguments" => %{"account_handle" => "acme", "project_handle" => "app"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:error, error, _frame} = Server.handle_request(request, frame)
      assert error.code == -32_602
      assert message(error) == "You do not have access to project: acme/app"
    end
  end

  describe "test tools" do
    test "calls list_test_runs tool" do
      project = %{id: 1, name: "app"}
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)
      stub(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project -> :ok end)

      stub(Tests, :list_test_runs, fn _attrs ->
        {[
           %{
             id: "run-1",
             duration: 10_000,
             status: "success",
             is_ci: true,
             is_flaky: false,
             scheme: "AppTests",
             git_branch: "main",
             git_commit_sha: "abc123",
             ran_at: ~N[2024-01-01 12:00:00]
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      stub(Analytics, :test_runs_metrics, fn _runs ->
        [%{test_run_id: "run-1", total_tests: 50, ran_tests: 45, skipped_tests: 5}]
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_test_runs",
          "arguments" => %{"account_handle" => "acme", "project_handle" => "app"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert length(result["test_runs"]) == 1
      assert hd(result["test_runs"])["total_test_count"] == 50
    end

    test "calls list_test_module_runs tool" do
      project = %{id: 1, name: "app"}

      stub(Tests, :get_test, fn "run-1" ->
        {:ok, %{id: "run-1", project_id: 1}}
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project -> :ok end)

      stub(Tests, :list_test_module_runs, fn _attrs ->
        {[
           %{
             name: "AuthTests",
             status: "success",
             is_flaky: false,
             duration: 5000,
             test_suite_count: 3,
             test_case_count: 15,
             avg_test_case_duration: 333
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_test_module_runs",
          "arguments" => %{"test_run_id" => "run-1"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert length(result["modules"]) == 1
      assert hd(result["modules"])["name"] == "AuthTests"
    end

    test "calls list_test_suite_runs tool" do
      project = %{id: 1, name: "app"}

      stub(Tests, :get_test, fn "run-1" ->
        {:ok, %{id: "run-1", project_id: 1}}
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project -> :ok end)

      stub(Tests, :list_test_suite_runs, fn _attrs ->
        {[
           %{
             name: "LoginSuite",
             status: "success",
             is_flaky: false,
             duration: 2000,
             test_case_count: 5,
             avg_test_case_duration: 400,
             test_module_run_id: "mod-1"
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_test_suite_runs",
          "arguments" => %{"test_run_id" => "run-1"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert length(result["suites"]) == 1
      assert hd(result["suites"])["name"] == "LoginSuite"
    end

    test "calls list_test_case_runs tool" do
      project = %{id: 1, name: "app"}
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)
      stub(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project -> :ok end)

      stub(Tests, :list_test_case_runs, fn _attrs ->
        {[
           %{
             id: "tcr-1",
             test_case_id: "tc-1",
             test_run_id: "run-1",
             name: "testLogin",
             module_name: "AuthTests",
             suite_name: "LoginSuite",
             status: "success",
             duration: 200,
             is_ci: true,
             is_flaky: false,
             git_branch: "main",
             git_commit_sha: "abc123",
             ran_at: ~N[2024-01-01 12:00:00]
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_test_case_runs",
          "arguments" => %{
            "account_handle" => "acme",
            "project_handle" => "app",
            "test_case_id" => "tc-1"
          }
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert length(result["test_case_runs"]) == 1
      assert hd(result["test_case_runs"])["name"] == "testLogin"
    end

    test "calls list_test_cases tool" do
      project = %{id: 1, name: "app"}
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)
      stub(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project -> :ok end)

      stub(Tests, :list_test_cases, fn 1, _attrs ->
        {[
           %{
             id: "tc-1",
             name: "testLogin",
             module_name: "AuthModule",
             suite_name: "AuthSuite",
             is_flaky: false,
             is_quarantined: false,
             last_status: :success,
             last_duration: 1500,
             last_ran_at: ~N[2024-01-01 12:00:00],
             avg_duration: 1400
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_test_cases",
          "arguments" => %{"account_handle" => "acme", "project_handle" => "app"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert length(result["test_cases"]) == 1
      assert hd(result["test_cases"])["name"] == "testLogin"
      assert hd(result["test_cases"])["module_name"] == "AuthModule"
    end

    test "calls get_test_run tool" do
      project = %{id: 1, name: "app"}

      stub(Tests, :get_test, fn "run-1" ->
        {:ok,
         %{
           id: "run-1",
           status: :success,
           duration: 10_000,
           is_ci: true,
           is_flaky: false,
           scheme: "AppTests",
           git_branch: "main",
           git_commit_sha: "abc123",
           ran_at: ~N[2024-01-01 12:00:00],
           project_id: 1
         }}
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project -> :ok end)

      stub(Analytics, :get_test_run_metrics, fn "run-1" ->
        %{total_count: 50, failed_count: 2, flaky_count: 1, avg_duration: 300}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_test_run",
          "arguments" => %{"test_run_id" => "run-1"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert result["id"] == "run-1"
      assert result["total_test_count"] == 50
      assert result["failed_test_count"] == 2
    end

    test "calls get_test_case_run tool" do
      project = %{id: 1, name: "app"}

      stub(Tests, :get_test_case_run_by_id, fn "tcr-1", [preload: [:failures, :repetitions]] ->
        {:ok,
         %{
           id: "tcr-1",
           test_case_id: "tc-1",
           test_run_id: "run-1",
           name: "testLogin",
           module_name: "AuthModule",
           suite_name: "AuthSuite",
           status: :failure,
           duration: 500,
           is_ci: true,
           is_flaky: false,
           is_new: false,
           scheme: "AppTests",
           git_branch: "main",
           git_commit_sha: "abc123",
           ran_at: ~N[2024-01-01 12:00:00],
           project_id: 1,
           failures: [
             %{
               message: "XCTAssertEqual failed",
               path: "Tests/AuthTests.swift",
               line_number: 42,
               issue_type: "assertion_failure"
             }
           ],
           repetitions: []
         }}
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project -> :ok end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_test_case_run",
          "arguments" => %{"test_case_run_id" => "tcr-1"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert result["id"] == "tcr-1"
      assert result["name"] == "testLogin"
      assert result["status"] == "failure"
      assert length(result["failures"]) == 1
      assert hd(result["failures"])["message"] == "XCTAssertEqual failed"
    end
  end

  describe "bundle tools" do
    test "calls list_bundles tool" do
      project = %{id: 1, name: "app"}
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)
      stub(Tuist.Authorization, :authorize, fn :bundle_read, :subject, ^project -> :ok end)

      stub(Bundles, :list_bundles, fn _attrs ->
        {[
           %{
             id: "bundle-1",
             name: "MyApp",
             app_bundle_id: "com.acme.app",
             version: "1.0.0",
             type: :ipa,
             supported_platforms: [:ios],
             install_size: 50_000_000,
             download_size: 30_000_000,
             git_branch: "main",
             git_commit_sha: "abc123",
             inserted_at: ~U[2024-01-01 12:00:00Z]
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_bundles",
          "arguments" => %{"account_handle" => "acme", "project_handle" => "app"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert length(result["bundles"]) == 1
      assert hd(result["bundles"])["name"] == "MyApp"
      assert hd(result["bundles"])["install_size"] == 50_000_000
    end

    test "calls get_bundle tool" do
      project = %{id: 1, name: "app"}

      stub(Bundles, :get_bundle, fn "bundle-1" ->
        {:ok,
         %{
           id: "bundle-1",
           name: "MyApp",
           app_bundle_id: "com.acme.app",
           version: "1.0.0",
           type: :ipa,
           supported_platforms: [:ios],
           install_size: 50_000_000,
           download_size: 30_000_000,
           git_branch: "main",
           git_commit_sha: "abc123",
           git_ref: "refs/tags/v1.0.0",
           project_id: 1,
           inserted_at: ~U[2024-01-01 12:00:00Z]
         }}
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :bundle_read, :subject, ^project -> :ok end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_bundle",
          "arguments" => %{"bundle_id" => "bundle-1"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert result["id"] == "bundle-1"
      assert result["install_size"] == 50_000_000
      refute Map.has_key?(result, "artifacts")
    end

    test "requires :bundle_read authorization" do
      project = %{id: 1, name: "app"}
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)

      expect(Tuist.Authorization, :authorize, fn :bundle_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_bundles",
          "arguments" => %{"account_handle" => "acme", "project_handle" => "app"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:error, error, _frame} = Server.handle_request(request, frame)
      assert error.code == -32_602
      assert message(error) == "You do not have access to project: acme/app"
    end

    test "calls list_bundle_artifacts tool" do
      project = %{id: 1, name: "app"}

      stub(Bundles, :get_bundle, fn "bundle-1" ->
        {:ok,
         %{
           id: "bundle-1",
           project_id: 1
         }}
      end)

      stub(Bundles, :list_bundle_artifacts, fn "bundle-1", [] ->
        [
          %{
            id: "art-1",
            artifact_type: :directory,
            path: "MyApp.app",
            size: 50_000_000,
            shasum: "sha256abc"
          },
          %{
            id: "art-2",
            artifact_type: :file,
            path: "MyApp.app/MyApp",
            size: 20_000_000,
            shasum: "sha256def"
          }
        ]
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :bundle_read, :subject, ^project -> :ok end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_bundle_artifacts",
          "arguments" => %{"bundle_id" => "bundle-1"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert length(result["artifacts"]) == 2
      assert result["bundle_id"] == "bundle-1"
      assert result["parent_artifact_id"] == nil

      dir = Enum.find(result["artifacts"], &(&1["artifact_type"] == "directory"))
      assert dir["has_children"] == true

      file = Enum.find(result["artifacts"], &(&1["artifact_type"] == "file"))
      assert file["has_children"] == false
    end

    test "calls list_bundle_artifacts with parent_artifact_id" do
      project = %{id: 1, name: "app"}

      stub(Bundles, :get_bundle, fn "bundle-1" ->
        {:ok,
         %{
           id: "bundle-1",
           project_id: 1
         }}
      end)

      stub(Bundles, :list_bundle_artifacts, fn "bundle-1", [parent_artifact_id: "art-1"] ->
        [
          %{
            id: "art-3",
            artifact_type: :file,
            path: "MyApp.app/Info.plist",
            size: 1_000,
            shasum: "sha256ghi"
          }
        ]
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :bundle_read, :subject, ^project -> :ok end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_bundle_artifacts",
          "arguments" => %{"bundle_id" => "bundle-1", "parent_artifact_id" => "art-1"}
        }
      }

      frame = Frame.new(%{current_subject: :subject})

      assert {:reply, %{"content" => [%{"type" => "text", "text" => text}]}, _frame} =
               Server.handle_request(request, frame)

      result = JSON.decode!(text)
      assert length(result["artifacts"]) == 1
      assert result["parent_artifact_id"] == "art-1"
    end
  end

  describe "comparison prompts" do
    test "returns compare_builds prompt messages with default branch" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{default_branch: "develop", build_system: :xcode}
      end)

      request = %{
        "method" => "prompts/get",
        "params" => %{
          "name" => "compare_builds",
          "arguments" => %{
            "head" => "build-head-id",
            "account_handle" => "acme",
            "project_handle" => "app"
          }
        }
      }

      assert {:reply, %{"messages" => messages}, _frame} = Server.handle_request(request, Frame.new())

      assert length(messages) == 1
      text = hd(messages)["content"]["text"]
      assert text =~ "Compare Builds"
      assert text =~ "build-head-id"
      assert text =~ "list_xcode_build_targets"
      assert text =~ "git_branch=develop"
    end

    test "returns compare_test_runs prompt messages" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{default_branch: "main", build_system: :xcode}
      end)

      request = %{
        "method" => "prompts/get",
        "params" => %{
          "name" => "compare_test_runs",
          "arguments" => %{
            "base" => "run-base-id",
            "head" => "run-head-id",
            "account_handle" => "acme",
            "project_handle" => "app"
          }
        }
      }

      assert {:reply, %{"messages" => messages}, _frame} = Server.handle_request(request, Frame.new())

      assert length(messages) == 1
      text = hd(messages)["content"]["text"]
      assert text =~ "Compare Test Runs"
      assert text =~ "run-base-id"
      assert text =~ "run-head-id"
    end

    test "returns compare_bundles prompt messages" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{default_branch: "main", build_system: :xcode}
      end)

      request = %{
        "method" => "prompts/get",
        "params" => %{
          "name" => "compare_bundles",
          "arguments" => %{
            "account_handle" => "acme",
            "project_handle" => "app"
          }
        }
      }

      assert {:reply, %{"messages" => messages}, _frame} = Server.handle_request(request, Frame.new())

      assert length(messages) == 1
      text = hd(messages)["content"]["text"]
      assert text =~ "Compare Bundles"
      assert text =~ "install_size"
    end

    test "returns compare_builds prompt without handles when using dashboard URLs" do
      request = %{
        "method" => "prompts/get",
        "params" => %{
          "name" => "compare_builds",
          "arguments" => %{
            "base" => "https://tuist.dev/acme/app/builds/build-runs/base-id",
            "head" => "https://tuist.dev/acme/app/builds/build-runs/head-id"
          }
        }
      }

      assert {:reply, %{"messages" => messages}, _frame} = Server.handle_request(request, Frame.new())

      assert length(messages) == 1
      text = hd(messages)["content"]["text"]
      assert text =~ "Compare Builds"
      assert text =~ "base-id"
      assert text =~ "head-id"
    end

    test "returns compare_test_case prompt messages" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{default_branch: "main", build_system: :xcode}
      end)

      request = %{
        "method" => "prompts/get",
        "params" => %{
          "name" => "compare_test_case",
          "arguments" => %{
            "test_case_id" => "tc-123",
            "head_branch" => "feature/login",
            "account_handle" => "acme",
            "project_handle" => "app"
          }
        }
      }

      assert {:reply, %{"messages" => messages}, _frame} = Server.handle_request(request, Frame.new())

      assert length(messages) == 1
      text = hd(messages)["content"]["text"]
      assert text =~ "Compare Test Case"
      assert text =~ "tc-123"
      assert text =~ "feature/login"
    end

    test "returns compare_generations prompt messages with default branch" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{default_branch: "develop", build_system: :xcode}
      end)

      request = %{
        "method" => "prompts/get",
        "params" => %{
          "name" => "compare_generations",
          "arguments" => %{
            "head" => "gen-head-id",
            "account_handle" => "acme",
            "project_handle" => "app"
          }
        }
      }

      assert {:reply, %{"messages" => messages}, _frame} = Server.handle_request(request, Frame.new())

      assert length(messages) == 1
      text = hd(messages)["content"]["text"]
      assert text =~ "Compare Generations"
      assert text =~ "gen-head-id"
      assert text =~ "list_xcode_module_cache_targets"
      assert text =~ "git_branch=develop"
    end

    test "returns compare_cache_runs prompt messages" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{default_branch: "main", build_system: :xcode}
      end)

      request = %{
        "method" => "prompts/get",
        "params" => %{
          "name" => "compare_cache_runs",
          "arguments" => %{
            "base" => "cr-base-id",
            "head" => "cr-head-id",
            "account_handle" => "acme",
            "project_handle" => "app"
          }
        }
      }

      assert {:reply, %{"messages" => messages}, _frame} = Server.handle_request(request, Frame.new())

      assert length(messages) == 1
      text = hd(messages)["content"]["text"]
      assert text =~ "Compare Cache Runs"
      assert text =~ "cr-base-id"
      assert text =~ "cr-head-id"
    end
  end

  describe "generation and cache run tools" do
    test "calls list_generations tool" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{id: 1, account: %{name: "acme"}, name: "app"}
      end)

      stub(Tuist.Authorization, :authorize, fn _action, _subject, _project -> :ok end)

      stub(CommandEvents, :list_command_events, fn _attrs ->
        {[
           %{
             id: "gen-1",
             name: "generate",
             duration: 5000,
             status: 0,
             tuist_version: "4.0.0",
             swift_version: "5.10",
             macos_version: "14.0",
             is_ci: false,
             git_branch: "main",
             git_commit_sha: "abc123",
             git_ref: nil,
             command_arguments: nil,
             cacheable_targets: ["App", "Core"],
             local_cache_target_hits: ["Core"],
             remote_cache_target_hits: [],
             created_at: ~N[2025-01-01 12:00:00],
             user_account_name: nil
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_generations",
          "arguments" => %{
            "account_handle" => "acme",
            "project_handle" => "app"
          }
        }
      }

      assert {:reply, %{"content" => [%{"text" => json}]}, _frame} =
               Server.handle_request(request, Frame.new())

      data = Jason.decode!(json)
      assert length(data["generations"]) == 1
      assert hd(data["generations"])["id"] == "gen-1"
      assert hd(data["generations"])["status"] == "success"
      assert hd(data["generations"])["cacheable_targets"] == ["App", "Core"]
    end

    test "calls get_generation tool" do
      stub(CommandEvents, :get_command_event_by_id, fn "gen-1" ->
        {:ok,
         %{
           id: "gen-1",
           name: "generate",
           project_id: 1,
           duration: 5000,
           status: 0,
           tuist_version: "4.0.0",
           swift_version: "5.10",
           macos_version: "14.0",
           is_ci: false,
           git_branch: "main",
           git_commit_sha: "abc123",
           git_ref: nil,
           command_arguments: nil,
           cacheable_targets: ["App"],
           local_cache_target_hits: [],
           remote_cache_target_hits: [],
           created_at: ~N[2025-01-01 12:00:00]
         }}
      end)

      stub(Projects, :get_project_by_id, fn 1 ->
        %{id: 1, account: %{name: "acme"}, name: "app"}
      end)

      stub(Tuist.Authorization, :authorize, fn _action, _subject, _project -> :ok end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_generation",
          "arguments" => %{"generation_id" => "gen-1"}
        }
      }

      assert {:reply, %{"content" => [%{"text" => json}]}, _frame} =
               Server.handle_request(request, Frame.new())

      data = Jason.decode!(json)
      assert data["id"] == "gen-1"
      assert data["status"] == "success"
    end

    test "get_generation rejects non-generate events" do
      stub(CommandEvents, :get_command_event_by_id, fn "cache-1" ->
        {:ok, %{id: "cache-1", name: "cache", project_id: 1}}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_generation",
          "arguments" => %{"generation_id" => "cache-1"}
        }
      }

      assert {:error, error, _frame} = Server.handle_request(request, Frame.new())
      assert message(error) =~ "Generation not found"
    end

    test "calls list_cache_runs tool" do
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" ->
        %{id: 1, account: %{name: "acme"}, name: "app"}
      end)

      stub(Tuist.Authorization, :authorize, fn _action, _subject, _project -> :ok end)

      stub(CommandEvents, :list_command_events, fn _attrs ->
        {[
           %{
             id: "cr-1",
             name: "cache",
             duration: 3000,
             status: 0,
             tuist_version: "4.0.0",
             swift_version: "5.10",
             macos_version: "14.0",
             is_ci: true,
             git_branch: "main",
             git_commit_sha: "def456",
             git_ref: nil,
             command_arguments: "warm",
             cacheable_targets: ["App", "Core", "UI"],
             local_cache_target_hits: ["Core"],
             remote_cache_target_hits: ["UI"],
             created_at: ~N[2025-01-01 12:00:00],
             user_account_name: nil
           }
         ],
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_cache_runs",
          "arguments" => %{
            "account_handle" => "acme",
            "project_handle" => "app"
          }
        }
      }

      assert {:reply, %{"content" => [%{"text" => json}]}, _frame} =
               Server.handle_request(request, Frame.new())

      data = Jason.decode!(json)
      assert length(data["cache_runs"]) == 1
      assert hd(data["cache_runs"])["id"] == "cr-1"
    end

    test "calls get_cache_run tool" do
      stub(CommandEvents, :get_command_event_by_id, fn "cr-1" ->
        {:ok,
         %{
           id: "cr-1",
           name: "cache",
           project_id: 1,
           duration: 3000,
           status: 0,
           tuist_version: "4.0.0",
           swift_version: "5.10",
           macos_version: "14.0",
           is_ci: true,
           git_branch: "main",
           git_commit_sha: "def456",
           git_ref: nil,
           command_arguments: "warm",
           cacheable_targets: ["App"],
           local_cache_target_hits: [],
           remote_cache_target_hits: [],
           created_at: ~N[2025-01-01 12:00:00]
         }}
      end)

      stub(Projects, :get_project_by_id, fn 1 ->
        %{id: 1, account: %{name: "acme"}, name: "app"}
      end)

      stub(Tuist.Authorization, :authorize, fn _action, _subject, _project -> :ok end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_cache_run",
          "arguments" => %{"cache_run_id" => "cr-1"}
        }
      }

      assert {:reply, %{"content" => [%{"text" => json}]}, _frame} =
               Server.handle_request(request, Frame.new())

      data = Jason.decode!(json)
      assert data["id"] == "cr-1"
      assert data["command_arguments"] == "warm"
    end

    test "calls list_xcode_module_cache_targets tool" do
      stub(CommandEvents, :get_command_event_by_id, fn "gen-1" ->
        {:ok,
         %{
           id: "gen-1",
           name: "generate",
           project_id: 1,
           created_at: ~N[2025-01-01 12:00:00]
         }}
      end)

      stub(Projects, :get_project_by_id, fn 1 ->
        %{id: 1, account: %{name: "acme"}, name: "app"}
      end)

      stub(Tuist.Authorization, :authorize, fn _action, _subject, _project -> :ok end)

      stub(Xcode, :binary_cache_analytics, fn _event, _flop_params ->
        {%{
           cacheable_targets: [
             %{
               name: "App",
               binary_cache_hit: :miss,
               binary_cache_hash: "hash-abc",
               product: "App.app",
               bundle_id: "com.example.app",
               product_name: "App",
               external_hash: "",
               sources_hash: "src-hash",
               resources_hash: "res-hash",
               copy_files_hash: "",
               core_data_models_hash: "",
               target_scripts_hash: "",
               environment_hash: "",
               headers_hash: "",
               deployment_target_hash: "",
               info_plist_hash: "",
               entitlements_hash: "",
               dependencies_hash: "dep-hash",
               project_settings_hash: "",
               target_settings_hash: "",
               buildable_folders_hash: "",
               destinations: ["iphone"],
               additional_strings: []
             }
           ]
         },
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 1,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_xcode_module_cache_targets",
          "arguments" => %{"run_id" => "gen-1"}
        }
      }

      assert {:reply, %{"content" => [%{"text" => json}]}, _frame} =
               Server.handle_request(request, Frame.new())

      data = Jason.decode!(json)
      assert length(data["targets"]) == 1
      target = hd(data["targets"])
      assert target["name"] == "App"
      assert target["cache_status"] == "miss"
      assert target["cache_hash"] == "hash-abc"
      assert target["subhashes"]["sources"] == "src-hash"
      assert target["subhashes"]["dependencies"] == "dep-hash"
      refute Map.has_key?(target["subhashes"], "headers")
    end
  end

  describe "test case run attachment tools" do
    test "list_test_case_run_attachments returns attachments" do
      stub(Tests, :get_test_case_run_by_id, fn "run-1", [preload: [:attachments]] ->
        {:ok,
         %{
           id: "run-1",
           project_id: 1,
           attachments: [
             %{id: "att-1", file_name: "crash-report.ips"},
             %{id: "att-2", file_name: "screenshot.png"}
           ]
         }}
      end)

      stub(Projects, :get_project_by_id, fn 1 ->
        %{id: 1, account: %{name: "acme"}, name: "app"}
      end)

      stub(Tuist.Authorization, :authorize, fn _action, _subject, _project -> :ok end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "list_test_case_run_attachments",
          "arguments" => %{"test_case_run_id" => "run-1"}
        }
      }

      assert {:reply, %{"content" => [%{"text" => json}]}, _frame} =
               Server.handle_request(request, Frame.new())

      data = Jason.decode!(json)
      assert data["test_case_run_id"] == "run-1"
      assert length(data["attachments"]) == 2

      att1 = Enum.find(data["attachments"], &(&1["id"] == "att-1"))
      assert att1["file_name"] == "crash-report.ips"
      assert att1["type"] == "crash_report"

      att2 = Enum.find(data["attachments"], &(&1["id"] == "att-2"))
      assert att2["file_name"] == "screenshot.png"
      assert att2["type"] == "image"
    end

    test "get_test_case_run_attachment returns download URL" do
      stub(Tests, :get_test_case_run_by_id, fn "run-1", [preload: [:attachments]] ->
        {:ok,
         %{
           id: "run-1",
           project_id: 1,
           attachments: [
             %{id: "att-1", file_name: "crash-report.ips"}
           ]
         }}
      end)

      stub(Projects, :get_project_by_id, fn 1 ->
        %{id: 1, account: %{name: "acme"}, name: "app"}
      end)

      stub(Tuist.Authorization, :authorize, fn _action, _subject, _project -> :ok end)

      stub(Tuist.Storage, :generate_download_url, fn _key, _account, _opts ->
        "https://s3.example.com/presigned-url"
      end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_test_case_run_attachment",
          "arguments" => %{
            "test_case_run_id" => "run-1",
            "attachment_id" => "att-1"
          }
        }
      }

      assert {:reply, %{"content" => [%{"text" => json}]}, _frame} =
               Server.handle_request(request, Frame.new())

      data = Jason.decode!(json)
      assert data["id"] == "att-1"
      assert data["file_name"] == "crash-report.ips"
      assert data["download_url"] == "https://s3.example.com/presigned-url"
      assert data["expires_in_seconds"] == 3600
    end

    test "get_test_case_run_attachment returns error for missing attachment" do
      stub(Tests, :get_test_case_run_by_id, fn "run-1", [preload: [:attachments]] ->
        {:ok, %{id: "run-1", project_id: 1, attachments: []}}
      end)

      stub(Projects, :get_project_by_id, fn 1 ->
        %{id: 1, account: %{name: "acme"}, name: "app"}
      end)

      stub(Tuist.Authorization, :authorize, fn _action, _subject, _project -> :ok end)

      request = %{
        "method" => "tools/call",
        "params" => %{
          "name" => "get_test_case_run_attachment",
          "arguments" => %{
            "test_case_run_id" => "run-1",
            "attachment_id" => "nonexistent"
          }
        }
      }

      assert {:error, error, _frame} = Server.handle_request(request, Frame.new())
      assert message(error) =~ "Attachment not found"
    end
  end

  defp message(error), do: Map.get(error.data, :message) || Map.get(error.data, "message")
end
