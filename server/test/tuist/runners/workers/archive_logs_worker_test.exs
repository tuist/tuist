defmodule Tuist.Runners.Workers.ArchiveLogsWorkerTest do
  use TuistTestSupport.Cases.DataCase, async: false

  import Mimic
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Runners.JobLogs
  alias Tuist.Runners.Jobs
  alias Tuist.Runners.Workers.ArchiveLogsWorker
  alias Tuist.Storage

  setup :verify_on_exit!

  defp enqueue(account, workflow_job_id) do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "acme/cli",
        workflow_run_id: workflow_job_id * 10,
        run_attempt: 1,
        job_name: "build",
        head_branch: "main",
        head_sha: "deadbeef"
      })
  end

  describe "perform/1" do
    test "gzips the full log, uploads it to S3, and stamps log_archived_at" do
      account = account_fixture()
      enqueue(account, 9_900_001)

      :ok =
        JobLogs.append([
          %{
            workflow_job_id: 9_900_001,
            account_id: account.id,
            line_number: 1,
            ts: ~U[2026-05-28 12:00:00.000000Z],
            message: "first"
          },
          %{
            workflow_job_id: 9_900_001,
            account_id: account.id,
            line_number: 2,
            ts: ~U[2026-05-28 12:00:01.000000Z],
            message: "second"
          }
        ])

      expected_key = "runners/#{account.id}/9900001/runner.log.gz"

      expect(Storage, :upload, fn source, ^expected_key, %{id: account_id} ->
        assert account_id == account.id

        gzipped =
          source
          |> Enum.to_list()
          |> IO.iodata_to_binary()

        decompressed = :zlib.gunzip(gzipped)
        assert decompressed =~ "first"
        assert decompressed =~ "second"
        :ok
      end)

      assert :ok =
               ArchiveLogsWorker.perform(%Oban.Job{
                 args: %{"workflow_job_id" => 9_900_001, "account_id" => account.id}
               })

      assert {:ok, %{log_archived_at: %DateTime{}}} = Jobs.get_for_account(account.id, 9_900_001)
    end

    test "streams a multi-megabyte log without holding the whole thing in memory" do
      # Smoke-tests the streaming path. The original in-memory design
      # built the full plain-text *and* the gzip simultaneously; the
      # streaming path keeps only the in-flight CH batch and one S3
      # multipart chunk resident. We don't assert RSS, but the test
      # exercises a payload large enough to fan through several batches
      # (`@batch_size` is 2_000) and across the 5 MiB multipart cap.
      account = account_fixture()
      enqueue(account, 9_900_010)

      # Each line is ~1 KiB; 8_000 lines is ~8 MiB of plain text — far
      # more than the previous in-memory approach was comfortable with.
      payload = String.duplicate("payload-", 128)

      lines =
        Enum.map(1..8_000, fn n ->
          %{
            workflow_job_id: 9_900_010,
            account_id: account.id,
            line_number: n,
            ts: DateTime.add(~U[2026-05-28 12:00:00.000000Z], n, :millisecond),
            message: "#{n}-#{payload}"
          }
        end)

      :ok = JobLogs.append(lines)

      expect(Storage, :upload, fn source, key, _account ->
        assert key == "runners/#{account.id}/9900010/runner.log.gz"

        gzipped =
          source
          |> Enum.to_list()
          |> IO.iodata_to_binary()

        # Round-trip the stream to confirm it's a valid gzip and the
        # last line made it through (i.e. nothing was truncated by an
        # over-eager buffer cap).
        decompressed = :zlib.gunzip(gzipped)
        assert decompressed =~ "8000-#{payload}"
        :ok
      end)

      assert :ok =
               ArchiveLogsWorker.perform(%Oban.Job{
                 args: %{"workflow_job_id" => 9_900_010, "account_id" => account.id}
               })
    end

    test "is a no-op when the job has no captured log lines" do
      account = account_fixture()
      enqueue(account, 9_900_002)

      reject(&Storage.upload/3)

      assert :ok =
               ArchiveLogsWorker.perform(%Oban.Job{
                 args: %{"workflow_job_id" => 9_900_002, "account_id" => account.id}
               })

      assert {:ok, %{log_archived_at: nil}} = Jobs.get_for_account(account.id, 9_900_002)
    end

    test "is a no-op when the account no longer exists" do
      reject(&Storage.upload/3)

      assert :ok =
               ArchiveLogsWorker.perform(%Oban.Job{
                 args: %{"workflow_job_id" => 9_900_003, "account_id" => -1}
               })
    end

    test "broadcasts :runner_job_log_archived after stamping log_archived_at" do
      account = account_fixture()
      enqueue(account, 9_900_020)

      :ok =
        JobLogs.append([
          %{
            workflow_job_id: 9_900_020,
            account_id: account.id,
            line_number: 1,
            ts: ~U[2026-05-28 12:00:00.000000Z],
            message: "hi"
          }
        ])

      :ok = Tuist.PubSub.subscribe(JobLogs.topic(9_900_020))
      stub(Storage, :upload, fn _, _, _ -> :ok end)

      assert :ok =
               ArchiveLogsWorker.perform(%Oban.Job{
                 args: %{"workflow_job_id" => 9_900_020, "account_id" => account.id}
               })

      assert_receive {:runner_job_log_archived, %{workflow_job_id: 9_900_020, archived_at: %DateTime{}}},
                     1_000
    end

    test "does not broadcast when the job has no captured log lines" do
      account = account_fixture()
      enqueue(account, 9_900_021)

      :ok = Tuist.PubSub.subscribe(JobLogs.topic(9_900_021))
      reject(&Storage.upload/3)

      assert :ok =
               ArchiveLogsWorker.perform(%Oban.Job{
                 args: %{"workflow_job_id" => 9_900_021, "account_id" => account.id}
               })

      refute_receive {:runner_job_log_archived, _}, 100
    end
  end
end
