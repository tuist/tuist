defmodule Cache.DiskTest do
  use ExUnit.Case, async: true
  use Mimic

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

    test "does not replace an artifact published after the destination was checked" do
      {:ok, dir} = Briefly.create(directory: true)
      tmp_path = Path.join(dir, "tmp_file.txt")
      target_path = Path.join(dir, "target_file.txt")
      File.write!(tmp_path, "second upload")
      File.write!(target_path, "first upload")
      # What an upload observes when it checked just before another one published.
      stub(File, :exists?, fn _path -> false end)

      assert {:error, :exists} = Disk.move_file(tmp_path, target_path)
      assert File.read!(target_path) == "first upload"
    end

    test "publishes exactly one of several uploads racing for one key" do
      {:ok, dir} = Briefly.create(directory: true)
      target_path = Path.join(dir, "target_file.txt")

      results =
        1..16
        |> Enum.map(fn index ->
          tmp_path = Path.join(dir, "upload_#{index}")
          File.write!(tmp_path, "upload #{index}")
          tmp_path
        end)
        |> Task.async_stream(&{&1, Disk.move_file(&1, target_path)}, max_concurrency: 16, ordered: false)
        |> Enum.map(fn {:ok, result} -> result end)

      assert [{winner, :ok}] = Enum.filter(results, &match?({_path, :ok}, &1))
      assert Enum.count(results, &match?({_path, {:error, :exists}}, &1)) == 15
      assert File.read!(target_path) == String.replace(Path.basename(winner), "_", " ")
    end
  end

  describe "write_new_file/2" do
    test "publishes the data without leaving a temporary file behind" do
      {:ok, dir} = Briefly.create(directory: true)
      target_path = Path.join(dir, "artifact")

      assert :ok = Disk.write_new_file(target_path, "bytes")
      assert File.read!(target_path) == "bytes"
      assert File.ls!(dir) == ["artifact"]
    end

    test "leaves an existing artifact alone without leaving a temporary file behind" do
      {:ok, dir} = Briefly.create(directory: true)
      target_path = Path.join(dir, "artifact")
      File.write!(target_path, "first upload")

      assert {:error, :exists} = Disk.write_new_file(target_path, "second upload")
      assert File.read!(target_path) == "first upload"
      assert File.ls!(dir) == ["artifact"]
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

  describe "small uploads" do
    test "do not replace an artifact another upload already published" do
      account = unique_account()
      on_exit(fn -> Disk.delete_project(account, "test_project") end)

      assert :ok = Xcode.Disk.put(account, "test_project", "hash1", "first upload")
      assert {:error, :exists} = Xcode.Disk.put(account, "test_project", "hash1", "second upload")

      path = Disk.artifact_path(Xcode.Disk.key(account, "test_project", "hash1"))
      assert File.read!(path) == "first upload"
    end
  end
end
