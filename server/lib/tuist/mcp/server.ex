defmodule Tuist.MCP.Server do
  @moduledoc false

  use Hermes.Server,
    name: "tuist",
    version: "1.4.1",
    capabilities: [
      {:tools, list_changed?: false},
      {:prompts, list_changed?: false}
    ],
    protocol_versions: ["2025-03-26"]

  alias Hermes.MCP.Error
  alias Hermes.Server.Frame
  alias Hermes.Server.Handlers
  alias Tuist.MCP.Components.Prompts.FixFlakyTest
  alias Tuist.MCP.Components.Tools.GetTestCase
  alias Tuist.MCP.Components.Tools.GetTestCaseRun
  alias Tuist.MCP.Components.Tools.GetTestRun
  alias Tuist.MCP.Components.Tools.ListProjects
  alias Tuist.MCP.Components.Tools.ListTestCases

  component(ListProjects, name: "list_projects")
  component(ListTestCases, name: "list_test_cases")
  component(GetTestCase, name: "get_test_case")
  component(GetTestRun, name: "get_test_run")
  component(GetTestCaseRun, name: "get_test_case_run")
  component(FixFlakyTest, name: "fix_flaky_test")

  @impl Hermes.Server
  def handle_request(%{"method" => "tools/call", "params" => %{"name" => _name} = params} = request, %Frame{} = frame) do
    request = put_in(request, ["params"], Map.put_new(params, "arguments", %{}))
    Handlers.handle(request, __MODULE__, frame)
  end

  @impl Hermes.Server
  def handle_request(%{"method" => "tools/call"}, %Frame{} = frame) do
    {:error, invalid_params_error("Missing required parameter: name."), frame}
  end

  @impl Hermes.Server
  def handle_request(%{"method" => "prompts/get", "params" => %{"name" => _name} = params} = request, %Frame{} = frame) do
    request = put_in(request, ["params"], Map.put_new(params, "arguments", %{}))
    Handlers.handle(request, __MODULE__, frame)
  end

  @impl Hermes.Server
  def handle_request(%{"method" => "prompts/get"}, %Frame{} = frame) do
    {:error, invalid_params_error("Missing required parameter: name."), frame}
  end

  @impl Hermes.Server
  def handle_request(request, %Frame{} = frame), do: Handlers.handle(request, __MODULE__, frame)

  defp invalid_params_error(message) do
    Error.protocol(:invalid_params, %{message: message})
  end
end
