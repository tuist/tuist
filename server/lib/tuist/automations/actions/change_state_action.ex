defmodule Tuist.Automations.Actions.ChangeStateAction do
  @moduledoc false
  alias Tuist.Tests

  def execute(%{type: :test_case, id: test_case_id}, %{"state" => target_state}) do
    case Tests.update_test_case(test_case_id, %{state: target_state}) do
      {:ok, _updated} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
