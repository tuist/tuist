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

    test "supports absolute byte limits and fractional percentages" do
      attrs = %{name: "Size check", metric: :install_size, baseline_branch: "main", project_id: 1}

      absolute = BundleThreshold.changeset(%BundleThreshold{}, Map.put(attrs, :deviation_bytes, 1_500_000))
      assert absolute.valid?
      assert BundleThreshold.limit_label(Ecto.Changeset.apply_changes(absolute)) == "1.5 MB"

      percentage = BundleThreshold.changeset(%BundleThreshold{}, Map.put(attrs, :deviation_percentage, 0.47))
      assert percentage.valid?
      assert BundleThreshold.limit_label(Ecto.Changeset.apply_changes(percentage)) == "0.47%"
    end

    test "requires exactly one limit" do
      attrs = %{name: "Size check", metric: :install_size, baseline_branch: "main", project_id: 1}
      missing = BundleThreshold.changeset(%BundleThreshold{}, attrs)
      refute missing.valid?
      assert "can't be blank" in errors_on(missing).deviation_percentage

      both =
        BundleThreshold.changeset(
          %BundleThreshold{},
          Map.merge(attrs, %{deviation_bytes: 1_500_000, deviation_percentage: 0.47})
        )

      refute both.valid?
      assert "must not be set with a percentage" in errors_on(both).deviation_bytes
    end

    test "rejects invalid byte limits" do
      for bytes <- [0, -1, 1.5, 9_223_372_036_854_775_808] do
        changeset =
          BundleThreshold.changeset(%BundleThreshold{}, %{
            name: "Size check",
            metric: :install_size,
            baseline_branch: "main",
            project_id: 1,
            deviation_bytes: bytes
          })

        refute changeset.valid?
        assert errors_on(changeset).deviation_bytes != []
      end
    end

    test "changing units requires clearing the previous limit and preserves unrelated edits" do
      threshold = %BundleThreshold{
        name: "Size check",
        metric: :install_size,
        baseline_branch: "main",
        project_id: 1,
        deviation_percentage: 0.47
      }

      refute BundleThreshold.changeset(threshold, %{deviation_bytes: 1_500_000}).valid?
      switched = BundleThreshold.changeset(threshold, %{deviation_bytes: 1_500_000, deviation_percentage: nil})
      assert switched.valid?
      absolute = Ecto.Changeset.apply_changes(switched)
      assert BundleThreshold.changeset(absolute, %{name: "Renamed"}).valid?
      assert BundleThreshold.changeset(absolute, %{deviation_bytes: nil, deviation_percentage: 0.47}).valid?
    end

    test "formats byte limits without losing precision" do
      assert BundleThreshold.megabytes(1) == "0.000001"
      assert BundleThreshold.megabytes(1_500_001) == "1.500001"
      assert BundleThreshold.megabytes(9_223_372_036_854_775_807) == "9223372036854.775807"
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

    test "invalid without name" do
      changeset =
        BundleThreshold.changeset(%BundleThreshold{}, %{
          id: UUIDv7.generate(),
          metric: :install_size,
          deviation_percentage: 5.0,
          baseline_branch: "main",
          project_id: 1
        })

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).name
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
