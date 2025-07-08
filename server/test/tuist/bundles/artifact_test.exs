defmodule Tuist.Bundles.ArtifactTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Bundles.Artifact

  @valid_attrs %{
    name: "App",
    bundle_id: UUIDv7.generate(),
    size: 1024,
    artifact_type: :file,
    shasum: "sha",
    path: "App/path",
    project_id: 1
  }

  describe "create_changeset/2" do
    test "is valid when contains all necessary attributes" do
      changeset = Artifact.changeset(%Artifact{}, @valid_attrs)
      assert changeset.valid?
    end

    test "ensures bundle_id is present" do
      changeset = Artifact.changeset(%Artifact{}, Map.delete(@valid_attrs, :bundle_id))
      assert "can't be blank" in errors_on(changeset).bundle_id
    end

    test "ensures shasum is present" do
      changeset = Artifact.changeset(%Artifact{}, Map.delete(@valid_attrs, :shasum))
      assert "can't be blank" in errors_on(changeset).shasum
    end

    test "ensures size is present" do
      changeset = Artifact.changeset(%Artifact{}, Map.delete(@valid_attrs, :size))
      assert "can't be blank" in errors_on(changeset).size
    end

    test "ensures path is present" do
      changeset = Artifact.changeset(%Artifact{}, Map.delete(@valid_attrs, :path))
      assert "can't be blank" in errors_on(changeset).path
    end

    test "ensures artifact_type is present" do
      changeset = Artifact.changeset(%Artifact{}, Map.delete(@valid_attrs, :artifact_type))
      assert "can't be blank" in errors_on(changeset).artifact_type
    end

    test "ensures artifact_type is valid" do
      changeset = Artifact.changeset(%Artifact{}, Map.put(@valid_attrs, :artifact_type, :invalid))
      assert "is invalid" in errors_on(changeset).artifact_type
    end
  end
end
