defmodule Tuist.MCP.ToolTest do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Tuist.MCP.Components.Tools.ListBundles
  alias Tuist.MCP.Tool

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

  describe "resolved_output_schema/0" do
    test "every tool pre-resolves its output schema at compile time" do
      for {name, module} <- Tuist.MCP.Server.server().tools do
        assert is_struct(module.resolved_output_schema(), ExJsonSchema.Schema.Root),
               "tool #{name} does not pre-resolve its output schema"
      end
    end
  end
end
