defmodule Tuist.Automations.Actions.ChangeStateAction do
  @moduledoc """
  Legacy standalone `change_state` entry point with no production callers:
  the live path is `Tuist.Automations.ActionExecutor.execute_actions/3`,
  which coalesces attribute actions and routes state through the holds
  ledger. Kept as a thin shim over the executor so no second state-write
  implementation exists; without an owning automation it cannot place a
  claim, so it falls back to the executor's direct write.
  """
  alias Tuist.Automations.ActionExecutor

  def execute(%{type: :test_case} = entity, %{"state" => target_state}) do
    ActionExecutor.execute_actions(
      [%{"type" => "change_state", "state" => target_state}],
      %{},
      entity
    )
  end
end
