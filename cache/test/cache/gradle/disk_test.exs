defmodule Cache.Gradle.DiskTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Cache.CacheArtifacts
  alias Cache.Disk
  alias Cache.Gradle.Disk, as: GradleDisk

  @test_account "test_account"
  @test_project "test_project"
  @test_cache_key "abc123"
  @test_key "#{@test_account}/#{@test_project}/gradle/ab/c1/#{@test_cache_key}"

  setup do
    {:ok, test_storage_dir} = Briefly.create(directory: true)

    Disk
    |> stub(:storage_dir, fn -> test_storage_dir end)
    |> stub(:artifact_path, fn key -> Path.join(test_storage_dir, key) end)

    stub(CacheArtifacts, :track_artifact_access, fn _key -> :ok end)
    {:ok, test_storage_dir: test_storage_dir}
  end

  describe "key/3" do
    test "constructs sharded Gradle key" do
      key = GradleDisk.key(@test_account, @test_project, @test_cache_key)
      assert key == @test_key
    end

    test "uses sharding for nested cache key" do
      nested_key = "deeply/nested/artifact"
      key = GradleDisk.key(@test_account, @test_project, nested_key)
      assert key == "#{@test_account}/#{@test_project}/gradle/de/ep/#{nested_key}"
    end
  end

  describe "exists?/3" do
    test "returns true when file exists" do
      path = Disk.artifact_path(@test_key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "test content")

      assert GradleDisk.exists?(@test_account, @test_project, @test_cache_key) == true
    end

    test "returns false when file doesn't exist" do
      assert GradleDisk.exists?("nonexistent", "project", "abcd1234") == false
    end
  end

  describe "put/4" do
    test "writes binary data to disk successfully" do
      data = "test artifact data"

      assert GradleDisk.put(@test_account, @test_project, @test_cache_key, data) == :ok

      path = Disk.artifact_path(@test_key)
      assert File.exists?(path)
      assert File.read!(path) == data
    end

    test "creates parent directories if they don't exist" do
      data = "nested artifact"

      assert GradleDisk.put("account", "project", "deeply/nested/artifact", data) == :ok

      path = Disk.artifact_path("account/project/gradle/de/ep/deeply/nested/artifact")
      assert File.exists?(path)
      assert File.read!(path) == data
    end

    test "overwrites existing file" do
      path = Disk.artifact_path(@test_key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "old content")

      new_data = "new content"
      assert GradleDisk.put(@test_account, @test_project, @test_cache_key, new_data) == :ok

      assert File.read!(path) == new_data
    end

    test "handles binary data" do
      binary_data = <<1, 2, 3, 4, 5, 255, 0, 128>>

      assert GradleDisk.put(@test_account, @test_project, @test_cache_key, binary_data) == :ok

      path = Disk.artifact_path(@test_key)
      assert File.read!(path) == binary_data
    end

    test "handles file tuple input" do
      {:ok, tmp_path} = Briefly.create()
      File.write!(tmp_path, "file content")

      assert GradleDisk.put(@test_account, @test_project, @test_cache_key, {:file, tmp_path}) == :ok

      path = Disk.artifact_path(@test_key)
      assert File.exists?(path)
      assert File.read!(path) == "file content"
    end
  end

  describe "stat/3" do
    test "returns file stat for existing artifact" do
      data = "test content for stat"
      assert GradleDisk.put(@test_account, @test_project, @test_cache_key, data) == :ok

      assert {:ok, stat} = GradleDisk.stat(@test_account, @test_project, @test_cache_key)
      assert %File.Stat{} = stat
      assert stat.size == byte_size(data)
      assert stat.type == :regular
    end

    test "returns error for non-existent artifact" do
      assert {:error, :enoent} = GradleDisk.stat("nonexistent", "project", "abcd1234")
    end
  end

  describe "local_accel_path/3" do
    test "builds internal X-Accel-Redirect path with sharded structure" do
      path = GradleDisk.local_accel_path(@test_account, @test_project, @test_cache_key)
      assert path == "/internal/local/#{@test_account}/#{@test_project}/gradle/ab/c1/#{@test_cache_key}"
    end

    test "builds internal path for nested cache key with sharded structure" do
      nested_key = "deeply/nested/artifact"
      path = GradleDisk.local_accel_path(@test_account, @test_project, nested_key)
      assert path == "/internal/local/#{@test_account}/#{@test_project}/gradle/de/ep/#{nested_key}"
    end
  end

  describe "integration test" do
    test "put and exists? roundtrip" do
      original_data = "This is test artifact content for roundtrip testing"

      assert GradleDisk.put(@test_account, @test_project, @test_cache_key, original_data) == :ok
      assert GradleDisk.exists?(@test_account, @test_project, @test_cache_key) == true
    end
  end
end
