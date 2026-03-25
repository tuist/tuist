defmodule Tuist.MCP.Components.Tools.TestToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.MCP.Components.Tools.GetTestCase
  alias Tuist.MCP.Components.Tools.GetTestCaseRun
  alias Tuist.MCP.Components.Tools.GetTestRun
  alias Tuist.MCP.Components.Tools.ListTestCaseRunAttachments
  alias Tuist.MCP.Components.Tools.ListTestCaseRuns
  alias Tuist.MCP.Components.Tools.ListTestCases
  alias Tuist.MCP.Components.Tools.ListTestModuleRuns
  alias Tuist.MCP.Components.Tools.ListTestRuns
  alias Tuist.MCP.Components.Tools.ListTestSuiteRuns
  alias Tuist.MCP.Components.Tools.ListXcodeSelectiveTestingTargets
  alias Tuist.Projects
  alias Tuist.Tests
  alias Tuist.Tests.Analytics
  alias Tuist.Xcode

  describe "list_test_runs" do
    test "returns paginated test runs with metrics" do
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

      stub(Analytics, :test_runs_metrics, fn _project_id, _runs ->
        [%{test_run_id: "run-1", total_tests: 50, ran_tests: 45, skipped_tests: 5, xcode_selective_testing_local_hits: 3, xcode_selective_testing_remote_hits: 2, xcode_selective_testing_targets: 10}]
      end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               ListTestRuns.call(conn, %{"account_handle" => "acme", "project_handle" => "app"})

      result = JSON.decode!(text)
      assert length(result["test_runs"]) == 1
      assert hd(result["test_runs"])["total_test_count"] == 50

      run = hd(result["test_runs"])
      assert run["xcode_selective_testing_targets"] == 10
      assert run["xcode_selective_testing_local_hits"] == 3
      assert run["xcode_selective_testing_remote_hits"] == 2
    end
  end

  describe "list_test_module_runs" do
    test "returns module runs for a test run" do
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

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               ListTestModuleRuns.call(conn, %{"test_run_id" => "run-1"})

      result = JSON.decode!(text)
      assert length(result["modules"]) == 1
      assert hd(result["modules"])["name"] == "AuthTests"
    end
  end

  describe "list_test_suite_runs" do
    test "returns suite runs for a test run" do
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

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               ListTestSuiteRuns.call(conn, %{"test_run_id" => "run-1"})

      result = JSON.decode!(text)
      assert length(result["suites"]) == 1
      assert hd(result["suites"])["name"] == "LoginSuite"
    end
  end

  describe "list_test_case_runs" do
    test "returns test case runs" do
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

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               ListTestCaseRuns.call(conn, %{
                 "account_handle" => "acme",
                 "project_handle" => "app",
                 "test_case_id" => "tc-1"
               })

      result = JSON.decode!(text)
      assert length(result["test_case_runs"]) == 1
      assert hd(result["test_case_runs"])["name"] == "testLogin"
    end
  end

  describe "list_test_cases" do
    test "returns test cases" do
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

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               ListTestCases.call(conn, %{"account_handle" => "acme", "project_handle" => "app"})

      result = JSON.decode!(text)
      assert length(result["test_cases"]) == 1
      assert hd(result["test_cases"])["name"] == "testLogin"
      assert hd(result["test_cases"])["module_name"] == "AuthModule"
    end

    test "requires :test_read authorization" do
      project = %{id: "project-id", name: "project-name"}
      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)

      expect(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} =
               ListTestCases.call(conn, %{"account_handle" => "acme", "project_handle" => "app"})

      assert text =~ "You do not have access to project: acme/app"
    end
  end

  describe "get_test_case" do
    test "requires :test_read to read by id" do
      project = %{id: "project-id", name: "project-name"}
      project_id = project.id
      stub(Tests, :get_test_case_by_id, fn "test-case-id" -> {:ok, %{project_id: project.id}} end)
      stub(Projects, :get_project_by_id, fn ^project_id -> project end)

      expect(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} =
               GetTestCase.call(conn, %{"test_case_id" => "test-case-id"})

      assert text =~ "You do not have access to this resource."
    end

    test "requires :test_read to read by identifier" do
      project = %{id: "project-id", name: "project-name"}

      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)

      expect(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} =
               GetTestCase.call(conn, %{
                 "account_handle" => "acme",
                 "project_handle" => "app",
                 "identifier" => "AuthTests/LoginSuite/testLogin"
               })

      assert text =~ "You do not have access to project: acme/app"
    end

    test "returns error without test_case_id or identifier" do
      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} =
               GetTestCase.call(conn, %{})

      assert text =~
               "Provide either test_case_id, or identifier with account_handle and project_handle."
    end
  end

  describe "get_test_run" do
    test "returns test run with metrics" do
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

      stub(Analytics, :get_test_run_selective_testing_metrics, fn "run-1" ->
        %{xcode_selective_testing_local_hits: 10, xcode_selective_testing_remote_hits: 5, xcode_selective_testing_targets: 20}
      end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               GetTestRun.call(conn, %{"test_run_id" => "run-1"})

      result = JSON.decode!(text)
      assert result["id"] == "run-1"
      assert result["total_test_count"] == 50
      assert result["failed_test_count"] == 2
      assert result["xcode_selective_testing_targets"] == 20
      assert result["xcode_selective_testing_local_hits"] == 10
      assert result["xcode_selective_testing_remote_hits"] == 5
    end

    test "requires :test_read authorization" do
      project = %{id: "project-id", name: "project-name"}
      project_id = project.id
      stub(Tests, :get_test, fn "test-run-id" -> {:ok, %{id: "test-run-id", project_id: project.id}} end)
      stub(Projects, :get_project_by_id, fn ^project_id -> project end)

      expect(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} =
               GetTestRun.call(conn, %{"test_run_id" => "test-run-id"})

      assert text =~ "You do not have access to this resource."
    end
  end

  describe "get_test_case_run" do
    test "returns test case run with failures" do
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

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               GetTestCaseRun.call(conn, %{"test_case_run_id" => "tcr-1"})

      result = JSON.decode!(text)
      assert result["id"] == "tcr-1"
      assert result["name"] == "testLogin"
      assert result["status"] == "failure"
      assert length(result["failures"]) == 1
      assert hd(result["failures"])["message"] == "XCTAssertEqual failed"
    end

    test "requires :test_read authorization" do
      project = %{id: "project-id", name: "project-name"}
      project_id = project.id

      stub(Tests, :get_test_case_run_by_id, fn "run-id", [preload: [:failures, :repetitions]] ->
        {:ok, %{project_id: project.id}}
      end)

      stub(Projects, :get_project_by_id, fn ^project_id -> project end)

      expect(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project ->
        {:error, :forbidden}
      end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}], "isError" => true} =
               GetTestCaseRun.call(conn, %{"test_case_run_id" => "run-id"})

      assert text =~ "You do not have access to this resource."
    end
  end

  describe "test case run attachments" do
    test "list_test_case_run_attachments returns attachments with download URLs" do
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

      stub(Tuist.Storage, :generate_download_url, fn _key, _account, _opts ->
        "https://s3.example.com/presigned-url"
      end)

      conn = %Plug.Conn{assigns: %{}}

      assert %{"content" => [%{"text" => json}]} =
               ListTestCaseRunAttachments.call(conn, %{"test_case_run_id" => "run-1"})

      data = Jason.decode!(json)
      assert data["test_case_run_id"] == "run-1"
      assert length(data["attachments"]) == 2

      att1 = Enum.find(data["attachments"], &(&1["id"] == "att-1"))
      assert att1["file_name"] == "crash-report.ips"
      assert att1["type"] == "crash_report"
      assert att1["download_url"] == "https://s3.example.com/presigned-url"

      att2 = Enum.find(data["attachments"], &(&1["id"] == "att-2"))
      assert att2["file_name"] == "screenshot.png"
      assert att2["type"] == "image"
      assert att2["download_url"] == "https://s3.example.com/presigned-url"
    end
  end

  describe "list_xcode_selective_testing_targets" do
    test "returns targets with selective testing status" do
      project = %{id: 1, name: "app"}

      stub(Tests, :get_test, fn "run-1" ->
        {:ok, %{id: "run-1", project_id: 1}}
      end)

      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project -> :ok end)

      stub(Xcode, :selective_testing_analytics, fn %{id: "run-1"}, _flop_params ->
        {%{
           test_modules: [
             %{name: "AuthTests", selective_testing_hit: :miss, selective_testing_hash: "abc123"},
             %{name: "CoreTests", selective_testing_hit: :local, selective_testing_hash: "def456"},
             %{name: "UITests", selective_testing_hit: :remote, selective_testing_hash: "ghi789"}
           ]
         },
         %{
           has_next_page?: false,
           has_previous_page?: false,
           total_count: 3,
           total_pages: 1,
           current_page: 1,
           page_size: 20
         }}
      end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               ListXcodeSelectiveTestingTargets.call(conn, %{"test_run_id" => "run-1"})

      result = JSON.decode!(text)
      assert length(result["targets"]) == 3

      auth = Enum.find(result["targets"], &(&1["name"] == "AuthTests"))
      assert auth["hit_status"] == "miss"
      assert auth["hash"] == "abc123"

      core = Enum.find(result["targets"], &(&1["name"] == "CoreTests"))
      assert core["hit_status"] == "local"

      ui = Enum.find(result["targets"], &(&1["name"] == "UITests"))
      assert ui["hit_status"] == "remote"
    end
  end
end
