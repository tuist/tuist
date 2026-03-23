defmodule Cache.Registry.DiskTest do
  use ExUnit.Case, async: true

  alias Cache.Disk
  alias Cache.Registry.Disk, as: RegistryDisk

  @test_scope "apple"
  @test_name "parser"
  @test_version "1.0.0"
  @test_filename "source_archive.zip"

  defp unique_component(prefix) do
    "#{prefix}_#{:erlang.unique_integer([:positive, :monotonic])}"
  end

  defp cleanup_registry_key(key) do
    key
    |> Path.dirname()
    |> then(&Path.join(Disk.storage_dir(), &1))
    |> File.rm_rf()
  end

  describe "key/4" do
    test "constructs normalized key" do
      key = RegistryDisk.key("Apple", "Parser", "v1.2", "source_archive.zip")
      assert key == "registry/swift/apple/parser/1.2.0/source_archive.zip"
    end

    test "normalizes version with leading v" do
      key = RegistryDisk.key("apple", "parser", "v1.2.3", "Package.swift")
      assert key == "registry/swift/apple/parser/1.2.3/Package.swift"
    end

    test "adds trailing zeros to incomplete version" do
      key = RegistryDisk.key("apple", "parser", "1", "source_archive.zip")
      assert key == "registry/swift/apple/parser/1.0.0/source_archive.zip"
    end

    test "handles pre-release version" do
      key = RegistryDisk.key("apple", "parser", "1.0.0-alpha.1", "source_archive.zip")
      assert key == "registry/swift/apple/parser/1.0.0-alpha+1/source_archive.zip"
    end
  end

  describe "exists?/4" do
    test "returns true when file exists" do
      scope = unique_component("scope")
      name = unique_component("name")
      version = "1.0.0"
      filename = "source_archive.zip"

      key = RegistryDisk.key(scope, name, version, filename)
      path = Disk.artifact_path(key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "test content")

      on_exit(fn -> cleanup_registry_key(key) end)

      assert RegistryDisk.exists?(scope, name, version, filename) == true
    end

    test "returns false when file doesn't exist" do
      assert RegistryDisk.exists?("nonexistent", "package", "1.0.0", "file.zip") == false
    end
  end

  describe "put/5" do
    test "writes binary data to disk" do
      scope = unique_component("scope")
      name = unique_component("name")
      version = "1.0.0"
      filename = "source_archive.zip"
      data = "test artifact data"

      assert RegistryDisk.put(scope, name, version, filename, data) == :ok

      key = RegistryDisk.key(scope, name, version, filename)
      path = Disk.artifact_path(key)

      on_exit(fn -> cleanup_registry_key(key) end)

      assert File.exists?(path)
      assert File.read!(path) == data
    end

    test "creates parent directories if they don't exist" do
      data = "nested artifact"

      scope = unique_component("scope")
      name = unique_component("name")
      version = "2.0.0"
      filename = "file.zip"

      assert RegistryDisk.put(scope, name, version, filename, data) == :ok

      key = RegistryDisk.key(scope, name, version, filename)
      path = Disk.artifact_path(key)

      on_exit(fn -> cleanup_registry_key(key) end)

      assert File.exists?(path)
      assert File.read!(path) == data
    end

    test "handles file tuple input" do
      {:ok, tmp_path} = Briefly.create()
      File.write!(tmp_path, "file content")

      scope = unique_component("scope")
      name = unique_component("name")
      version = "1.0.0"
      filename = "source_archive.zip"

      assert RegistryDisk.put(scope, name, version, filename, {:file, tmp_path}) == :ok

      key = RegistryDisk.key(scope, name, version, filename)
      path = Disk.artifact_path(key)

      on_exit(fn -> cleanup_registry_key(key) end)

      assert File.exists?(path)
      assert File.read!(path) == "file content"
    end
  end

  describe "stat/4" do
    test "returns file stat for existing artifact" do
      scope = unique_component("scope")
      name = unique_component("name")
      version = "1.0.0"
      filename = "source_archive.zip"
      data = "test content for stat"

      key = RegistryDisk.key(scope, name, version, filename)
      path = Disk.artifact_path(key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, data)

      on_exit(fn -> cleanup_registry_key(key) end)

      assert {:ok, stat} = RegistryDisk.stat(scope, name, version, filename)
      assert %File.Stat{} = stat
      assert stat.size == byte_size(data)
      assert stat.type == :regular
    end

    test "returns error for non-existent artifact" do
      assert {:error, :enoent} = RegistryDisk.stat("nonexistent", "package", "1.0.0", "file.zip")
    end
  end

  describe "local_accel_path/4" do
    test "builds internal X-Accel-Redirect path" do
      path = RegistryDisk.local_accel_path(@test_scope, @test_name, @test_version, @test_filename)
      assert path == "/internal/local/registry/swift/apple/parser/1.0.0/source_archive.zip"
    end

    test "normalizes components in path" do
      path = RegistryDisk.local_accel_path("Apple", "Parser", "v1.2", "Package.swift")
      assert path == "/internal/local/registry/swift/apple/parser/1.2.0/Package.swift"
    end
  end
end
