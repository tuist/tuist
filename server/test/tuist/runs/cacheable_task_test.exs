defmodule Tuist.Runs.CacheableTaskTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Runs.CacheableTask

  describe "changeset/2" do
    @valid_attrs %{
      type: :swift,
      status: :hit_remote,
      key: "cache_key_abc123"
    }

    test "creates valid changeset with all required attributes" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"

      changeset = CacheableTask.changeset(build_run_id, @valid_attrs)

      assert changeset.valid?
      assert changeset.changes.build_run_id == String.downcase(build_run_id)
      assert changeset.changes.type == "swift"
      assert changeset.changes.status == "hit_remote"
      assert changeset.changes.key == "cache_key_abc123"
    end

    test "converts type atom to string" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"
      attrs = Map.put(@valid_attrs, :type, :clang)

      changeset = CacheableTask.changeset(build_run_id, attrs)

      assert changeset.valid?
      assert changeset.changes.type == "clang"
    end

    test "converts status atom to string for hit_local" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"
      attrs = Map.put(@valid_attrs, :status, :hit_local)

      changeset = CacheableTask.changeset(build_run_id, attrs)

      assert changeset.valid?
      assert changeset.changes.status == "hit_local"
    end

    test "converts status atom to string for miss" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"
      attrs = Map.put(@valid_attrs, :status, :miss)

      changeset = CacheableTask.changeset(build_run_id, attrs)

      assert changeset.valid?
      assert changeset.changes.status == "miss"
    end

    test "handles string key correctly" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"
      attrs = Map.put(@valid_attrs, :key, "different_cache_key")

      changeset = CacheableTask.changeset(build_run_id, attrs)

      assert changeset.valid?
      assert changeset.changes.key == "different_cache_key"
    end

    test "includes build_run_id in changeset" do
      build_run_id = "A12673DA-1345-4077-BB30-D7576FEACE08"

      changeset = CacheableTask.changeset(build_run_id, @valid_attrs)

      assert changeset.valid?
      assert changeset.changes.build_run_id == String.downcase(build_run_id)
    end

    test "requires build_run_id" do
      changeset = CacheableTask.changeset(nil, @valid_attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).build_run_id
    end

    test "requires type" do
      attrs = Map.delete(@valid_attrs, :type)
      changeset = CacheableTask.changeset("B12673DA-1345-4077-BB30-D7576FEACE09", attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).type
    end

    test "requires status" do
      attrs = Map.delete(@valid_attrs, :status)
      changeset = CacheableTask.changeset("B12673DA-1345-4077-BB30-D7576FEACE09", attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).status
    end

    test "requires key" do
      attrs = Map.delete(@valid_attrs, :key)
      changeset = CacheableTask.changeset("B12673DA-1345-4077-BB30-D7576FEACE09", attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).key
    end
  end
end
