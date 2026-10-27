defmodule Tuist.Automations.Actions.RemoveLabelAction do
  @moduledoc false
  alias Tuist.Tests

  def execute(%{type: :test_case, id: test_case_id}, %{"label" => "flaky"}) do
    case Tests.update_test_case(test_case_id, %{is_flaky: false}) do
      {:ok, _updated} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(_entity, %{"label" => _label}) do
    :ok
  end
end
