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
end
