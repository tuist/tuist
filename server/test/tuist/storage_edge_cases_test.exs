defmodule Tuist.Storage.EdgeCasesTest do
  use ExUnit.Case, async: true

  alias Tuist.Storage
  alias Tuist.Storage.LocalS3

  # Helper to create isolated test directories
  defp create_test_environment do
    test_id = 8 |> :crypto.strong_rand_bytes() |> Base.encode16() |> String.downcase()
    base_dir = Path.join([System.tmp_dir!(), "tuist_edge_cases_test_#{test_id}"])

    completed_dir = Path.join(base_dir, "completed")
    uploads_dir = Path.join(base_dir, "uploads")
    File.mkdir_p!(completed_dir)
    File.mkdir_p!(uploads_dir)

    %{
      base_dir: base_dir,
      completed_dir: completed_dir,
      uploads_dir: uploads_dir
    }
  end

  defp cleanup_test_environment(%{base_dir: base_dir}) do
    File.rm_rf!(base_dir)
  end

  defp with_test_storage(test_env, fun) do
    Mimic.stub(LocalS3, :completed_directory, fn -> test_env.completed_dir end)
    Mimic.stub(LocalS3, :uploads_directory, fn -> test_env.uploads_dir end)
    Mimic.stub(LocalS3, :storage_directory, fn -> test_env.base_dir end)

    fun.()
  end

  setup do
    Mimic.copy(LocalS3)

    Mimic.stub(Tuist.Environment, :use_local_storage?, fn -> true end)
    Mimic.stub(Tuist.Environment, :s3_bucket_name, fn -> "edge-test-bucket" end)

    test_env = create_test_environment()

    on_exit(fn -> cleanup_test_environment(test_env) end)

    {:ok, test_env: test_env}
  end

  describe "edge cases for file paths" do
    test "handles empty object key", %{test_env: test_env} do
      object_key = ""

      with_test_storage(test_env, fn ->
        assert Storage.object_exists?(object_key) == false
        assert Storage.get_object_size(object_key) == 0
        assert Storage.get_object_as_string(object_key) == nil
      end)
    end

    test "handles object key with only slashes", %{test_env: test_env} do
      object_key = "///"

      with_test_storage(test_env, fn ->
        assert Storage.object_exists?(object_key) == false
        assert Storage.get_object_size(object_key) == 0
        assert Storage.get_object_as_string(object_key) == nil
      end)
    end

    test "handles object key starting with slash", %{test_env: test_env} do
      object_key = "/leading/slash/file.txt"

      with_test_storage(test_env, fn ->
        assert Storage.object_exists?(object_key) == false
        assert Storage.get_object_size(object_key) == 0
        assert Storage.get_object_as_string(object_key) == nil
      end)
    end

    test "handles object key ending with slash", %{test_env: test_env} do
      object_key = "trailing/slash/"

      with_test_storage(test_env, fn ->
        assert Storage.object_exists?(object_key) == false
        assert Storage.get_object_size(object_key) == 0
        assert Storage.get_object_as_string(object_key) == nil
      end)
    end

    test "handles very long object key", %{test_env: test_env} do
      # Create a very long but valid object key
      long_segment = String.duplicate("a", 100)
      object_key = Enum.join(for(_ <- 1..5, do: long_segment), "/") <> ".txt"

      with_test_storage(test_env, fn ->
        assert Storage.object_exists?(object_key) == false
        assert Storage.get_object_size(object_key) == 0
        assert Storage.get_object_as_string(object_key) == nil
      end)
    end

    test "handles object key with consecutive slashes", %{test_env: test_env} do
      object_key = "path//with///consecutive////slashes.txt"

      with_test_storage(test_env, fn ->
        assert Storage.object_exists?(object_key) == false
        assert Storage.get_object_size(object_key) == 0
        assert Storage.get_object_as_string(object_key) == nil
      end)
    end

    test "handles object key with dots", %{test_env: test_env} do
      object_key = "./relative/../path/./file.txt"

      with_test_storage(test_env, fn ->
        assert Storage.object_exists?(object_key) == false
        assert Storage.get_object_size(object_key) == 0
        assert Storage.get_object_as_string(object_key) == nil
      end)
    end
  end

  describe "edge cases for file operations" do
    test "handles file that becomes inaccessible after creation", %{test_env: test_env} do
      bucket = "edge-test-bucket"
      object_key = "temp-file.txt"
      content = "temporary content"

      with_test_storage(test_env, fn ->
        # Create file
        object_path = Path.join([test_env.completed_dir, bucket, object_key])
        File.mkdir_p!(Path.dirname(object_path))
        File.write!(object_path, content)

        # Verify it exists initially
        assert Storage.object_exists?(object_key) == true
        assert Storage.get_object_size(object_key) == byte_size(content)

        # Remove the file to simulate it becoming inaccessible
        File.rm!(object_path)

        # Now operations should handle missing file gracefully
        assert Storage.object_exists?(object_key) == false
        assert Storage.get_object_size(object_key) == 0
        assert Storage.get_object_as_string(object_key) == nil
      end)
    end

    test "handles directory instead of file", %{test_env: test_env} do
      bucket = "edge-test-bucket"
      object_key = "directory-as-file"

      with_test_storage(test_env, fn ->
        # Create a directory where we expect a file
        dir_path = Path.join([test_env.completed_dir, bucket, object_key])
        File.mkdir_p!(dir_path)

        # Operations should treat directory as non-existent file
        assert Storage.object_exists?(object_key) == false
        assert Storage.get_object_size(object_key) == 0
        assert Storage.get_object_as_string(object_key) == nil
      end)
    end

    test "handles symlink to file", %{test_env: test_env} do
      bucket = "edge-test-bucket"
      target_key = "target-file.txt"
      link_key = "symlink-file.txt"
      content = "symlinked content"

      with_test_storage(test_env, fn ->
        # Create target file
        target_path = Path.join([test_env.completed_dir, bucket, target_key])
        File.mkdir_p!(Path.dirname(target_path))
        File.write!(target_path, content)

        # Create symlink (skip if symlinks not supported on this system)
        link_path = Path.join([test_env.completed_dir, bucket, link_key])

        case File.ln_s(target_path, link_path) do
          :ok ->
            # Symlink created successfully, test it
            assert Storage.object_exists?(link_key) == true
            assert Storage.get_object_size(link_key) == byte_size(content)
            assert Storage.get_object_as_string(link_key) == content

          {:error, :enotsup} ->
            # Symlinks not supported on this system, skip test
            :ok

          {:error, reason} ->
            flunk("Failed to create symlink: #{inspect(reason)}")
        end
      end)
    end

    test "handles broken symlink", %{test_env: test_env} do
      bucket = "edge-test-bucket"
      link_key = "broken-symlink.txt"

      with_test_storage(test_env, fn ->
        # Create symlink to non-existent file
        link_path = Path.join([test_env.completed_dir, bucket, link_key])
        File.mkdir_p!(Path.dirname(link_path))
        non_existent_path = Path.join([test_env.completed_dir, bucket, "does-not-exist.txt"])

        case File.ln_s(non_existent_path, link_path) do
          :ok ->
            # Broken symlink created, operations should handle it gracefully
            assert Storage.object_exists?(link_key) == false
            assert Storage.get_object_size(link_key) == 0
            assert Storage.get_object_as_string(link_key) == nil

          {:error, :enotsup} ->
            # Symlinks not supported, skip test
            :ok

          {:error, reason} ->
            flunk("Failed to create broken symlink: #{inspect(reason)}")
        end
      end)
    end
  end

  describe "edge cases for bucket handling" do
    test "handles operations when bucket directory doesn't exist", %{test_env: test_env} do
      # Don't create the bucket directory, test with non-existent bucket
      Mimic.stub(Tuist.Environment, :s3_bucket_name, fn -> "non-existent-bucket" end)

      object_key = "some/file.txt"

      with_test_storage(test_env, fn ->
        assert Storage.object_exists?(object_key) == false
        assert Storage.get_object_size(object_key) == 0
        assert Storage.get_object_as_string(object_key) == nil
      end)
    end

    test "handles operations when completed directory doesn't exist", %{test_env: test_env} do
      # Remove the completed directory
      File.rm_rf!(test_env.completed_dir)

      object_key = "test-file.txt"

      with_test_storage(test_env, fn ->
        assert Storage.object_exists?(object_key) == false
        assert Storage.get_object_size(object_key) == 0
        assert Storage.get_object_as_string(object_key) == nil
      end)
    end

    test "handles bucket name with special characters", %{test_env: test_env} do
      # Test with bucket name containing special characters (though this might not be realistic)
      Mimic.stub(Tuist.Environment, :s3_bucket_name, fn -> "test-bucket-with-special-chars!@#" end)

      object_key = "test-file.txt"

      with_test_storage(test_env, fn ->
        # These should not crash, even with unusual bucket names
        assert Storage.object_exists?(object_key) == false
        assert Storage.get_object_size(object_key) == 0
        assert Storage.get_object_as_string(object_key) == nil
      end)
    end
  end

  describe "stress tests for robustness" do
    test "handles many rapid sequential operations", %{test_env: test_env} do
      bucket = "edge-test-bucket"
      object_key = "stress-test.txt"
      content = "stress test content"

      with_test_storage(test_env, fn ->
        # Create file
        object_path = Path.join([test_env.completed_dir, bucket, object_key])
        File.mkdir_p!(Path.dirname(object_path))
        File.write!(object_path, content)

        # Perform many rapid operations
        for _i <- 1..100 do
          assert Storage.object_exists?(object_key) == true
          assert Storage.get_object_size(object_key) == byte_size(content)
          assert Storage.get_object_as_string(object_key) == content
        end
      end)
    end

    test "handles operations on files with extreme sizes", %{test_env: test_env} do
      bucket = "edge-test-bucket"

      with_test_storage(test_env, fn ->
        # Test zero-byte file (already covered but included for completeness)
        empty_key = "empty.txt"
        empty_path = Path.join([test_env.completed_dir, bucket, empty_key])
        File.mkdir_p!(Path.dirname(empty_path))
        File.write!(empty_path, "")

        assert Storage.object_exists?(empty_key) == true
        assert Storage.get_object_size(empty_key) == 0
        assert Storage.get_object_as_string(empty_key) == ""

        # Test single-byte file
        single_key = "single.txt"
        single_path = Path.join([test_env.completed_dir, bucket, single_key])
        File.write!(single_path, "A")

        assert Storage.object_exists?(single_key) == true
        assert Storage.get_object_size(single_key) == 1
        assert Storage.get_object_as_string(single_key) == "A"
      end)
    end

    test "handles concurrent operations on same file", %{test_env: test_env} do
      bucket = "edge-test-bucket"
      object_key = "concurrent-access.txt"
      content = "content for concurrent access"

      with_test_storage(test_env, fn ->
        # Create file
        object_path = Path.join([test_env.completed_dir, bucket, object_key])
        File.mkdir_p!(Path.dirname(object_path))
        File.write!(object_path, content)

        # Run concurrent read operations
        tasks =
          for _i <- 1..20 do
            Task.async(fn ->
              # Each task performs all operations
              exists = Storage.object_exists?(object_key)
              size = Storage.get_object_size(object_key)
              file_content = Storage.get_object_as_string(object_key)

              {exists, size, file_content}
            end)
          end

        results = Task.await_many(tasks, 5000)

        # All results should be consistent
        for {exists, size, file_content} <- results do
          assert exists == true
          assert size == byte_size(content)
          assert file_content == content
        end
      end)
    end
  end
end
