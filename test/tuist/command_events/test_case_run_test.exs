defmodule Tuist.CommandEvents.TestCaseRunTest do
  alias Tuist.CommandEvents.TestCaseRun
  use TuistTestSupport.Cases.DataCase
  use Mimic

  describe "create_changeset" do
    test "changeset is valid if all properties are set" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run())

      # Then
      assert got.valid?
    end

    test "changeset is not valid if test_case_id is not specified" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run(test_case_id: nil))

      # Then
      refute got.valid?
      assert "can't be blank" in errors_on(got).test_case_id
    end

    test "changeset is not valid if xcode_target_id is not specified" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run(xcode_target_id: nil))

      # Then
      refute got.valid?
    end

    test "changeset is not valid if status is not specified" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run(status: nil))

      # Then
      refute got.valid?
      assert "can't be blank" in errors_on(got).status
    end

    test "changeset is not valid if command_event_id is not specified" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run(command_event_id: nil))

      # Then
      refute got.valid?
      assert "can't be blank" in errors_on(got).command_event_id
    end

    test "changeset is not valid if status is not success or failure" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run(status: :invalid))

      # Then
      refute got.valid?
      assert "is invalid" in errors_on(got).status
    end

    test "changeset is valid if status is failure" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run(status: :failure))

      # Then
      assert got.valid?
    end
  end

  defp test_case_run(attrs \\ []) do
    %{
      status: attrs |> Keyword.get(:status, :success),
      command_event_id: attrs |> Keyword.get(:command_event_id, 1),
      test_case_id: attrs |> Keyword.get(:test_case_id, 1),
      xcode_target_id: attrs |> Keyword.get(:xcode_target_id, UUIDv7.generate())
    }
  end
end
