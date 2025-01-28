defmodule Tuist.Xcode.XcodeTargetTest do
  alias Tuist.Xcode.XcodeTarget
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.XcodeFixtures
  use TuistTestSupport.Cases.DataCase

  describe "create_changeset/1" do
    test "is valid when contains all necessary attributes" do
      # Given
      xcode_project = XcodeFixtures.xcode_project_fixture()

      # When
      got =
        XcodeTarget.create_changeset(%XcodeTarget{}, %{
          name: "XcodeTarget",
          xcode_project_id: xcode_project.id
        })

      # Then
      assert got.valid?
    end

    test "is valid when contains extra binary cache attributes" do
      # Given
      xcode_project = XcodeFixtures.xcode_project_fixture()

      # When
      got =
        XcodeTarget.create_changeset(%XcodeTarget{}, %{
          name: "XcodeTarget",
          xcode_project_id: xcode_project.id,
          binary_cache_hit: :miss,
          binary_cache_hash: "hash-a"
        })

      # Then
      assert got.valid?
    end

    test "when binary_cache_hit is invalid" do
      # Given
      xcode_project = XcodeFixtures.xcode_project_fixture()

      # When
      got =
        XcodeTarget.create_changeset(%XcodeTarget{}, %{
          name: "XcodeTarget",
          xcode_project_id: xcode_project.id,
          binary_cache_hit: :invalid,
          binary_cache_hash: "hash-a"
        })

      # Then
      assert "is invalid" in errors_on(got).binary_cache_hit
    end

    test "is valid when contains extra selective testing attributes" do
      # Given
      xcode_project = XcodeFixtures.xcode_project_fixture()

      # When
      got =
        XcodeTarget.create_changeset(%XcodeTarget{}, %{
          name: "XcodeTarget",
          xcode_project_id: xcode_project.id,
          selective_testing_hit: :remote,
          selective_testing_hash: "hash-a"
        })

      # Then
      assert got.valid?
    end

    test "when selective_testing_hit is invalid" do
      # Given
      xcode_project = XcodeFixtures.xcode_project_fixture()

      # When
      got =
        XcodeTarget.create_changeset(%XcodeTarget{}, %{
          name: "XcodeTarget",
          xcode_project_id: xcode_project.id,
          selective_testing_hit: :invalid,
          selective_testing_hash: "hash-a"
        })

      # Then
      assert "is invalid" in errors_on(got).selective_testing_hit
    end

    test "ensures a xcode_project is present" do
      # When
      got = XcodeTarget.create_changeset(%XcodeTarget{}, %{})

      # Then
      assert "can't be blank" in errors_on(got).xcode_project_id
    end

    test "ensures a name is present" do
      # When
      got = XcodeTarget.create_changeset(%XcodeTarget{}, %{})

      # Then
      assert "can't be blank" in errors_on(got).name
    end

    test "ensures that the name and xcode_project_id are unique" do
      # Given
      xcode_project = XcodeFixtures.xcode_project_fixture()

      changeset =
        XcodeTarget.create_changeset(%XcodeTarget{}, %{
          name: "XcodeTarget",
          xcode_project_id: xcode_project.id
        })

      # When
      {:ok, _} = Repo.insert(changeset)

      {:error, got} =
        XcodeTarget.create_changeset(%XcodeTarget{}, %{
          name: "XcodeTarget",
          xcode_project_id: xcode_project.id
        })
        |> Repo.insert()

      # Then
      assert "has already been taken" in errors_on(got).xcode_project_id
    end
  end
end
