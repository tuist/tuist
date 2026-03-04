defmodule Tuist.Bundles.BundleThresholdTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Bundles.BundleThreshold

  describe "changeset/2" do
    test "valid with all required fields" do
      changeset =
        BundleThreshold.changeset(%BundleThreshold{}, %{
          id: UUIDv7.generate(),
          name: "Size check",
          metric: :install_size,
          deviation_percentage: 5.0,
          baseline_branch: "main",
          project_id: 1
        })

      assert changeset.valid?
    end

    test "valid with optional bundle_name" do
      changeset =
        BundleThreshold.changeset(%BundleThreshold{}, %{
          id: UUIDv7.generate(),
          name: "Size check",
          metric: :download_size,
          deviation_percentage: 10.0,
          baseline_branch: "main",
          bundle_name: "MyApp",
          project_id: 1
        })

      assert changeset.valid?
    end

    test "defaults name to Untitled when omitted" do
      changeset =
        BundleThreshold.changeset(%BundleThreshold{}, %{
          id: UUIDv7.generate(),
          metric: :install_size,
          deviation_percentage: 5.0,
          baseline_branch: "main",
          project_id: 1
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :name) == "Untitled"
    end

    test "invalid without metric" do
      changeset =
        BundleThreshold.changeset(%BundleThreshold{}, %{
          id: UUIDv7.generate(),
          name: "Size check",
          deviation_percentage: 5.0,
          baseline_branch: "main",
          project_id: 1
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).metric
    end

    test "invalid without baseline_branch" do
      changeset =
        BundleThreshold.changeset(%BundleThreshold{}, %{
          id: UUIDv7.generate(),
          name: "Size check",
          metric: :install_size,
          deviation_percentage: 5.0,
          project_id: 1
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).baseline_branch
    end

    test "invalid with deviation_percentage <= 0" do
      changeset =
        BundleThreshold.changeset(%BundleThreshold{}, %{
          id: UUIDv7.generate(),
          name: "Size check",
          metric: :install_size,
          deviation_percentage: 0,
          baseline_branch: "main",
          project_id: 1
        })

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).deviation_percentage
    end

    test "invalid with negative deviation_percentage" do
      changeset =
        BundleThreshold.changeset(%BundleThreshold{}, %{
          id: UUIDv7.generate(),
          name: "Size check",
          metric: :install_size,
          deviation_percentage: -1.0,
          baseline_branch: "main",
          project_id: 1
        })

      refute changeset.valid?
      assert "must be greater than 0" in errors_on(changeset).deviation_percentage
    end
  end
end
