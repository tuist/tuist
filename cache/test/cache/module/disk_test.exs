defmodule Cache.Module.DiskTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Cache.Disk
  alias Cache.Module.Disk, as: ModuleDisk

  defp unique_hash(prefix) do
    "#{prefix}#{:erlang.unique_integer([:positive, :monotonic])}"
  end

  defp unique_account do
    "test_account_#{:erlang.unique_integer([:positive, :monotonic])}"
  end

  defp dest_path_for(account, project, category, hash, name) do
    Disk.artifact_path(ModuleDisk.key(account, project, category, hash, name))
  end

  defp cleanup_project(account_handle, project_handle) do
    Disk.delete_project(account_handle, project_handle)
    :ok
  end

  describe "put_from_parts/6" do
    test "assembles multiple parts into a single file" do
      {:ok, part1} = Briefly.create()
      {:ok, part2} = Briefly.create()
      {:ok, part3} = Briefly.create()

      File.write!(part1, "PART1-")
      File.write!(part2, "PART2-")
      File.write!(part3, "PART3")

      account = unique_account()
      on_exit(fn -> cleanup_project(account, "project") end)

      hash = unique_hash("abcd")
      assert :ok = ModuleDisk.put_from_parts(account, "project", "builds", hash, "test.zip", [part1, part2, part3])

      dest_path = dest_path_for(account, "project", "builds", hash, "test.zip")
      assert File.exists?(dest_path)
      assert File.read!(dest_path) == "PART1-PART2-PART3"
    end

    test "assembles single part" do
      {:ok, part1} = Briefly.create()
      File.write!(part1, "SINGLE_PART_CONTENT")

      account = unique_account()
      on_exit(fn -> cleanup_project(account, "project") end)

      hash = unique_hash("efgh")
      assert :ok = ModuleDisk.put_from_parts(account, "project", "builds", hash, "single.zip", [part1])

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
      on_exit(fn -> cleanup_project(account, "project") end)

      hash = unique_hash("ijkl")
      assert :ok = ModuleDisk.put_from_parts(account, "project", "builds", hash, "binary.zip", [part1, part2])

      dest_path = dest_path_for(account, "project", "builds", hash, "binary.zip")
      assert File.read!(dest_path) == binary1 <> binary2
    end

    test "returns error when destination already exists" do
      account = unique_account()
      on_exit(fn -> cleanup_project(account, "project") end)

      hash = unique_hash("mnop")
      dest_path = dest_path_for(account, "project", "builds", hash, "existing.zip")
      File.mkdir_p!(Path.dirname(dest_path))
      File.write!(dest_path, "existing content")

      {:ok, part1} = Briefly.create()
      File.write!(part1, "new content")

      assert {:error, :exists} = ModuleDisk.put_from_parts(account, "project", "builds", hash, "existing.zip", [part1])

      assert File.read!(dest_path) == "existing content"
    end

    test "returns error when part file doesn't exist" do
      account = unique_account()
      on_exit(fn -> cleanup_project(account, "project") end)

      hash = unique_hash("qrst")
      dest_path = dest_path_for(account, "project", "builds", hash, "missing.zip")

      log =
        capture_log(fn ->
          assert {:error, :enoent} =
                   ModuleDisk.put_from_parts(account, "project", "builds", hash, "missing.zip", ["/nonexistent/part"])
        end)

      assert log =~ "Failed to assemble artifact to #{dest_path}"
    end

    test "creates parent directories if they don't exist" do
      {:ok, part1} = Briefly.create()
      File.write!(part1, "content")

      account = unique_account()
      on_exit(fn -> cleanup_project(account, "project") end)

      hash = unique_hash("uvwx")
      assert :ok = ModuleDisk.put_from_parts(account, "project", "tests", hash, "new.zip", [part1])

      dest_path = dest_path_for(account, "project", "tests", hash, "new.zip")
      assert File.exists?(dest_path)
    end
  end
end
