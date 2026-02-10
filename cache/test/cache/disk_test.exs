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
end

defmodule Cache.DiskIntegrationTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Cache.Disk

  describe "delete_project/2" do
    test "deletes all artifacts for a project" do
      account = unique_account()
      project = "test_project"

      Disk.xcode_cas_put(account, project, "hash1", "content1")
      Disk.xcode_cas_put(account, project, "hash2", "content2")
      assert Disk.xcode_cas_exists?(account, project, "hash1")
      assert Disk.xcode_cas_exists?(account, project, "hash2")

      assert :ok = Disk.delete_project(account, project)

      refute Disk.xcode_cas_exists?(account, project, "hash1")
      refute Disk.xcode_cas_exists?(account, project, "hash2")
    end

    test "returns :ok when project directory does not exist" do
      assert :ok = Disk.delete_project("nonexistent_account", "nonexistent_project")
    end
  end
end
