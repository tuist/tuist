defmodule Tuist.MCP.Components.Tools.GetBazelIntegrationGuideTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.MCP.BazelIntegrationGuide
  alias Tuist.MCP.Components.Tools.GetBazelIntegrationGuide

  describe "get_bazel_integration_guide" do
    test "returns a local-server workflow with authentication and cache verification" do
      result =
        GetBazelIntegrationGuide.call(%Plug.Conn{}, %{
          "account_handle" => "acme",
          "project_handle" => "bazel",
          "server_url" => "http://localhost:8080"
        })

      assert %{"guide" => guide} = result["structuredContent"]
      assert guide =~ "`acme/bazel`"
      assert guide =~ "list_accounts"
      assert guide =~ "create_project"
      assert guide =~ "build_system=bazel"
      assert guide =~ ~s{tuist auth whoami --url "http://localhost:8080"}
      assert guide =~ ~s{tuist auth login --url "http://localhost:8080"}
      assert guide =~ ~s{project = "ACCOUNT_HANDLE/PROJECT_HANDLE"}
      assert guide =~ ~s{url = "http://localhost:8080"}
      assert guide =~ "Tuist/Config.swift"
      assert guide =~ "try-import %workspace%/.bazelrc.tuist"
      assert guide =~ "Confirm that the exact `try-import` line is present and active"
      assert guide =~ "existing `--remote_cache` or `--bes_backend` options conflict"
      assert guide =~ ".bazelrc.tuist` contains a machine-local credential-helper path"
      assert guide =~ "must never be committed"
      assert guide =~ "--no-build-insights"
      assert guide =~ "bazel build --bes_upload_mode=wait_for_upload_complete TARGET"
      assert guide =~ "no more than 60 seconds"
      assert guide =~ "For a failed `bazel build`"
      assert guide =~ "For a failed `bazel test`"
      assert guide =~ "list_bazel_invocation_logs"
      assert guide =~ "get_bazel_invocation_log"
      assert guide =~ "When the user chose `--no-build-insights`"
      assert guide =~ "No invocation is expected in Tuist"
    end

    test "defaults to the deployment serving the tool" do
      result = GetBazelIntegrationGuide.call(%Plug.Conn{}, %{})

      assert result["structuredContent"]["guide"] =~ ~s{tuist auth whoami --url "http://localhost:8080"}
    end

    test "treats a blank server URL as omitted" do
      result = GetBazelIntegrationGuide.call(%Plug.Conn{}, %{"server_url" => "  "})

      assert result["structuredContent"]["guide"] =~ ~s{tuist auth whoami --url "http://localhost:8080"}
    end

    test "rejects an invalid server URL" do
      result =
        GetBazelIntegrationGuide.call(%Plug.Conn{}, %{
          "server_url" => "https://attacker.example;touch"
        })

      assert %{"isError" => true, "content" => [%{"text" => message}]} = result
      assert message =~ "server_url must be an HTTP or HTTPS origin"
      refute message =~ "attacker.example"
    end

    test "trims a valid server origin and quotes IPv6 origins in shell commands" do
      assert {:ok, guide} =
               BazelIntegrationGuide.build(%{"server_url" => "  http://[::1]:8080/  "})

      assert guide =~ ~s{tuist auth whoami --url "http://[::1]:8080"}
      assert guide =~ ~s{url = "http://[::1]:8080"}
    end
  end
end
