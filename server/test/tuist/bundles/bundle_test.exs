defmodule Tuist.Bundles.BundleTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Bundles.Bundle

  @valid_attrs %{
    id: UUIDv7.generate(),
    name: "App",
    app_bundle_id: "dev.tuist.app",
    install_size: 1024,
    download_size: 1024,
    supported_platforms: [:ios, :ios_simulator],
    version: "1.0.0",
    type: :app,
    git_branch: "main",
    project_id: 1
  }

  describe "create_changeset/2" do
    test "is valid when all required fields are present" do
      changeset = Bundle.create_changeset(%Bundle{}, @valid_attrs)
      assert changeset.valid?
    end

    test "accepts type and supported_platforms as strings (post-OpenAPI cast)" do
      attrs =
        @valid_attrs
        |> Map.put(:type, "app")
        |> Map.put(:supported_platforms, ["ios", "ios_simulator"])

      changeset = Bundle.create_changeset(%Bundle{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :type) == "app"
      assert get_change(changeset, :supported_platforms) == ["ios", "ios_simulator"]
    end

    test "accepts inserted_at as DateTime and normalizes to NaiveDateTime" do
      attrs = Map.put(@valid_attrs, :inserted_at, ~U[2024-01-01 02:00:00.000000Z])

      changeset = Bundle.create_changeset(%Bundle{}, attrs)

      assert changeset.valid?
      assert get_change(changeset, :inserted_at) == ~N[2024-01-01 02:00:00.000000]
    end

    for field <- [
          :id,
          :app_bundle_id,
          :name,
          :install_size,
          :supported_platforms,
          :version,
          :type,
          :project_id
        ] do
      @field field

      test "ensures #{@field} is present" do
        changeset = Bundle.create_changeset(%Bundle{}, Map.delete(@valid_attrs, @field))
        assert "can't be blank" in errors_on(changeset)[@field]
      end
    end

    test "rejects an invalid type" do
      changeset = Bundle.create_changeset(%Bundle{}, Map.put(@valid_attrs, :type, :not_a_real_type))
      assert "is invalid" in errors_on(changeset).type
    end

    test "rejects a supported_platforms value that is not in the enum" do
      changeset =
        Bundle.create_changeset(%Bundle{}, Map.put(@valid_attrs, :supported_platforms, [:ios, :made_up_os]))

      assert "has an invalid entry" in errors_on(changeset).supported_platforms
    end
  end
end
