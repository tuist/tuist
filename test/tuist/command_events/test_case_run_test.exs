defmodule Tuist.CommandEvents.TestCaseRunTest do
  alias Tuist.CommandEvents.TestCaseRun
  use Tuist.DataCase
  use Mimic

  describe "create_changeset" do
    test "changeset is valid if all properties are set" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run())

      # Then
      assert got.valid? == true
    end

    test "changeset is not valid if test_case_id is not specified" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run(test_case_id: nil))

      # Then
      assert got.valid? == false
      assert "can't be blank" in errors_on(got).test_case_id
    end

    test "changeset is valid if module_hash is not specified" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run(module_hash: nil))

      # Then
      assert got.valid? == true
    end

    test "changeset is not valid if status is not specified" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run(status: nil))

      # Then
      assert got.valid? == false
      assert "can't be blank" in errors_on(got).status
    end

    test "changeset is not valid if command_event_id is not specified" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run(command_event_id: nil))

      # Then
      assert got.valid? == false
      assert "can't be blank" in errors_on(got).command_event_id
    end

    test "changeset is not valid if status is not success or failure" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run(status: :invalid))

      # Then
      assert got.valid? == false
      assert "is invalid" in errors_on(got).status
    end

    test "changeset is valid if status is failure" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run(status: :failure))

      # Then
      assert got.valid? == true
    end
  end

  defp test_case_run(attrs \\ []) do
    %{
      module_hash: attrs |> Keyword.get(:module_hash, "123"),
      status: attrs |> Keyword.get(:status, :success),
      command_event_id: attrs |> Keyword.get(:command_event_id, 1),
      test_case_id: attrs |> Keyword.get(:test_case_id, 1)
    }
  end
end
