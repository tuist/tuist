defmodule Tuist.MCP.Components.Tools.GetGradleIntegrationGuideTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.MCP.Components.Tools.GetGradleIntegrationGuide

  describe "get_gradle_integration_guide" do
    test "returns a local-server workflow with deterministic authentication and cache verification" do
      result =
        GetGradleIntegrationGuide.call(%Plug.Conn{}, %{
          "account_handle" => "acme",
          "project_handle" => "android",
          "server_url" => "http://localhost:8080",
          "features" => "remote_cache,build_insights"
        })

      assert %{
               "plugin_version" => "0.10.0",
               "guide" => guide
             } = result["structuredContent"]

      assert guide =~ "`acme/android`"
      assert guide =~ "list_accounts"
      assert guide =~ "tuist auth whoami --url http://localhost:8080"
      assert guide =~ "tuist auth login --url http://localhost:8080"
      assert guide =~ "Model Context Protocol token as a build token"
      assert guide =~ "explicitly ask the user to confirm the email address"
      assert guide =~ ~s{project = "ACCOUNT_HANDLE/PROJECT_HANDLE"}
      refute guide =~ "full_handle ="
      assert guide =~ ~s{id("dev.tuist") version "0.10.0"}
      assert guide =~ "allowInsecureProtocol = true"
      assert guide =~ "Keep it for local or self-hosted servers"
      assert guide =~ "push = System.getenv(\"CI\") != null"
      assert guide =~ "do not end the agent turn while a background build is pending"
      assert guide =~ "pass an explicit long `timeout` to the Bash tool"
      assert guide =~ "CI=1 ./gradlew clean TASK"
      assert guide =~ "list_gradle_build_tasks"
    end

    test "defaults to the deployment serving the tool" do
      result = GetGradleIntegrationGuide.call(%Plug.Conn{}, %{"server_url" => nil})

      assert result["structuredContent"]["guide"] =~ "tuist auth whoami --url http://localhost:8080"
      assert result["structuredContent"]["guide"] =~ "allowInsecureProtocol = true"
      assert result["structuredContent"]["guide"] =~ "run `./gradlew clean` separately"
    end

    test "does not allow an insecure protocol for an HTTPS server" do
      result = GetGradleIntegrationGuide.call(%Plug.Conn{}, %{"server_url" => "https://tuist.dev"})

      refute result["structuredContent"]["guide"] =~ "allowInsecureProtocol = true"
    end
  end
end
