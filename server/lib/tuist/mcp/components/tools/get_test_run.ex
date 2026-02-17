defmodule Tuist.MCP.Components.Tools.GetTestRun do
  use Hermes.Server.Component, type: :tool

  alias Tuist.MCP.Components.Helpers
  alias Tuist.MCP.Tools.GetTestRun, as: Legacy

  @moduledoc """
  Get details and aggregate metrics for a specific test run, including crash summaries.
  """

  schema do
    field :test_run_id, :string, required: true, description: "The UUID of the test run."
  end

  @impl true
  def execute(arguments, frame) do
    arguments
    |> Helpers.normalize_legacy_arguments()
    |> Legacy.call(frame.assigns[:current_subject])
    |> Helpers.to_tool_response(frame)
  end
end
