defmodule Tuist.Runs.TestCaseEventTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Runs.TestCaseEvent

  describe "changeset/2" do
    @valid_attrs %{
      id: "a12673da-1345-4077-bb30-d7576feace09",
      test_case_id: "b23784eb-2456-4188-8c41-e8687afbdf10",
      event_type: "marked_flaky",
      actor_type: "user",
      actor_id: 123,
      inserted_at: ~N[2024-01-01 12:00:00.000000]
    }

    test "creates valid changeset with all attributes" do
      changeset = TestCaseEvent.changeset(%TestCaseEvent{}, @valid_attrs)

      assert changeset.valid?
      assert changeset.changes.id == "a12673da-1345-4077-bb30-d7576feace09"
      assert changeset.changes.test_case_id == "b23784eb-2456-4188-8c41-e8687afbdf10"
      assert changeset.changes.event_type == "marked_flaky"
      assert changeset.changes.actor_type == "user"
      assert changeset.changes.actor_id == 123
    end

    test "requires id" do
      attrs = Map.delete(@valid_attrs, :id)
      changeset = TestCaseEvent.changeset(%TestCaseEvent{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).id
    end

    test "requires test_case_id" do
      attrs = Map.delete(@valid_attrs, :test_case_id)
      changeset = TestCaseEvent.changeset(%TestCaseEvent{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).test_case_id
    end

    test "requires event_type" do
      attrs = Map.delete(@valid_attrs, :event_type)
      changeset = TestCaseEvent.changeset(%TestCaseEvent{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).event_type
    end

    test "requires actor_type" do
      attrs = Map.delete(@valid_attrs, :actor_type)
      changeset = TestCaseEvent.changeset(%TestCaseEvent{}, attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).actor_type
    end

    test "requires actor_id when actor_type is user" do
      attrs = %{@valid_attrs | actor_type: "user", actor_id: nil}
      changeset = TestCaseEvent.changeset(%TestCaseEvent{}, attrs)

      refute changeset.valid?
      assert "is required when actor_type is user" in errors_on(changeset).actor_id
    end

    test "allows nil actor_id when actor_type is system" do
      attrs = %{@valid_attrs | actor_type: "system", actor_id: nil}
      changeset = TestCaseEvent.changeset(%TestCaseEvent{}, attrs)

      assert changeset.valid?
    end

    test "rejects non-nil actor_id when actor_type is system" do
      attrs = %{@valid_attrs | actor_type: "system", actor_id: 123}
      changeset = TestCaseEvent.changeset(%TestCaseEvent{}, attrs)

      refute changeset.valid?
      assert "must be nil when actor_type is system" in errors_on(changeset).actor_id
    end
  end

  describe "first_run_id/1" do
    test "returns a valid UUID" do
      test_case_id = "b23784eb-2456-4188-8c41-e8687afbdf10"

      result = TestCaseEvent.first_run_id(test_case_id)

      assert {:ok, _} = Ecto.UUID.cast(result)
    end

    test "returns the same UUID for the same test_case_id" do
      test_case_id = "b23784eb-2456-4188-8c41-e8687afbdf10"

      result1 = TestCaseEvent.first_run_id(test_case_id)
      result2 = TestCaseEvent.first_run_id(test_case_id)

      assert result1 == result2
    end

    test "returns different UUIDs for different test_case_ids" do
      test_case_id_1 = "b23784eb-2456-4188-8c41-e8687afbdf10"
      test_case_id_2 = "c34895fc-3567-4299-9d52-f97982cce621"

      result1 = TestCaseEvent.first_run_id(test_case_id_1)
      result2 = TestCaseEvent.first_run_id(test_case_id_2)

      refute result1 == result2
    end
  end
end
