defmodule TuistCloud.CommandEvents.TestCaseRunTest do
  alias TuistCloud.CommandEvents.TestCaseRun
  use TuistCloud.DataCase
  use Mimic

  describe "create_changeset" do
    test "changeset is valid if all properties are set" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run())

      # Then
      assert got.valid? == true
    end

    test "changeset is not valid if name is not specified" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run(name: nil))

      # Then
      assert got.valid? == false
      assert "can't be blank" in errors_on(got).name
    end

    test "changeset is not valid if module_name is not specified" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run(module_name: nil))

      # Then
      assert got.valid? == false
      assert "can't be blank" in errors_on(got).module_name
    end

    test "changeset is not valid if identifier is not specified" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run(identifier: nil))

      # Then
      assert got.valid? == false
      assert "can't be blank" in errors_on(got).identifier
    end

    test "changeset is not valid if project_identifier is not specified" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run(project_identifier: nil))

      # Then
      assert got.valid? == false
      assert "can't be blank" in errors_on(got).project_identifier
    end

    test "changeset is not valid if module_hash is not specified" do
      # When
      got = TestCaseRun.create_changeset(%TestCaseRun{}, test_case_run(module_hash: nil))

      # Then
      assert got.valid? == false
      assert "can't be blank" in errors_on(got).module_hash
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
      name: attrs |> Keyword.get(:name, "testHello()"),
      module_name: attrs |> Keyword.get(:module_name, "MyApp"),
      identifier: attrs |> Keyword.get(:identifier, "MyAppTests"),
      project_identifier: attrs |> Keyword.get(:project_identifier, "MyApp/MyApp.xcodeproj"),
      module_hash: attrs |> Keyword.get(:module_hash, "123"),
      status: attrs |> Keyword.get(:status, :success),
      command_event_id: attrs |> Keyword.get(:command_event_id, 1)
    }
  end
end
