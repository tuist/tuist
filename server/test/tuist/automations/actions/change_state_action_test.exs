defmodule Tuist.Automations.Actions.ChangeStateActionTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Automations.Actions.ChangeStateAction
  alias Tuist.Tests

  describe "execute/2" do
    test "calls Tests.update_test_case with the requested state" do
      test_case_id = Ecto.UUID.generate()
      entity = %{type: :test_case, id: test_case_id}

      expect(Tests, :update_test_case, fn ^test_case_id, %{state: "muted"} ->
        {:ok, %{state: "muted"}}
      end)

      assert :ok = ChangeStateAction.execute(entity, %{"state" => "muted"})
    end

    test "propagates the error tuple from Tests.update_test_case" do
      entity = %{type: :test_case, id: Ecto.UUID.generate()}
      expect(Tests, :update_test_case, fn _id, _attrs -> {:error, :not_found} end)
      assert {:error, :not_found} = ChangeStateAction.execute(entity, %{"state" => "enabled"})
    end
  end
end
