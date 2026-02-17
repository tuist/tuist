defmodule Tuist.MCP.Components.Tools.GetTestCase do
  use Hermes.Server.Component, type: :tool

  alias Tuist.MCP.Components.Helpers
  alias Tuist.MCP.Tools.GetTestCase, as: Legacy

  @moduledoc """
  Get detailed information about a test case including reliability and flakiness metrics.
  """

  schema do
    field :test_case_id, :string, required: true, description: "The UUID of the test case."
  end

  @impl true
  def execute(arguments, frame) do
    arguments
    |> Helpers.normalize_legacy_arguments()
    |> Legacy.call(frame.assigns[:current_subject])
    |> Helpers.to_tool_response(frame)
  end
end
