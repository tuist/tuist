defmodule Tuist.Automations.Actions.RemoveLabelActionTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Automations.Actions.RemoveLabelAction
  alias Tuist.Tests

  describe "execute/2 with flaky label" do
    test "unmarks the given test case as flaky" do
      test_case_id = Ecto.UUID.generate()
      entity = %{type: :test_case, id: test_case_id}

      expect(Tests, :update_test_case, fn ^test_case_id, %{is_flaky: false} ->
        {:ok, %{is_flaky: false}}
      end)

      assert :ok = RemoveLabelAction.execute(entity, %{"label" => "flaky"})
    end

    test "propagates the error tuple" do
      entity = %{type: :test_case, id: Ecto.UUID.generate()}
      expect(Tests, :update_test_case, fn _id, _attrs -> {:error, :not_found} end)
      assert {:error, :not_found} = RemoveLabelAction.execute(entity, %{"label" => "flaky"})
    end
  end

  describe "execute/2 with unknown label" do
    test "no-ops for unsupported labels" do
      entity = %{type: :test_case, id: Ecto.UUID.generate()}
      reject(&Tests.update_test_case/2)
      assert :ok = RemoveLabelAction.execute(entity, %{"label" => "slow"})
    end
  end
end
