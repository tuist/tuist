defmodule Tuist.Automations.Actions.MarkAsFlakyAction do
  @moduledoc false
  alias Tuist.Tests

  def execute(test_case_id) do
    case Tests.update_test_case(test_case_id, %{is_flaky: true}) do
      {:ok, _updated} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
