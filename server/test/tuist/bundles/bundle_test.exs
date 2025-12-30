defmodule Tuist.Bundles.BundleTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Bundles.Bundle

  describe "create_changeset/2" do
    @valid_attrs %{
      id: UUIDv7.generate(),
      name: "App",
      app_bundle_id: "dev.tuist.app",
      install_size: 1024,
      download_size: 1024,
      supported_platforms: [
        :ios,
        :ios_simulator
      ],
      version: "1.0.0",
      type: :app,
      git_branch: "main",
      project_id: 1
    }

    test "is valid when contains all necessary attributes" do
      changeset = Bundle.changeset(%Bundle{}, @valid_attrs)
      assert changeset.valid?
    end

    test "ensures bundle_id is present" do
      changeset = Bundle.changeset(%Bundle{}, Map.delete(@valid_attrs, :app_bundle_id))
      assert "can't be blank" in errors_on(changeset).app_bundle_id
    end

    test "ensures name is present" do
      changeset = Bundle.changeset(%Bundle{}, Map.delete(@valid_attrs, :name))
      assert "can't be blank" in errors_on(changeset).name
    end

    test "ensures install_size is present" do
      changeset = Bundle.changeset(%Bundle{}, Map.delete(@valid_attrs, :install_size))
      assert "can't be blank" in errors_on(changeset).install_size
    end

    test "ensures supported_platforms is present" do
      changeset = Bundle.changeset(%Bundle{}, Map.delete(@valid_attrs, :supported_platforms))
      assert "can't be blank" in errors_on(changeset).supported_platforms
    end

    test "ensures version is present" do
      changeset = Bundle.changeset(%Bundle{}, Map.delete(@valid_attrs, :version))
      assert "can't be blank" in errors_on(changeset).version
    end

    test "ensures project_id is present" do
      changeset = Bundle.changeset(%Bundle{}, Map.delete(@valid_attrs, :project_id))
      assert "can't be blank" in errors_on(changeset).project_id
    end

    test "ensures supported_platforms are valid" do
      changeset = Bundle.changeset(%Bundle{}, Map.put(@valid_attrs, :supported_platforms, [:ios, :invalid]))
      assert "is invalid" in errors_on(changeset).supported_platforms
    end

    test "ensures type is valid" do
      changeset = Bundle.changeset(%Bundle{}, Map.put(@valid_attrs, :type, :invalid_type))
      assert "is invalid" in errors_on(changeset).type
    end
  end
end
