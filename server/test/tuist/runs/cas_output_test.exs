defmodule Tuist.Runs.CASOutputTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Runs.CASOutput

  describe "changeset/2" do
    @valid_attrs %{
      node_id: "MyTarget",
      checksum: "abc123def456",
      size: 1024,
      duration: 1.5,
      compressed_size: 512,
      operation: :download
    }

    test "creates valid changeset with all required attributes" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"

      changeset = CASOutput.changeset(build_run_id, @valid_attrs)

      assert changeset.valid?
    end

    test "converts operation atom to string for download" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"
      attrs = Map.put(@valid_attrs, :operation, :download)

      changeset = CASOutput.changeset(build_run_id, attrs)

      assert changeset.valid?
      assert changeset.changes.operation == "download"
    end

    test "converts operation atom to string for upload" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"
      attrs = Map.put(@valid_attrs, :operation, :upload)

      changeset = CASOutput.changeset(build_run_id, attrs)

      assert changeset.valid?
      assert changeset.changes.operation == "upload"
    end

    test "truncates duration milliseconds to integer" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"
      attrs = Map.put(@valid_attrs, :duration, 2500.7)

      changeset = CASOutput.changeset(build_run_id, attrs)

      assert changeset.valid?
      assert changeset.changes.duration == 2500
    end

    test "truncates fractional milliseconds" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"
      attrs = Map.put(@valid_attrs, :duration, 1999.9)

      changeset = CASOutput.changeset(build_run_id, attrs)

      assert changeset.valid?
      assert changeset.changes.duration == 1999
    end

    test "handles integer duration values" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"
      attrs = Map.put(@valid_attrs, :duration, 3000)

      changeset = CASOutput.changeset(build_run_id, attrs)

      assert changeset.valid?
      assert changeset.changes.duration == 3000
    end

    test "handles string node_id correctly" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"
      attrs = Map.put(@valid_attrs, :node_id, "DifferentTarget")

      changeset = CASOutput.changeset(build_run_id, attrs)

      assert changeset.valid?
      assert changeset.changes.node_id == "DifferentTarget"
    end

    test "handles different checksum values" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"
      attrs = Map.put(@valid_attrs, :checksum, "xyz789")

      changeset = CASOutput.changeset(build_run_id, attrs)

      assert changeset.valid?
      assert changeset.changes.checksum == "xyz789"
    end

    test "handles different size values" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"
      attrs = Map.put(@valid_attrs, :size, 2048)

      changeset = CASOutput.changeset(build_run_id, attrs)

      assert changeset.valid?
      assert changeset.changes.size == 2048
    end

    test "handles different compressed_size values" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"
      attrs = Map.put(@valid_attrs, :compressed_size, 1024)

      changeset = CASOutput.changeset(build_run_id, attrs)

      assert changeset.valid?
      assert changeset.changes.compressed_size == 1024
    end

    test "includes build_run_id in changeset" do
      build_run_id = "A12673DA-1345-4077-BB30-D7576FEACE08"

      changeset = CASOutput.changeset(build_run_id, @valid_attrs)

      assert changeset.valid?
      assert changeset.changes.build_run_id == String.downcase(build_run_id)
    end

    test "requires build_run_id" do
      changeset = CASOutput.changeset(nil, @valid_attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).build_run_id
    end

    test "requires node_id" do
      attrs = Map.delete(@valid_attrs, :node_id)
      changeset = CASOutput.changeset("B12673DA-1345-4077-BB30-D7576FEACE09", attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).node_id
    end

    test "requires checksum" do
      attrs = Map.delete(@valid_attrs, :checksum)
      changeset = CASOutput.changeset("B12673DA-1345-4077-BB30-D7576FEACE09", attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).checksum
    end

    test "requires size" do
      attrs = Map.delete(@valid_attrs, :size)
      changeset = CASOutput.changeset("B12673DA-1345-4077-BB30-D7576FEACE09", attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).size
    end

    test "requires duration" do
      attrs = Map.delete(@valid_attrs, :duration)
      changeset = CASOutput.changeset("B12673DA-1345-4077-BB30-D7576FEACE09", attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).duration
    end

    test "requires compressed_size" do
      attrs = Map.delete(@valid_attrs, :compressed_size)
      changeset = CASOutput.changeset("B12673DA-1345-4077-BB30-D7576FEACE09", attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).compressed_size
    end

    test "requires operation" do
      attrs = Map.delete(@valid_attrs, :operation)
      changeset = CASOutput.changeset("B12673DA-1345-4077-BB30-D7576FEACE09", attrs)

      refute changeset.valid?
      assert "can't be blank" in errors_on(changeset).operation
    end

    test "accepts valid type values" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"

      # Test with a few different valid types
      for type <- ["swift", "swiftsourceinfo", "assembly", "unknown"] do
        attrs = Map.put(@valid_attrs, :type, type)
        changeset = CASOutput.changeset(build_run_id, attrs)

        assert changeset.valid?, "Expected #{type} to be valid"
        assert changeset.changes.type == type
      end
    end

    test "rejects invalid type values" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"
      attrs = Map.put(@valid_attrs, :type, "invalid-type")

      changeset = CASOutput.changeset(build_run_id, attrs)

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).type
    end

    test "defaults to unknown when type is not provided" do
      build_run_id = "B12673DA-1345-4077-BB30-D7576FEACE09"
      attrs = Map.delete(@valid_attrs, :type)

      changeset = CASOutput.changeset(build_run_id, attrs)

      assert changeset.valid?
      assert changeset.changes.type == "unknown"
    end
  end
end
