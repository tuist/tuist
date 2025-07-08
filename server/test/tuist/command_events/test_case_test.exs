defmodule Tuist.CommandEvents.TestCaseTest do
  use TuistTestSupport.Cases.DataCase
  use Mimic

  alias Tuist.CommandEvents.TestCase

  describe "create_changeset" do
    test "changeset is valid if all properties are set" do
      # When
      got = TestCase.create_changeset(%TestCase{}, test_case())

      # Then
      assert got.valid? == true
    end

    test "changeset is not valid if project_id is not specified" do
      # When
      got = TestCase.create_changeset(%TestCase{}, test_case(project_id: nil))

      # Then
      assert got.valid? == false
      assert "can't be blank" in errors_on(got).project_id
    end

    test "changeset is not valid if name is not specified" do
      # When
      got = TestCase.create_changeset(%TestCase{}, test_case(name: nil))

      # Then
      assert got.valid? == false
      assert "can't be blank" in errors_on(got).name
    end

    test "changeset is not valid if module_name is not specified" do
      # When
      got = TestCase.create_changeset(%TestCase{}, test_case(module_name: nil))

      # Then
      assert got.valid? == false
      assert "can't be blank" in errors_on(got).module_name
    end

    test "changeset is not valid if identifier is not specified" do
      # When
      got = TestCase.create_changeset(%TestCase{}, test_case(identifier: nil))

      # Then
      assert got.valid? == false
      assert "can't be blank" in errors_on(got).identifier
    end

    test "changeset is not valid if project_identifier is not specified" do
      # When
      got = TestCase.create_changeset(%TestCase{}, test_case(project_identifier: nil))

      # Then
      assert got.valid? == false
      assert "can't be blank" in errors_on(got).project_identifier
    end
  end

  defp test_case(attrs \\ []) do
    %{
      project_id: Keyword.get(attrs, :project_id, 1),
      name: Keyword.get(attrs, :name, "testHello()"),
      module_name: Keyword.get(attrs, :module_name, "MyApp"),
      identifier: Keyword.get(attrs, :identifier, "MyAppTests"),
      project_identifier: Keyword.get(attrs, :project_identifier, "MyApp/MyApp.xcodeproj")
    }
  end
end
