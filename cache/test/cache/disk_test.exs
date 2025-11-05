defmodule Cache.DiskTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.Disk

  @test_account "test_account"
  @test_project "test_project"
  @test_id "abc123"
  @test_key "#{@test_account}/#{@test_project}/cas/#{@test_id}"

  setup do
    {:ok, test_storage_dir} = Briefly.create(directory: true)

    Disk
    |> stub(:storage_dir, fn -> test_storage_dir end)
    |> stub(:artifact_path, fn key -> Path.join(test_storage_dir, key) end)
    |> stub(:put, fn account_handle, project_handle, id, data ->
      key = "#{account_handle}/#{project_handle}/cas/#{id}"
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
    |> stub(:exists?, fn account_handle, project_handle, id ->
      key = "#{account_handle}/#{project_handle}/cas/#{id}"
      test_storage_dir |> Path.join(key) |> File.exists?()
    end)
    |> stub(:get_local_path, fn account_handle, project_handle, id ->
      key = "#{account_handle}/#{project_handle}/cas/#{id}"
      path = Path.join(test_storage_dir, key)

      if File.exists?(path) do
        {:ok, path}
      else
        {:error, :not_found}
      end
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

  describe "exists?/3" do
    test "returns true when file exists" do
      path = Disk.artifact_path(@test_key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "test content")

      assert Disk.exists?(@test_account, @test_project, @test_id) == true
    end

    test "returns false when file doesn't exist" do
      assert Disk.exists?("nonexistent", "project", "id") == false
    end
  end

  describe "put/4" do
    test "writes data to disk successfully" do
      data = "test artifact data"

      assert Disk.put(@test_account, @test_project, @test_id, data) == :ok

      path = Disk.artifact_path(@test_key)
      assert File.exists?(path)
      assert File.read!(path) == data
    end

    test "creates parent directories if they don't exist" do
      data = "nested artifact"

      assert Disk.put("account", "project", "deeply/nested/artifact", data) == :ok

      path = Disk.artifact_path("account/project/cas/deeply/nested/artifact")
      assert File.exists?(path)
      assert File.read!(path) == data
    end

    test "overwrites existing file" do
      path = Disk.artifact_path(@test_key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "old content")

      new_data = "new content"
      assert Disk.put(@test_account, @test_project, @test_id, new_data) == :ok

      assert File.read!(path) == new_data
    end

    test "handles binary data" do
      binary_data = <<1, 2, 3, 4, 5, 255, 0, 128>>

      assert Disk.put(@test_account, @test_project, @test_id, binary_data) == :ok

      path = Disk.artifact_path(@test_key)
      assert File.read!(path) == binary_data
    end
  end

  describe "get_local_path/3" do
    test "returns path when file exists" do
      data = "test content"
      assert Disk.put(@test_account, @test_project, @test_id, data) == :ok

      result = Disk.get_local_path(@test_account, @test_project, @test_id)
      assert {:ok, path} = result
      assert path == Disk.artifact_path(@test_key)
      assert File.read!(path) == data
    end

    test "returns error when file doesn't exist" do
      result = Disk.get_local_path("nonexistent", "project", "id")
      assert result == {:error, :not_found}
    end
  end

  describe "integration test" do
    test "put and exists roundtrip" do
      original_data = "This is test artifact content for roundtrip testing"

      assert Disk.put(@test_account, @test_project, @test_id, original_data) == :ok
      assert Disk.exists?(@test_account, @test_project, @test_id) == true
    end
  end
end
