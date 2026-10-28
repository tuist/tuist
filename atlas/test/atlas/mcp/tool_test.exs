defmodule Atlas.MCP.ToolTest.SampleTool do
  @moduledoc false

  use Atlas.MCP.Tool,
    name: "sample_tool",
    schema: %{"type" => "object", "properties" => %{}},
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "count" => %{"type" => "integer"}
      },
      "required" => ["id", "count"],
      "additionalProperties" => false
    }

  @impl EMCP.Tool
  def description, do: "Sample tool used to exercise structured content validation."

  def execute(_conn, _args), do: {:ok, %{id: "sample", count: 1}}
end

defmodule Atlas.MCP.ToolTest do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Atlas.MCP.Server
  alias Atlas.MCP.Tool
  alias Atlas.MCP.ToolTest.SampleTool
  alias ExJsonSchema.Schema.Root

  setup :verify_on_exit!

  describe "json_response/2" do
    test "returns both the encoded text content and the structured content" do
      response = Tool.json_response(%{id: "sample", count: 1}, SampleTool)

      assert [%{"type" => "text", "text" => text}] = response["content"]
      assert JSON.decode!(text) == response["structuredContent"]
      assert response["structuredContent"] == %{"id" => "sample", "count" => 1}
    end

    test "raises in dev and test so schema drift fails loudly for developers" do
      assert_raise RuntimeError, ~r/sample_tool returned invalid structured content/, fn ->
        Tool.json_response(%{id: "sample", count: nil}, SampleTool)
      end
    end

    test "logs an error and still serves the payload outside dev and test" do
      stub(Atlas.Environment, :dev?, fn -> false end)
      stub(Atlas.Environment, :test?, fn -> false end)

      log =
        capture_log(fn ->
          response = Tool.json_response(%{id: "sample", count: nil}, SampleTool)

          assert response["structuredContent"] == %{"id" => "sample", "count" => nil}
        end)

      assert log =~ "sample_tool returned invalid structured content"
      assert log =~ "[error]"
    end

    test "raises a descriptive error when a tool returns a payload that is not a map" do
      assert_raise ArgumentError, ~r/sample_tool must return a map as structured content/, fn ->
        Tool.json_response([1, 2, 3], SampleTool)
      end
    end
  end

  describe "call/2" do
    test "wraps a successful execute/2 in content and structured content" do
      response = SampleTool.call(nil, %{})

      assert response["structuredContent"] == %{"id" => "sample", "count" => 1}
      assert [%{"type" => "text"}] = response["content"]
    end
  end

  describe "descriptor/1" do
    test "attaches the output schema without validating it at request time" do
      descriptor = Tool.descriptor(SampleTool)

      assert descriptor["outputSchema"] == SampleTool.output_schema()
      assert descriptor["name"] == "sample_tool"
      assert descriptor["inputSchema"] == SampleTool.input_schema()
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

  describe "nullable/1" do
    test "widens an object fragment so it also accepts null" do
      assert Tool.nullable(%{"type" => "object", "properties" => %{}}) == %{
               "type" => ["object", "null"],
               "properties" => %{}
             }
    end
  end

  describe "resolved_output_schema/0" do
    test "every registered tool resolves its output schema at compile time" do
      for {name, module} <- Server.server().tools do
        assert is_struct(module.resolved_output_schema(), Root),
               "tool #{name} does not pre-resolve its output schema"
      end
    end
  end
end
