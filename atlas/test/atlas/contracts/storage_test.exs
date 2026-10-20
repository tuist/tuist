defmodule Atlas.Contracts.StorageTest do
  use ExUnit.Case, async: true

  alias Atlas.Contracts.Storage

  describe "source/0" do
    test "reflects the :disk default that the config sets in dev and test" do
      assert Storage.source() == :disk
    end
  end

  describe "read/2 with :disk" do
    test "reads the placeholder stub shipped in priv/contracts/templates" do
      assert {:ok, contents} = Storage.read("2026-02", "msa.docx")
      assert byte_size(contents) > 0
    end

    test "returns {:error, :enoent} for missing files" do
      assert {:error, :enoent} = Storage.read("2026-02", "does-not-exist.docx")
    end
  end

  describe "stat/2 with :disk" do
    test "returns the on-disk byte size" do
      assert {:ok, size} = Storage.stat("2026-02", "msa.docx")
      assert size > 0
    end

    test "returns {:error, :enoent} for missing files" do
      assert {:error, :enoent} = Storage.stat("2026-02", "does-not-exist.docx")
    end
  end
end
