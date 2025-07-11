defmodule Tuist.Xcode.Postgres.XcodeGraphTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Repo
  alias Tuist.Xcode.Postgres.XcodeGraph

  describe "create_changeset/1" do
    test "is valid when contains all necessary attributes" do
      # When
      got =
        XcodeGraph.create_changeset(%XcodeGraph{}, %{
          name: "XcodeGraph",
          command_event_id: UUIDv7.generate()
        })

      # Then
      assert got.valid?
    end

    test "ensures a command_event_id is present" do
      # When
      got = XcodeGraph.create_changeset(%XcodeGraph{}, %{})

      # Then
      assert "can't be blank" in errors_on(got).command_event_id
    end

    test "ensures a name is present" do
      # When
      got = XcodeGraph.create_changeset(%XcodeGraph{}, %{})

      # Then
      assert "can't be blank" in errors_on(got).name
    end

    test "ensures that the command_event_id is unique" do
      # Given
      uuid = UUIDv7.generate()

      changeset =
        XcodeGraph.create_changeset(%XcodeGraph{}, %{
          name: "XcodeGraph",
          command_event_id: uuid
        })

      # When
      {:ok, _} = Repo.insert(changeset)

      {:error, got} =
        %XcodeGraph{}
        |> XcodeGraph.create_changeset(%{
          name: "XcodeGraph",
          command_event_id: uuid
        })
        |> Repo.insert()

      # Then
      assert "has already been taken" in errors_on(got).command_event_id
    end
  end
end
