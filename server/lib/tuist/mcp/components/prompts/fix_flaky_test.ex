defmodule Tuist.MCP.Components.Prompts.FixFlakyTest do
  use Hermes.Server.Component, type: :prompt

  alias Tuist.MCP.Components.Helpers
  alias Tuist.MCP.Prompts.FixFlakyTest, as: Legacy

  @moduledoc """
  Guides you through fixing a flaky test by analyzing failure patterns, identifying the root cause, and applying a targeted correction.
  """

  schema do
    field :account_handle, :string,
      description: "The account handle (organization or user). Required if project_handle is provided."

    field :project_handle, :string,
      description: "The project handle. Required if account_handle is provided."

    field :test_case_id, :string,
      description: "The UUID of a specific flaky test case to fix."
  end

  @impl true
  def get_messages(arguments, frame) do
    arguments
    |> Helpers.normalize_legacy_arguments()
    |> Legacy.get()
    |> Helpers.to_prompt_response(frame)
  end
end
