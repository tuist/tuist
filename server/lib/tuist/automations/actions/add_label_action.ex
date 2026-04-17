defmodule Tuist.Automations.Actions.AddLabelAction do
  @moduledoc false
  alias Tuist.Tests

  def execute(test_case_id, %{"label" => "flaky"}) do
    case Tests.update_test_case(test_case_id, %{is_flaky: true}) do
      {:ok, _updated} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def execute(_test_case_id, %{"label" => _label}) do
    :ok
  end
end
