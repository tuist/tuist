defmodule Tuist.Storage.LocalS3Test do
  use ExUnit.Case, async: true

  alias Tuist.Storage.LocalS3

  describe "storage_directory/0" do
    test "returns a consistent path" do
      dir1 = LocalS3.storage_directory()
      dir2 = LocalS3.storage_directory()

      assert dir1 == dir2
      assert String.contains?(dir1, "tmp/local_s3_storage")
    end

    test "returns project-relative path" do
      storage_dir = LocalS3.storage_directory()

      assert is_binary(storage_dir)
      assert String.ends_with?(storage_dir, "tmp/local_s3_storage")
    end
  end

  describe "uploads_directory/0" do
    test "returns uploads subdirectory" do
      uploads_dir = LocalS3.uploads_directory()
      storage_dir = LocalS3.storage_directory()

      assert uploads_dir == Path.join(storage_dir, "uploads")
    end
  end

  describe "completed_directory/0" do
    test "returns completed subdirectory" do
      completed_dir = LocalS3.completed_directory()
      storage_dir = LocalS3.storage_directory()

      assert completed_dir == Path.join(storage_dir, "completed")
    end
  end
end
