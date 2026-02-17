defmodule Tuist.MCP.Components.Tools.GetTestCaseRun do
  use Hermes.Server.Component, type: :tool

  alias Tuist.MCP.Components.Helpers
  alias Tuist.MCP.Tools.GetTestCaseRun, as: Legacy

  @moduledoc """
  Get detailed information about a specific test case run including failures and repetitions.
  """

  schema do
    field :test_case_run_id, :string,
      required: true,
      description: "The UUID of the test case run."
  end

  @impl true
  def execute(arguments, frame) do
    arguments
    |> Helpers.normalize_legacy_arguments()
    |> Legacy.call(frame.assigns[:current_subject])
    |> Helpers.to_tool_response(frame)
  end
end
