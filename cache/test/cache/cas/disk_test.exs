defmodule Cache.CAS.DiskTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.CacheArtifacts
  alias Cache.CAS.Disk, as: CASDisk
  alias Cache.Disk

  @test_account "test_account"
  @test_project "test_project"
  @test_id "abc123"
  @test_key "#{@test_account}/#{@test_project}/cas/ab/c1/#{@test_id}"

  setup do
    {:ok, test_storage_dir} = Briefly.create(directory: true)

    Disk
    |> stub(:storage_dir, fn -> test_storage_dir end)
    |> stub(:artifact_path, fn key -> Path.join(test_storage_dir, key) end)

    stub(CacheArtifacts, :track_artifact_access, fn _key -> :ok end)
    {:ok, test_storage_dir: test_storage_dir}
  end

  describe "key/3" do
    test "constructs sharded CAS key" do
      key = CASDisk.key(@test_account, @test_project, @test_id)
      assert key == @test_key
    end

    test "uses sharding for nested id" do
      nested_id = "deeply/nested/artifact"
      key = CASDisk.key(@test_account, @test_project, nested_id)
      assert key == "#{@test_account}/#{@test_project}/cas/de/ep/#{nested_id}"
    end
  end

  describe "exists?/3" do
    test "returns true when file exists" do
      path = Disk.artifact_path(@test_key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "test content")

      assert CASDisk.exists?(@test_account, @test_project, @test_id) == true
    end

    test "returns false when file doesn't exist" do
      assert CASDisk.exists?("nonexistent", "project", "abcd1234") == false
    end
  end

  describe "put/4" do
    test "writes binary data to disk successfully" do
      data = "test artifact data"

      assert CASDisk.put(@test_account, @test_project, @test_id, data) == :ok

      path = Disk.artifact_path(@test_key)
      assert File.exists?(path)
      assert File.read!(path) == data
    end

    test "creates parent directories if they don't exist" do
      data = "nested artifact"

      assert CASDisk.put("account", "project", "deeply/nested/artifact", data) == :ok

      path = Disk.artifact_path("account/project/cas/de/ep/deeply/nested/artifact")
      assert File.exists?(path)
      assert File.read!(path) == data
    end

    test "overwrites existing file" do
      path = Disk.artifact_path(@test_key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "old content")

      new_data = "new content"
      assert CASDisk.put(@test_account, @test_project, @test_id, new_data) == :ok

      assert File.read!(path) == new_data
    end

    test "handles binary data" do
      binary_data = <<1, 2, 3, 4, 5, 255, 0, 128>>

      assert CASDisk.put(@test_account, @test_project, @test_id, binary_data) == :ok

      path = Disk.artifact_path(@test_key)
      assert File.read!(path) == binary_data
    end

    test "handles file tuple input" do
      {:ok, tmp_path} = Briefly.create()
      File.write!(tmp_path, "file content")

      assert CASDisk.put(@test_account, @test_project, @test_id, {:file, tmp_path}) == :ok

      path = Disk.artifact_path(@test_key)
      assert File.exists?(path)
      assert File.read!(path) == "file content"
    end
  end

  describe "get_local_path/3" do
    test "returns path when file exists" do
      data = "test content"
      assert CASDisk.put(@test_account, @test_project, @test_id, data) == :ok

      result = CASDisk.get_local_path(@test_account, @test_project, @test_id)
      assert {:ok, path} = result
      assert path == Disk.artifact_path(@test_key)
      assert File.read!(path) == data
    end

    test "returns error when file doesn't exist" do
      result = CASDisk.get_local_path("nonexistent", "project", "abcd1234")
      assert result == {:error, :not_found}
    end
  end

  describe "stat/3" do
    test "returns file stat for existing artifact" do
      data = "test content for stat"
      assert CASDisk.put(@test_account, @test_project, @test_id, data) == :ok

      assert {:ok, stat} = CASDisk.stat(@test_account, @test_project, @test_id)
      assert %File.Stat{} = stat
      assert stat.size == byte_size(data)
      assert stat.type == :regular
    end

    test "returns error for non-existent artifact" do
      assert {:error, :enoent} = CASDisk.stat("nonexistent", "project", "abcd1234")
    end
  end

  describe "local_accel_path/3" do
    test "builds internal X-Accel-Redirect path with sharded structure" do
      path = CASDisk.local_accel_path(@test_account, @test_project, @test_id)
      assert path == "/internal/local/#{@test_account}/#{@test_project}/cas/ab/c1/#{@test_id}"
    end

    test "builds internal path for nested id with sharded structure" do
      nested_id = "deeply/nested/artifact"
      path = CASDisk.local_accel_path(@test_account, @test_project, nested_id)
      assert path == "/internal/local/#{@test_account}/#{@test_project}/cas/de/ep/#{nested_id}"
    end
  end

  describe "integration test" do
    test "put and exists? roundtrip" do
      original_data = "This is test artifact content for roundtrip testing"

      assert CASDisk.put(@test_account, @test_project, @test_id, original_data) == :ok
      assert CASDisk.exists?(@test_account, @test_project, @test_id) == true
    end
  end
end
