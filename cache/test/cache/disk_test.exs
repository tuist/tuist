defmodule Cache.DiskTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Cache.Disk

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

  describe "shards_for_id/1" do
    test "extracts two-character shards from a hex ID" do
      assert {"AB", "CD"} = Disk.shards_for_id("ABCD1234")
      assert {"12", "34"} = Disk.shards_for_id("1234ABCD")
      assert {"FF", "EE"} = Disk.shards_for_id("FFEE0000")
    end
  end

  describe "ensure_directory/1" do
    test "creates directory and parent directories if they don't exist" do
      {:ok, dir} = Briefly.create(directory: true)
      file_path = Path.join(dir, "subdir1/subdir2/file.txt")

      assert :ok = Disk.ensure_directory(file_path)
      assert File.dir?(Path.dirname(file_path))
    end

    test "returns :ok if directory already exists" do
      {:ok, dir} = Briefly.create(directory: true)

      assert :ok = Disk.ensure_directory(Path.join(dir, "file.txt"))
    end
  end

  describe "move_file/2" do
    test "atomically moves a file from temporary path to target path" do
      {:ok, dir} = Briefly.create(directory: true)
      tmp_path = Path.join(dir, "tmp_file.txt")
      target_path = Path.join(dir, "target_file.txt")

      File.write!(tmp_path, "content")
      assert :ok = Disk.move_file(tmp_path, target_path)
      assert File.exists?(target_path)
      refute File.exists?(tmp_path)
      assert File.read!(target_path) == "content"
    end

    test "returns error if target file already exists" do
      {:ok, dir} = Briefly.create(directory: true)
      tmp_path = Path.join(dir, "tmp_file.txt")
      target_path = Path.join(dir, "target_file.txt")

      File.write!(tmp_path, "tmp_content")
      File.write!(target_path, "existing_content")

      assert {:error, :exists} = Disk.move_file(tmp_path, target_path)
      assert File.read!(target_path) == "existing_content"
    end
  end
end

defmodule Cache.DiskIntegrationTest do
  use ExUnit.Case, async: true

  alias Cache.Disk
  alias Cache.Xcode

  defp unique_account do
    "test_account_#{:erlang.unique_integer([:positive, :monotonic])}"
  end

  describe "delete_project/2" do
    test "deletes all artifacts for a project" do
      account = unique_account()
      project = "test_project"

      Xcode.Disk.put(account, project, "hash1", "content1")
      Xcode.Disk.put(account, project, "hash2", "content2")
      assert Xcode.Disk.exists?(account, project, "hash1")
      assert Xcode.Disk.exists?(account, project, "hash2")

      assert :ok = Disk.delete_project(account, project)

      refute Xcode.Disk.exists?(account, project, "hash1")
      refute Xcode.Disk.exists?(account, project, "hash2")
    end

    test "returns :ok when project directory does not exist" do
      assert :ok = Disk.delete_project("nonexistent_account", "nonexistent_project")
    end
  end

  describe "delete_project_before/3" do
    test "skips files whose mtime matches the cutoff second" do
      account = unique_account()
      project = "cutoff_project"
      artifact_key = "#{account}/#{project}/xcode/AB/CD/equal-cutoff"
      artifact_path = Disk.artifact_path(artifact_key)

      assert :ok = Disk.ensure_directory(artifact_path)
      File.write!(artifact_path, "content")

      cutoff = DateTime.truncate(DateTime.utc_now(), :second)
      unix_seconds = DateTime.to_unix(cutoff, :second)
      assert :ok = File.touch(artifact_path, unix_seconds)

      assert {:ok, 0} = Disk.delete_project_before(account, project, cutoff)
      assert File.exists?(artifact_path)
    end

    test "deletes files whose mtime is older than the cutoff second" do
      account = unique_account()
      project = "older_cutoff_project"
      artifact_key = "#{account}/#{project}/xcode/AB/CD/older-than-cutoff"
      artifact_path = Disk.artifact_path(artifact_key)

      assert :ok = Disk.ensure_directory(artifact_path)
      File.write!(artifact_path, "content")

      cutoff = DateTime.truncate(DateTime.utc_now(), :second)
      unix_seconds = DateTime.to_unix(DateTime.add(cutoff, -1, :second), :second)
      assert :ok = File.touch(artifact_path, unix_seconds)

      assert {:ok, 1} = Disk.delete_project_before(account, project, cutoff)
      refute File.exists?(artifact_path)
    end

    test "returns an error when file removal fails" do
      account = unique_account()
      project = "protected_project"
      artifact_key = "#{account}/#{project}/xcode/AB/CD/protected-artifact"
      artifact_path = Disk.artifact_path(artifact_key)
      artifact_dir = Path.dirname(artifact_path)

      assert :ok = Disk.ensure_directory(artifact_path)
      File.write!(artifact_path, "content")

      cutoff = DateTime.truncate(DateTime.utc_now(), :second)
      unix_seconds = DateTime.to_unix(DateTime.add(cutoff, -1, :second), :second)
      assert :ok = File.touch(artifact_path, unix_seconds)
      assert :ok = File.chmod(artifact_dir, 0o555)

      try do
        assert {:error, reason} = Disk.delete_project_before(account, project, cutoff)
        assert reason in [:eacces, :eperm]
      after
        assert :ok = File.chmod(artifact_dir, 0o755)
        _ = File.rm(artifact_path)
      end
    end
  end
end
