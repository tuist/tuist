defmodule Tuist.MCP.Components.Tools.ListProjects do
  use Hermes.Server.Component, type: :tool

  alias Tuist.MCP.Components.Helpers
  alias Tuist.MCP.Tools.ListProjects, as: Legacy

  @moduledoc """
  List all projects accessible to the authenticated user.
  """

  schema do
  end

  @impl true
  def execute(arguments, frame) do
    arguments
    |> Helpers.normalize_legacy_arguments()
    |> Legacy.call(frame.assigns[:current_subject])
    |> Helpers.to_tool_response(frame)
  end
end
