defmodule Tuist.Automations.Actions.UnmarkAsFlakyActionTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Automations.Actions.UnmarkAsFlakyAction
  alias Tuist.Tests

  describe "execute/1" do
    test "unmarks the given test case as flaky" do
      test_case_id = Ecto.UUID.generate()

      expect(Tests, :update_test_case, fn ^test_case_id, %{is_flaky: false} ->
        {:ok, %{is_flaky: false}}
      end)

      assert :ok = UnmarkAsFlakyAction.execute(test_case_id)
    end

    test "propagates the error tuple" do
      expect(Tests, :update_test_case, fn _id, _attrs -> {:error, :not_found} end)
      assert {:error, :not_found} = UnmarkAsFlakyAction.execute(Ecto.UUID.generate())
    end
  end
end
