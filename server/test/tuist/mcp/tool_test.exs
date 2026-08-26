defmodule Tuist.MCP.ToolTest do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Tuist.MCP.Components.Tools.ListBundles
  alias Tuist.MCP.Tool
  alias Tuist.Projects
  alias Tuist.Projects.Project

  defp valid_payload do
    %{
      bundles: [
        %{
          id: "bundle-id",
          name: "App",
          app_bundle_id: "dev.tuist.app",
          version: "1.0.0",
          type: "app",
          supported_platforms: ["ios"],
          install_size: 1000,
          download_size: 900,
          git_branch: "main",
          git_commit_sha: "abc123",
          inserted_at: "2026-07-10T00:00:00Z"
        }
      ],
      pagination_metadata:
        Tool.pagination_metadata(%{
          has_next_page?: false,
          has_previous_page?: false,
          total_count: 1,
          total_pages: 1,
          current_page: 1,
          page_size: 20
        })
    }
  end

  describe "json_response/2" do
    test "records the tool name" do
      expect(OpenTelemetry.Tracer, :set_attribute, fn "mcp.tool.name", "list_bundles" ->
        :ok
      end)

      Tool.json_response(valid_payload(), ListBundles)

      assert Logger.metadata()[:mcp_tool_name] == "list_bundles"
    end

    test "returns both the encoded text content and the structured content" do
      response = Tool.json_response(valid_payload(), ListBundles)

      assert [%{"type" => "text", "text" => text}] = response["content"]
      assert JSON.decode!(text) == response["structuredContent"]
      assert response["structuredContent"]["bundles"] |> hd() |> Map.get("id") == "bundle-id"
    end

    test "raises in dev and test so schema drift fails loudly for developers" do
      payload = put_in(valid_payload(), [:bundles, Access.at(0), :install_size], nil)

      assert_raise RuntimeError, ~r/list_bundles returned invalid structured content/, fn ->
        Tool.json_response(payload, ListBundles)
      end
    end

    test "logs an error and still serves the payload outside dev and test" do
      stub(Tuist.Environment, :dev?, fn -> false end)
      stub(Tuist.Environment, :test?, fn -> false end)

      payload = put_in(valid_payload(), [:bundles, Access.at(0), :install_size], nil)

      log =
        capture_log(fn ->
          response = Tool.json_response(payload, ListBundles)

          assert response["structuredContent"]["bundles"] |> hd() |> Map.get("install_size") == nil
        end)

      assert log =~ "list_bundles returned invalid structured content"
      assert log =~ "[error]"
    end

    test "raises a descriptive error when a tool returns a payload that is not a map" do
      assert_raise ArgumentError, ~r/list_bundles must return a map as structured content/, fn ->
        Tool.json_response([1, 2, 3], ListBundles)
      end
    end
  end

  describe "project observability context" do
    test "records a resource project's context after authorization" do
      parent = self()
      project = %Project{id: 1, name: "atlas", account: %{name: "tuist"}}

      expect(Projects, :get_project_by_id, fn 1 -> project end)

      expect(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project ->
        :ok
      end)

      expect(OpenTelemetry.Tracer, :set_attribute, 2, fn key, value ->
        send(parent, {:trace_attribute, key, value})
        :ok
      end)

      assert {:ok, %{project_id: 1}, ^project} =
               Tool.load_and_authorize(
                 {:ok, %{project_id: 1}},
                 %{current_subject: :subject},
                 :read,
                 :test,
                 "Test case not found."
               )

      assert_receive {:trace_attribute, "mcp.account.handle", "tuist"}
      assert_receive {:trace_attribute, "mcp.project.handle", "atlas"}
    end

    test "records an explicitly selected project's context after authorization" do
      parent = self()
      project = %Project{id: 1, name: "atlas", account: %{name: "tuist"}}

      expect(Projects, :get_project_by_account_and_project_handles, fn "tuist", "atlas" -> project end)

      expect(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project ->
        :ok
      end)

      expect(OpenTelemetry.Tracer, :set_attribute, 2, fn key, value ->
        send(parent, {:trace_attribute, key, value})
        :ok
      end)

      assert {:ok, ^project} =
               Tool.resolve_and_authorize_project(
                 %{"account_handle" => "tuist", "project_handle" => "atlas"},
                 %{current_subject: :subject},
                 :read,
                 :build
               )

      assert_receive {:trace_attribute, "mcp.account.handle", "tuist"}
      assert_receive {:trace_attribute, "mcp.project.handle", "atlas"}
    end

    test "does not record a resource project's context when authorization is denied" do
      project = %Project{id: 1, name: "atlas", account: %{name: "tuist"}}

      expect(Projects, :get_project_by_id, fn 1 -> project end)
      expect(Tuist.Authorization, :authorize, fn :test_read, :subject, ^project -> :error end)
      reject(&OpenTelemetry.Tracer.set_attribute/2)

      assert {:error, message} =
               Tool.load_and_authorize(
                 {:ok, %{project_id: 1}},
                 %{current_subject: :subject},
                 :read,
                 :test,
                 "Test case not found."
               )

      assert String.starts_with?(message, "You do not have access to this resource.")

      refute Keyword.has_key?(Logger.metadata(), :mcp_account_handle)
      refute Keyword.has_key?(Logger.metadata(), :mcp_project_handle)
    end

    test "does not record an explicitly selected project's context when authorization is denied" do
      project = %Project{id: 1, name: "atlas", account: %{name: "tuist"}}

      expect(Projects, :get_project_by_account_and_project_handles, fn "tuist", "atlas" -> project end)
      expect(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :error end)
      reject(&OpenTelemetry.Tracer.set_attribute/2)

      assert {:error, message} =
               Tool.resolve_and_authorize_project(
                 %{"account_handle" => "tuist", "project_handle" => "atlas"},
                 %{current_subject: :subject},
                 :read,
                 :build
               )

      assert String.starts_with?(message, "You do not have access to project: tuist/atlas")

      refute Keyword.has_key?(Logger.metadata(), :mcp_account_handle)
      refute Keyword.has_key?(Logger.metadata(), :mcp_project_handle)
    end

    test "does not record project context when project arguments are missing" do
      reject(&OpenTelemetry.Tracer.set_attribute/2)

      assert {:error, "Provide account_handle and project_handle."} =
               Tool.resolve_and_authorize_project(%{}, %{current_subject: :subject}, :read, :build)

      refute Keyword.has_key?(Logger.metadata(), :mcp_account_handle)
      refute Keyword.has_key?(Logger.metadata(), :mcp_project_handle)
    end

    test "does not record a tool name when a project action returns an error" do
      project = %Project{id: 1, name: "atlas", account: %{name: "tuist"}}

      expect(Projects, :get_project_by_account_and_project_handles, fn "tuist", "atlas" -> project end)
      expect(Tuist.Authorization, :authorize, fn :build_read, :subject, ^project -> :ok end)

      expect(OpenTelemetry.Tracer, :set_attribute, 2, fn _key, _value ->
        :ok
      end)

      _response =
        Tool.call_with_project(
          %Plug.Conn{assigns: %{current_subject: :subject}},
          %{"account_handle" => "tuist", "project_handle" => "atlas"},
          :read,
          :build,
          fn _conn, _args, _project -> {:error, "Build not found."} end,
          ListBundles
        )

      refute Keyword.has_key?(Logger.metadata(), :mcp_tool_name)
    end
  end

  describe "descriptor/1" do
    test "attaches the output schema without validating it at request time" do
      descriptor = Tool.descriptor(ListBundles)

      assert descriptor["outputSchema"] == ListBundles.output_schema()
      assert descriptor["name"] == "list_bundles"
    end
  end

  describe "validate_output_schema!/2" do
    test "rejects a schema that does not describe an object" do
      assert_raise ArgumentError, ~r/must provide an object output schema/, fn ->
        Tool.validate_output_schema!("bad_tool", %{"type" => "array"})
      end
    end

    test "returns the schema untouched when it describes an object" do
      schema = %{"type" => "object", "properties" => %{}}

      assert Tool.validate_output_schema!("good_tool", schema) == schema
    end
  end

  describe "pagination_metadata_schema/0" do
    test "accepts exactly what pagination_metadata/1 emits" do
      payload =
        %{
          has_next_page?: true,
          has_previous_page?: false,
          total_count: 42,
          total_pages: 3,
          current_page: 1,
          page_size: 20
        }
        |> Tool.pagination_metadata()
        |> JSON.encode!()
        |> JSON.decode!()

      assert :ok = ExJsonSchema.Validator.validate(Tool.pagination_metadata_schema(), payload)
    end
  end

  describe "resource_id/1" do
    @uuid "38338b32-3437-42e4-bc01-f048d6d3368f"

    test "extracts the identifier from a dashboard URL" do
      assert Tool.resource_id("https://tuist.dev/acme/app/builds/build-runs/#{@uuid}") == @uuid
    end

    test "ignores a trailing slash" do
      assert Tool.resource_id("https://tuist.dev/acme/app/builds/build-runs/#{@uuid}/") == @uuid
    end

    test "ignores a query string and a fragment" do
      assert Tool.resource_id("https://tuist.dev/acme/app/tests/test-runs/#{@uuid}?tab=modules") == @uuid
      assert Tool.resource_id("https://tuist.dev/acme/app/bundles/#{@uuid}#artifacts") == @uuid
    end

    test "is path-shape agnostic, so it covers every resource the dashboard links to" do
      for path <- [
            "acme/app/builds/build-runs",
            "acme/app/tests/test-runs",
            "acme/app/tests/test-cases",
            "acme/app/bundles",
            "acme/app/runs",
            "acme/app/gradle/builds"
          ] do
        assert Tool.resource_id("https://tuist.dev/#{path}/#{@uuid}") == @uuid
      end
    end

    test "accepts a URL from any host, including self-hosted instances" do
      assert Tool.resource_id("https://tuist.acme.io/acme/app/builds/build-runs/#{@uuid}") == @uuid
      assert Tool.resource_id("http://localhost:8080/acme/app/builds/build-runs/#{@uuid}") == @uuid
    end

    test "passes a bare identifier through unchanged" do
      assert Tool.resource_id(@uuid) == @uuid
    end

    test "passes anything that is not a URL through unchanged, so the lookup still rejects it" do
      assert Tool.resource_id("not-a-uuid") == "not-a-uuid"
      assert Tool.resource_id("") == ""
      assert Tool.resource_id("https://tuist.dev") == "https://tuist.dev"
      assert Tool.resource_id("https://tuist.dev/") == "https://tuist.dev/"
    end

    test "passes non-binary values through unchanged" do
      assert Tool.resource_id(nil) == nil
      assert Tool.resource_id(42) == 42
    end
  end

  describe "resolved_output_schema/0" do
    test "every tool pre-resolves its output schema at compile time" do
      for {name, module} <- Tuist.MCP.Server.server().tools do
        assert is_struct(module.resolved_output_schema(), ExJsonSchema.Schema.Root),
               "tool #{name} does not pre-resolve its output schema"
      end
    end
  end
end
