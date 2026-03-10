defmodule Tuist.MCP.Components.Prompts.PromptsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Anubis.Server.Frame
  alias Tuist.MCP.Server
  alias Tuist.Projects

  describe "fix_flaky_test" do
    test "returns prompt messages" do
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

  describe "compare_builds" do
    test "returns prompt messages with default branch" do
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

    test "returns prompt without handles when using dashboard URLs" do
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
  end

  describe "compare_test_runs" do
    test "returns prompt messages" do
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
  end

  describe "compare_bundles" do
    test "returns prompt messages" do
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
  end

  describe "compare_test_case" do
    test "returns prompt messages" do
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
  end

  describe "compare_generations" do
    test "returns prompt messages with default branch" do
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
  end

  describe "compare_cache_runs" do
    test "returns prompt messages" do
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
end
