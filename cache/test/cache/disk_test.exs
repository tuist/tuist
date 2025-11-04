defmodule Cache.DiskTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.Disk

  @test_key "test_account/test_project/cas/abc123"

  setup do
    {:ok, test_storage_dir} = Briefly.create(directory: true)

    Disk
    |> stub(:storage_dir, fn -> test_storage_dir end)
    |> stub(:artifact_path, fn key -> Path.join(test_storage_dir, key) end)
    |> stub(:put, fn key, data ->
      path = Path.join(test_storage_dir, key)

      case data do
        {:file, tmp_path} ->
          File.mkdir_p!(Path.dirname(path))
          File.rename(tmp_path, path)
          :ok

        binary when is_binary(binary) ->
          File.mkdir_p!(Path.dirname(path))
          File.write!(path, binary)
          :ok
      end
    end)
    |> stub(:exists?, fn key ->
      Path.join(test_storage_dir, key) |> File.exists?()
    end)

    {:ok, test_storage_dir: test_storage_dir}
  end

  describe "storage_dir/0" do
    test "returns mocked storage directory", %{test_storage_dir: test_storage_dir} do
      assert Disk.storage_dir() == test_storage_dir
    end
  end

  describe "artifact_path/1" do
    test "constructs full path from key", %{test_storage_dir: test_storage_dir} do
      expected_path = Path.join(test_storage_dir, @test_key)
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

  describe "integration test" do
    test "put and exists roundtrip" do
      original_data = "This is test artifact content for roundtrip testing"

      assert Disk.put(@test_key, original_data) == :ok
      assert Disk.exists?(@test_key) == true
    end
  end
end
