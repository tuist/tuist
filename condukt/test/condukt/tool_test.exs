defmodule Condukt.ToolTest do
  use ExUnit.Case, async: true

  alias Condukt.Tool
  alias Condukt.Tools.Command
  alias Condukt.Tools.Read

  defmodule RaisingTool do
    use Condukt.Tool

    @impl true
    def name, do: "RaisingTool"

    @impl true
    def description, do: "Raises while executing"

    @impl true
    def parameters, do: %{type: "object", properties: %{}}

    @impl true
    def call(_args, _context), do: raise("boom")
  end

  test "builds spec from module" do
    spec = Tool.to_spec(Read)

    assert spec.name == "Read"
    assert is_binary(spec.description)
    assert is_map(spec.parameters)
  end

  test "builds spec from a parameterized command tool" do
    spec = Tool.to_spec({Command, command: "git"})

    assert spec.name == "Git"
    assert spec.description =~ "`git`"
    assert spec.parameters[:properties][:args][:type] == "array"
  end

  test "builds spec from an inline tool" do
    tool =
      Condukt.tool(
        name: "n",
        description: "d",
        parameters: %{type: "object", properties: %{}},
        call: fn _, _ -> {:ok, "ok"} end
      )

    assert Tool.to_spec(tool) == %{
             name: "n",
             description: "d",
             parameters: %{type: "object", properties: %{}}
           }
  end

  test "returns the name of an inline tool" do
    tool =
      Condukt.tool(
        name: "named",
        description: "d",
        parameters: %{type: "object", properties: %{}},
        call: fn _, _ -> {:ok, ""} end
      )

    assert Tool.name(tool) == "named"
  end

  test "returns an error tuple when a tool raises" do
    assert {:error, "boom"} = Tool.execute(RaisingTool, %{}, %{agent: self(), cwd: ".", opts: []})
  end

  test "invokes an inline tool callback" do
    tool =
      Condukt.tool(
        name: "double",
        description: "doubles the value",
        parameters: %{type: "object", properties: %{x: %{type: "integer"}}, required: ["x"]},
        call: fn %{"x" => x}, _ctx -> {:ok, x * 2} end
      )

    assert {:ok, 6} = Tool.execute(tool, %{"x" => 3}, %{agent: self(), sandbox: nil, cwd: "."})
  end

  test "wraps inline tool callback exceptions" do
    tool =
      Condukt.tool(
        name: "boom",
        description: "raises",
        parameters: %{type: "object", properties: %{}},
        call: fn _, _ -> raise "kaboom" end
      )

    assert {:error, "kaboom"} = Tool.execute(tool, %{}, %{agent: self(), sandbox: nil, cwd: "."})
  end
end
