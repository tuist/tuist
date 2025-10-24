defmodule Tuist.Cache.DiskTest do
  use ExUnit.Case, async: false

  alias Tuist.Cache.Disk

  @test_storage_dir "tmp/test_cas"
  @test_key "test_account/test_project/cas/abc123"

  setup do
    Application.put_env(:tuist, :cas, storage_dir: @test_storage_dir)

    on_exit(fn ->
      File.rm_rf!(@test_storage_dir)
    end)

    :ok
  end

  describe "storage_dir/0" do
    test "returns configured storage directory" do
      assert Disk.storage_dir() == @test_storage_dir
    end

    test "returns default directory when not configured" do
      Application.delete_env(:tuist, :cas)
      assert Disk.storage_dir() == "tmp/cas"
    end
  end

  describe "artifact_path/1" do
    test "constructs full path from key" do
      expected_path = Path.join(@test_storage_dir, @test_key)
      assert Disk.artifact_path(@test_key) == expected_path
    end
  end

  describe "exists?/1" do
    test "returns true when file exists" do
      path = Disk.artifact_path(@test_key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "test content")

      assert Disk.exists?(@test_key) == true
    end

    test "returns false when file doesn't exist" do
      assert Disk.exists?("nonexistent/key") == false
    end
  end

  describe "put/2" do
    test "writes data to disk successfully" do
      data = "test artifact data"

      assert Disk.put(@test_key, data) == :ok

      path = Disk.artifact_path(@test_key)
      assert File.exists?(path)
      assert File.read!(path) == data
    end

    test "creates parent directories if they don't exist" do
      deep_key = "account/project/cas/deeply/nested/artifact"
      data = "nested artifact"

      assert Disk.put(deep_key, data) == :ok

      path = Disk.artifact_path(deep_key)
      assert File.exists?(path)
      assert File.read!(path) == data
    end

    test "overwrites existing file" do
      path = Disk.artifact_path(@test_key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "old content")

      new_data = "new content"
      assert Disk.put(@test_key, new_data) == :ok

      assert File.read!(path) == new_data
    end

    test "handles binary data" do
      binary_data = <<1, 2, 3, 4, 5, 255, 0, 128>>

      assert Disk.put(@test_key, binary_data) == :ok

      path = Disk.artifact_path(@test_key)
      assert File.read!(path) == binary_data
    end
  end

  describe "stream/1" do
    test "returns stream for reading file" do
      data = "line 1\nline 2\nline 3\n"
      path = Disk.artifact_path(@test_key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, data)

      stream = Disk.stream(@test_key)
      content = Enum.join(stream)

      assert content == data
    end

    test "streams large file in chunks" do
      large_data = String.duplicate("a", 100_000)
      path = Disk.artifact_path(@test_key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, large_data)

      stream = Disk.stream(@test_key)
      chunks = Enum.to_list(stream)

      assert length(chunks) > 1
      assert Enum.join(chunks) == large_data
    end

    test "handles binary content" do
      binary_data = :crypto.strong_rand_bytes(10_000)
      path = Disk.artifact_path(@test_key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, binary_data)

      stream = Disk.stream(@test_key)
      streamed_content = Enum.reduce(stream, <<>>, fn chunk, acc -> acc <> chunk end)

      assert streamed_content == binary_data
    end
  end

  describe "integration test" do
    test "put and stream roundtrip" do
      original_data = "This is test artifact content for roundtrip testing"

      assert Disk.put(@test_key, original_data) == :ok
      assert Disk.exists?(@test_key) == true

      stream = Disk.stream(@test_key)
      retrieved_data = Enum.join(stream)

      assert retrieved_data == original_data
    end
  end
end
