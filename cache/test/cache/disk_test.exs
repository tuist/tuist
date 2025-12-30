defmodule Cache.DiskTest do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.CacheArtifacts
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
    |> stub(:cas_put, fn account_handle, project_handle, id, data ->
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
    |> stub(:cas_exists?, fn account_handle, project_handle, id ->
      key = "#{account_handle}/#{project_handle}/cas/#{id}"
      test_storage_dir |> Path.join(key) |> File.exists?()
    end)
    |> stub(:cas_get_local_path, fn account_handle, project_handle, id ->
      key = "#{account_handle}/#{project_handle}/cas/#{id}"
      path = Path.join(test_storage_dir, key)

      if File.exists?(path) do
        {:ok, path}
      else
        {:error, :not_found}
      end
    end)
    |> stub(:cas_stat, fn account_handle, project_handle, id ->
      key = "#{account_handle}/#{project_handle}/cas/#{id}"
      path = Path.join(test_storage_dir, key)
      File.stat(path)
    end)

    stub(CacheArtifacts, :track_artifact_access, fn _key -> :ok end)
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

  describe "cas_exists?/3" do
    test "returns true when file exists" do
      path = Disk.artifact_path(@test_key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "test content")

      assert Disk.cas_exists?(@test_account, @test_project, @test_id) == true
    end

    test "returns false when file doesn't exist" do
      assert Disk.cas_exists?("nonexistent", "project", "id") == false
    end
  end

  describe "cas_put/4" do
    test "writes data to disk successfully" do
      data = "test artifact data"

      assert Disk.cas_put(@test_account, @test_project, @test_id, data) == :ok

      path = Disk.artifact_path(@test_key)
      assert File.exists?(path)
      assert File.read!(path) == data
    end

    test "creates parent directories if they don't exist" do
      data = "nested artifact"

      assert Disk.cas_put("account", "project", "deeply/nested/artifact", data) == :ok

      path = Disk.artifact_path("account/project/cas/deeply/nested/artifact")
      assert File.exists?(path)
      assert File.read!(path) == data
    end

    test "overwrites existing file" do
      path = Disk.artifact_path(@test_key)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "old content")

      new_data = "new content"
      assert Disk.cas_put(@test_account, @test_project, @test_id, new_data) == :ok

      assert File.read!(path) == new_data
    end

    test "handles binary data" do
      binary_data = <<1, 2, 3, 4, 5, 255, 0, 128>>

      assert Disk.cas_put(@test_account, @test_project, @test_id, binary_data) == :ok

      path = Disk.artifact_path(@test_key)
      assert File.read!(path) == binary_data
    end
  end

  describe "cas_get_local_path/3" do
    test "returns path when file exists" do
      data = "test content"
      assert Disk.cas_put(@test_account, @test_project, @test_id, data) == :ok

      result = Disk.cas_get_local_path(@test_account, @test_project, @test_id)
      assert {:ok, path} = result
      assert path == Disk.artifact_path(@test_key)
      assert File.read!(path) == data
    end

    test "returns error when file doesn't exist" do
      result = Disk.cas_get_local_path("nonexistent", "project", "id")
      assert result == {:error, :not_found}
    end
  end

  describe "cas_stat/3" do
    test "returns file stat for existing artifact" do
      data = "test content for stat"
      assert Disk.cas_put(@test_account, @test_project, @test_id, data) == :ok

      assert {:ok, stat} = Disk.cas_stat(@test_account, @test_project, @test_id)
      assert %File.Stat{} = stat
      assert stat.size == byte_size(data)
      assert stat.type == :regular
    end

    test "returns error for non-existent artifact" do
      assert {:error, :enoent} = Disk.cas_stat("nonexistent", "project", "id")
    end
  end

  describe "cas_local_accel_path/3" do
    test "builds internal X-Accel-Redirect path with sharded structure" do
      path = Disk.cas_local_accel_path(@test_account, @test_project, @test_id)
      assert path == "/internal/local/#{@test_account}/#{@test_project}/cas/ab/c1/#{@test_id}"
    end

    test "builds internal path for nested id with sharded structure" do
      nested_id = "deeply/nested/artifact"
      path = Disk.cas_local_accel_path(@test_account, @test_project, nested_id)
      assert path == "/internal/local/#{@test_account}/#{@test_project}/cas/de/ep/#{nested_id}"
    end
  end

  describe "integration test" do
    test "cas_put and cas_exists? roundtrip" do
      original_data = "This is test artifact content for roundtrip testing"

      assert Disk.cas_put(@test_account, @test_project, @test_id, original_data) == :ok
      assert Disk.cas_exists?(@test_account, @test_project, @test_id) == true
    end
  end

  describe "usage/1" do
    test "returns disk usage stats for an existing directory" do
      {:ok, dir} = Briefly.create(directory: true)

      assert {:ok, stats} = Disk.usage(dir)
      assert stats.total_bytes > 0
      assert stats.used_bytes >= 0
      assert stats.available_bytes >= 0
      assert stats.percent_used >= 0.0
    end

    test "returns error when df fails for missing path" do
      missing_path = Path.join(System.tmp_dir!(), "nonexistent-#{System.unique_integer([:positive])}")

      log =
        capture_log(fn ->
          assert {:error, :df_failed} = Disk.usage(missing_path)
        end)

      assert log =~ "df exited with 1"
    end
  end
end

defmodule Cache.DiskIntegrationTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Cache.Disk

  defp unique_hash(prefix) do
    "#{prefix}#{:erlang.unique_integer([:positive, :monotonic])}"
  end

  defp unique_account do
    "test_account_#{:erlang.unique_integer([:positive, :monotonic])}"
  end

  defp dest_path_for(account, project, category, hash, name) do
    Disk.artifact_path(Disk.module_key(account, project, category, hash, name))
  end

  setup do
    on_exit(fn ->
      File.rm_rf!(Disk.storage_dir())
      File.mkdir_p!(Disk.storage_dir())
    end)

    :ok
  end

  describe "module_put_from_parts/6" do
    test "assembles multiple parts into a single file" do
      {:ok, part1} = Briefly.create()
      {:ok, part2} = Briefly.create()
      {:ok, part3} = Briefly.create()

      File.write!(part1, "PART1-")
      File.write!(part2, "PART2-")
      File.write!(part3, "PART3")

      account = unique_account()
      hash = unique_hash("abcd")
      assert :ok = Disk.module_put_from_parts(account, "project", "builds", hash, "test.zip", [part1, part2, part3])

      dest_path = dest_path_for(account, "project", "builds", hash, "test.zip")
      assert File.exists?(dest_path)
      assert File.read!(dest_path) == "PART1-PART2-PART3"
    end

    test "assembles single part" do
      {:ok, part1} = Briefly.create()
      File.write!(part1, "SINGLE_PART_CONTENT")

      account = unique_account()
      hash = unique_hash("efgh")
      assert :ok = Disk.module_put_from_parts(account, "project", "builds", hash, "single.zip", [part1])

      dest_path = dest_path_for(account, "project", "builds", hash, "single.zip")
      assert File.exists?(dest_path)
      assert File.read!(dest_path) == "SINGLE_PART_CONTENT"
    end

    test "handles binary content correctly" do
      {:ok, part1} = Briefly.create()
      {:ok, part2} = Briefly.create()

      binary1 = <<0, 1, 2, 255, 128>>
      binary2 = <<64, 32, 16, 8, 4>>

      File.write!(part1, binary1)
      File.write!(part2, binary2)

      account = unique_account()
      hash = unique_hash("ijkl")
      assert :ok = Disk.module_put_from_parts(account, "project", "builds", hash, "binary.zip", [part1, part2])

      dest_path = dest_path_for(account, "project", "builds", hash, "binary.zip")
      assert File.read!(dest_path) == binary1 <> binary2
    end

    test "returns error when destination already exists" do
      account = unique_account()
      hash = unique_hash("mnop")
      dest_path = dest_path_for(account, "project", "builds", hash, "existing.zip")
      File.mkdir_p!(Path.dirname(dest_path))
      File.write!(dest_path, "existing content")

      {:ok, part1} = Briefly.create()
      File.write!(part1, "new content")

      assert {:error, :exists} = Disk.module_put_from_parts(account, "project", "builds", hash, "existing.zip", [part1])

      assert File.read!(dest_path) == "existing content"
    end

    test "returns error when part file doesn't exist" do
      account = unique_account()
      hash = unique_hash("qrst")
      dest_path = dest_path_for(account, "project", "builds", hash, "missing.zip")

      log =
        capture_log(fn ->
          assert {:error, :enoent} =
                   Disk.module_put_from_parts(account, "project", "builds", hash, "missing.zip", ["/nonexistent/part"])
        end)

      assert log =~ "Failed to assemble artifact to #{dest_path}"
    end

    test "creates parent directories if they don't exist" do
      {:ok, part1} = Briefly.create()
      File.write!(part1, "content")

      account = unique_account()
      hash = unique_hash("uvwx")
      assert :ok = Disk.module_put_from_parts(account, "project", "tests", hash, "new.zip", [part1])

      dest_path = dest_path_for(account, "project", "tests", hash, "new.zip")
      assert File.exists?(dest_path)
    end
  end
end
