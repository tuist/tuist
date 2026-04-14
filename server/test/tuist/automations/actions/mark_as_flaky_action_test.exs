defmodule Tuist.Automations.Actions.MarkAsFlakyActionTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Automations.Actions.MarkAsFlakyAction
  alias Tuist.Tests

  describe "execute/1" do
    test "marks the given test case as flaky" do
      test_case_id = Ecto.UUID.generate()

      expect(Tests, :update_test_case, fn ^test_case_id, %{is_flaky: true} ->
        {:ok, %{is_flaky: true}}
      end)

      assert :ok = MarkAsFlakyAction.execute(test_case_id)
    end

    test "propagates the error tuple" do
      expect(Tests, :update_test_case, fn _id, _attrs -> {:error, :not_found} end)
      assert {:error, :not_found} = MarkAsFlakyAction.execute(Ecto.UUID.generate())
    end
  end
end
