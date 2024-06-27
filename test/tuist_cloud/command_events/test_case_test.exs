defmodule TuistCloud.CommandEvents.TestCaseTest do
  alias TuistCloud.CommandEvents.TestCase
  use TuistCloud.DataCase
  use Mimic

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
      project_id: attrs |> Keyword.get(:project_id, 1),
      name: attrs |> Keyword.get(:name, "testHello()"),
      module_name: attrs |> Keyword.get(:module_name, "MyApp"),
      identifier: attrs |> Keyword.get(:identifier, "MyAppTests"),
      project_identifier: attrs |> Keyword.get(:project_identifier, "MyApp/MyApp.xcodeproj")
    }
  end
end
