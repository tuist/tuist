defmodule Cache.CleanProjectWorkerTest do
  use ExUnit.Case, async: true
  use Mimic

  import ExUnit.CaptureLog

  alias Cache.CleanProjectWorker
  alias Cache.Disk
  alias Cache.S3

  describe "perform/1" do
    test "cleans disk and S3 artifacts" do
      account_handle = "test_account"
      project_handle = "test_project"

      expect(Disk, :delete_project, fn ^account_handle, ^project_handle -> :ok end)

      expect(S3, :delete_all_with_prefix, fn "test_account/test_project/" ->
        {:ok, 5}
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      capture_log(fn ->
        assert :ok = CleanProjectWorker.perform(job)
      end)
    end

    test "logs errors but returns :ok when disk deletion fails" do
      account_handle = "test_account"
      project_handle = "test_project"

      expect(Disk, :delete_project, fn ^account_handle, ^project_handle -> {:error, :eacces} end)

      expect(S3, :delete_all_with_prefix, fn "test_account/test_project/" ->
        {:ok, 0}
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      log =
        capture_log(fn ->
          assert :ok = CleanProjectWorker.perform(job)
        end)

      assert log =~ "Failed to clean disk cache"
    end

    test "logs errors but returns :ok when S3 deletion fails" do
      account_handle = "test_account"
      project_handle = "test_project"

      expect(Disk, :delete_project, fn ^account_handle, ^project_handle -> :ok end)

      expect(S3, :delete_all_with_prefix, fn "test_account/test_project/" ->
        {:error, :timeout}
      end)

      job = %Oban.Job{args: %{"account_handle" => account_handle, "project_handle" => project_handle}}

      log =
        capture_log(fn ->
          assert :ok = CleanProjectWorker.perform(job)
        end)

      assert log =~ "Failed to clean S3 objects"
    end
  end
end
