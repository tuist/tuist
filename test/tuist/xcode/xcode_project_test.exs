defmodule Tuist.Xcode.XcodeProjectTest do
  alias Tuist.Xcode.XcodeProject
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.XcodeFixtures
  use TuistTestSupport.Cases.DataCase

  describe "create_changeset/1" do
    test "is valid when contains all necessary attributes" do
      # Given
      xcode_graph = XcodeFixtures.xcode_graph_fixture()

      # When
      got =
        XcodeProject.create_changeset(%XcodeProject{}, %{
          name: "XcodeProject",
          xcode_graph_id: xcode_graph.id
        })

      # Then
      assert got.valid?
    end

    test "ensures a xcode_graph is present" do
      # When
      got = XcodeProject.create_changeset(%XcodeProject{}, %{})

      # Then
      assert "can't be blank" in errors_on(got).xcode_graph_id
    end

    test "ensures a name is present" do
      # When
      got = XcodeProject.create_changeset(%XcodeProject{}, %{})

      # Then
      assert "can't be blank" in errors_on(got).name
    end

    test "ensures that the name and graph_id are unique" do
      # Given
      xcode_graph = XcodeFixtures.xcode_graph_fixture()

      changeset =
        XcodeProject.create_changeset(%XcodeProject{}, %{
          name: "XcodeProject",
          xcode_graph_id: xcode_graph.id
        })

      # When
      {:ok, _} = Repo.insert(changeset)

      {:error, got} =
        XcodeProject.create_changeset(%XcodeProject{}, %{
          name: "XcodeProject",
          xcode_graph_id: xcode_graph.id
        })
        |> Repo.insert()

      # Then
      assert "has already been taken" in errors_on(got).xcode_graph_id
    end
  end
end
