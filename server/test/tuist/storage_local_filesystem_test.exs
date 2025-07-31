defmodule Tuist.Storage.LocalFilesystemTest do
  use ExUnit.Case, async: true

  alias Tuist.Storage
  alias Tuist.Storage.LocalS3

  # Helper to create isolated test directories
  defp create_test_environment do
    # Create a unique test directory for this test
    test_id = 8 |> :crypto.strong_rand_bytes() |> Base.encode16() |> String.downcase()
    base_dir = Path.join([System.tmp_dir!(), "tuist_local_s3_test_#{test_id}"])

    # Create the directory structure
    completed_dir = Path.join(base_dir, "completed")
    uploads_dir = Path.join(base_dir, "uploads")
    File.mkdir_p!(completed_dir)
    File.mkdir_p!(uploads_dir)

    # Return paths for cleanup
    %{
      base_dir: base_dir,
      completed_dir: completed_dir,
      uploads_dir: uploads_dir
    }
  end

  defp cleanup_test_environment(%{base_dir: base_dir}) do
    File.rm_rf!(base_dir)
  end

  defp create_test_file(completed_dir, bucket, object_key, content) do
    object_path = Path.join([completed_dir, bucket, object_key])
    File.mkdir_p!(Path.dirname(object_path))
    File.write!(object_path, content)
    object_path
  end

  # Stub the LocalS3 module functions to use our test directories
  defp with_test_storage(test_env, fun) do
    # Mock the LocalS3 functions to return our test directories
    Mimic.stub(LocalS3, :completed_directory, fn -> test_env.completed_dir end)
    Mimic.stub(LocalS3, :uploads_directory, fn -> test_env.uploads_dir end)
    Mimic.stub(LocalS3, :storage_directory, fn -> test_env.base_dir end)

    fun.()
  end

  setup do
    # Start Mimic for this test
    Mimic.copy(LocalS3)

    # Enable local storage for all tests in this module
    Mimic.stub(Tuist.Environment, :use_local_storage?, fn -> true end)
    Mimic.stub(Tuist.Environment, :s3_bucket_name, fn -> "test-bucket" end)

    test_env = create_test_environment()

    on_exit(fn -> cleanup_test_environment(test_env) end)

    {:ok, test_env: test_env}
  end

  describe "object_exists?/1 with local storage" do
    test "returns true when file exists", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "path/to/test-file.txt"
      content = "test content"

      with_test_storage(test_env, fn ->
        create_test_file(test_env.completed_dir, bucket, object_key, content)

        assert Storage.object_exists?(object_key) == true
      end)
    end

    test "returns false when file does not exist", %{test_env: test_env} do
      object_key = "nonexistent/file.txt"

      with_test_storage(test_env, fn ->
        assert Storage.object_exists?(object_key) == false
      end)
    end

    test "returns false when directory exists but file does not", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "existing/dir/nonexistent.txt"

      with_test_storage(test_env, fn ->
        # Create the directory but not the file
        dir_path = Path.join([test_env.completed_dir, bucket, "existing/dir"])
        File.mkdir_p!(dir_path)

        assert Storage.object_exists?(object_key) == false
      end)
    end

    test "handles nested paths correctly", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "very/deeply/nested/path/file.txt"
      content = "nested content"

      with_test_storage(test_env, fn ->
        create_test_file(test_env.completed_dir, bucket, object_key, content)

        assert Storage.object_exists?(object_key) == true
      end)
    end

    test "handles special characters in object key", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "special chars/file with spaces & symbols!@#.txt"
      content = "special content"

      with_test_storage(test_env, fn ->
        create_test_file(test_env.completed_dir, bucket, object_key, content)

        assert Storage.object_exists?(object_key) == true
      end)
    end
  end

  describe "get_object_size/1 with local storage" do
    test "returns correct size for existing file", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "size-test.txt"
      content = "This content has exactly 35 chars."
      expected_size = byte_size(content)

      with_test_storage(test_env, fn ->
        create_test_file(test_env.completed_dir, bucket, object_key, content)

        assert Storage.get_object_size(object_key) == expected_size
      end)
    end

    test "returns 0 for nonexistent file", %{test_env: test_env} do
      object_key = "nonexistent.txt"

      with_test_storage(test_env, fn ->
        assert Storage.get_object_size(object_key) == 0
      end)
    end

    test "returns correct size for empty file", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "empty.txt"
      content = ""

      with_test_storage(test_env, fn ->
        create_test_file(test_env.completed_dir, bucket, object_key, content)

        assert Storage.get_object_size(object_key) == 0
      end)
    end

    test "returns correct size for large content", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "large.txt"
      # Create content that's 1MB
      content = String.duplicate("A", 1_048_576)

      with_test_storage(test_env, fn ->
        create_test_file(test_env.completed_dir, bucket, object_key, content)

        assert Storage.get_object_size(object_key) == 1_048_576
      end)
    end

    test "handles binary content correctly", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "binary.dat"
      content = <<1, 2, 3, 4, 5, 255, 254, 253>>

      with_test_storage(test_env, fn ->
        create_test_file(test_env.completed_dir, bucket, object_key, content)

        assert Storage.get_object_size(object_key) == 8
      end)
    end
  end

  describe "get_object_as_string/1 with local storage" do
    test "returns correct content for existing file", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "content-test.txt"
      content = "Hello, World!\nThis is a test file with multiple lines.\n"

      with_test_storage(test_env, fn ->
        create_test_file(test_env.completed_dir, bucket, object_key, content)

        assert Storage.get_object_as_string(object_key) == content
      end)
    end

    test "returns nil for nonexistent file", %{test_env: test_env} do
      object_key = "nonexistent.txt"

      with_test_storage(test_env, fn ->
        assert Storage.get_object_as_string(object_key) == nil
      end)
    end

    test "returns empty string for empty file", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "empty.txt"
      content = ""

      with_test_storage(test_env, fn ->
        create_test_file(test_env.completed_dir, bucket, object_key, content)

        assert Storage.get_object_as_string(object_key) == ""
      end)
    end

    test "handles unicode content correctly", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "unicode.txt"
      content = "Hello 世界! 🌍 Café naïve résumé"

      with_test_storage(test_env, fn ->
        create_test_file(test_env.completed_dir, bucket, object_key, content)

        assert Storage.get_object_as_string(object_key) == content
      end)
    end

    test "handles JSON content correctly", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "data.json"
      content = ~s({"name": "test", "value": 42, "nested": {"array": [1, 2, 3]}})

      with_test_storage(test_env, fn ->
        create_test_file(test_env.completed_dir, bucket, object_key, content)

        assert Storage.get_object_as_string(object_key) == content
      end)
    end

    test "handles large text content", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "large-text.txt"
      # Create a reasonably large text file
      line = "This is line with some random content and more text to make it longer.\n"
      content = String.duplicate(line, 200)
      expected_size = byte_size(content)

      with_test_storage(test_env, fn ->
        create_test_file(test_env.completed_dir, bucket, object_key, content)

        result = Storage.get_object_as_string(object_key)
        assert result == content
        assert byte_size(result) == expected_size
        # Should be reasonably large
        assert byte_size(result) > 5_000
      end)
    end
  end

  describe "stream_object/1 with local storage" do
    test "streams file content correctly", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "stream-test.txt"
      content = "Line 1\nLine 2\nLine 3\nLine 4\n"

      with_test_storage(test_env, fn ->
        create_test_file(test_env.completed_dir, bucket, object_key, content)

        stream = Storage.stream_object(object_key)
        result = Enum.join(stream, "")

        assert result == content
      end)
    end

    test "streams large files efficiently", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "large-stream.txt"
      # Create a file with 1000 lines
      lines = for i <- 1..1000, do: "This is line #{i} with some content\n"
      content = Enum.join(lines)

      with_test_storage(test_env, fn ->
        create_test_file(test_env.completed_dir, bucket, object_key, content)

        stream = Storage.stream_object(object_key)
        line_count = stream |> Stream.map(&String.split(&1, "\n")) |> Stream.flat_map(& &1) |> Enum.count()

        # Should have 1000 lines plus some empty strings from splitting
        assert line_count >= 1000
      end)
    end

    test "handles binary files in stream", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "binary-stream.dat"
      # Create binary content
      content = for _i <- 1..100, do: <<:rand.uniform(256) - 1>>, into: <<>>

      with_test_storage(test_env, fn ->
        create_test_file(test_env.completed_dir, bucket, object_key, content)

        stream = Storage.stream_object(object_key)
        result = Enum.join(stream, "")

        assert result == content
        assert byte_size(result) == 100
      end)
    end
  end

  describe "integration tests with complex scenarios" do
    test "handles concurrent access to different files", %{test_env: test_env} do
      bucket = "test-bucket"

      with_test_storage(test_env, fn ->
        # Create multiple files
        files =
          for i <- 1..10 do
            object_key = "concurrent/file_#{i}.txt"
            content = "Content for file #{i}"
            create_test_file(test_env.completed_dir, bucket, object_key, content)
            {object_key, content}
          end

        # Test concurrent access using tasks
        tasks =
          for {object_key, expected_content} <- files do
            Task.async(fn ->
              # Test all operations on each file
              exists = Storage.object_exists?(object_key)
              size = Storage.get_object_size(object_key)
              content = Storage.get_object_as_string(object_key)

              {exists, size, content, expected_content}
            end)
          end

        results = Task.await_many(tasks, 5000)

        # Verify all results
        for {exists, size, content, expected_content} <- results do
          assert exists == true
          assert size == byte_size(expected_content)
          assert content == expected_content
        end
      end)
    end

    test "preserves file content integrity", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "integrity-test.txt"

      # Test with various content types
      test_contents = [
        "Simple ASCII text",
        "Unicode: 你好世界 🌍",
        ~s(JSON: {"key": "value", "number": 42}),
        "Binary-like: \x00\x01\x02\xFF\xFE",
        "Multi-line:\nLine 1\nLine 2\n\nLine 4",
        # Large content
        String.duplicate("A", 10_000)
      ]

      with_test_storage(test_env, fn ->
        for content <- test_contents do
          # Create file with content
          create_test_file(test_env.completed_dir, bucket, object_key, content)

          # Verify all operations return consistent results
          assert Storage.object_exists?(object_key) == true
          assert Storage.get_object_size(object_key) == byte_size(content)
          assert Storage.get_object_as_string(object_key) == content

          # Verify streaming also returns correct content
          streamed_content = object_key |> Storage.stream_object() |> Enum.join("")
          assert streamed_content == content

          # Clean up for next iteration
          File.rm!(Path.join([test_env.completed_dir, bucket, object_key]))
        end
      end)
    end

    test "handles missing parent directories gracefully", %{test_env: test_env} do
      bucket = "test-bucket"
      object_key = "missing/parent/dirs/file.txt"

      with_test_storage(test_env, fn ->
        # Initially file doesn't exist
        assert Storage.object_exists?(object_key) == false
        assert Storage.get_object_size(object_key) == 0
        assert Storage.get_object_as_string(object_key) == nil

        # Create the file (this tests that our test helper creates parent dirs)
        content = "test content"
        create_test_file(test_env.completed_dir, bucket, object_key, content)

        # Now it should exist and be accessible
        assert Storage.object_exists?(object_key) == true
        assert Storage.get_object_size(object_key) == byte_size(content)
        assert Storage.get_object_as_string(object_key) == content
      end)
    end
  end
end
