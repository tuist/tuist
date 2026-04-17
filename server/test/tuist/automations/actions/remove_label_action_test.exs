defmodule Tuist.Automations.Actions.RemoveLabelActionTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Automations.Actions.RemoveLabelAction
  alias Tuist.Tests

  describe "execute/2 with flaky label" do
    test "unmarks the given test case as flaky" do
      test_case_id = Ecto.UUID.generate()

      expect(Tests, :update_test_case, fn ^test_case_id, %{is_flaky: false} ->
        {:ok, %{is_flaky: false}}
      end)

      assert :ok = RemoveLabelAction.execute(test_case_id, %{"label" => "flaky"})
    end

    test "propagates the error tuple" do
      expect(Tests, :update_test_case, fn _id, _attrs -> {:error, :not_found} end)
      assert {:error, :not_found} = RemoveLabelAction.execute(Ecto.UUID.generate(), %{"label" => "flaky"})
    end
  end

  describe "execute/2 with unknown label" do
    test "no-ops for unsupported labels" do
      reject(&Tests.update_test_case/2)
      assert :ok = RemoveLabelAction.execute(Ecto.UUID.generate(), %{"label" => "slow"})
    end
  end
end
