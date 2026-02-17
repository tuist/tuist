defmodule Tuist.MCP.Components.Tools.ListTestCases do
  use Hermes.Server.Component, type: :tool

  alias Tuist.MCP.Components.Helpers
  alias Tuist.MCP.Tools.ListTestCases, as: Legacy

  @moduledoc """
  List test cases for a project.
  """

  schema do
    field :account_handle, :string,
      required: true,
      description: "The account handle (organization or user)."

    field :project_handle, :string,
      required: true,
      description: "The project handle."

    field :flaky, :boolean, description: "When true, returns only flaky test cases."
    field :quarantined, :boolean, description: "Filter by quarantined status."
    field :module_name, :string, description: "Filter by module name."
    field :name, :string, description: "Filter by test case name."
    field :suite_name, :string, description: "Filter by suite name."
    field :page, :integer, description: "Page number (default: 1)."
    field :page_size, :integer, description: "Results per page (default: 20, max: 100)."
  end

  @impl true
  def execute(arguments, frame) do
    arguments
    |> Helpers.normalize_legacy_arguments()
    |> Legacy.call(frame.assigns[:current_subject])
    |> Helpers.to_tool_response(frame)
  end
end
