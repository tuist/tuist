defmodule Tuist.Bazel.Workers.ProcessTestInvocationWorkerTest do
  use ExUnit.Case, async: true
  use Mimic
  use Oban.Testing, repo: Tuist.Repo

  alias Tuist.Bazel.Workers.ProcessTestInvocationWorker

  setup :verify_on_exit!

  test "waits until the invocation completion marker arrives" do
    invocation = %{
      state: "collecting",
      updated_at: DateTime.utc_now(),
      test_run_id: UUIDv7.generate()
    }

    expect(Tuist.Bazel, :get_test_invocation, fn 123, "invocation-1" -> invocation end)

    assert {:snooze, 15} = perform_job(ProcessTestInvocationWorker, job_args())
  end

  test "waits for the completed Build Event Protocol invocation" do
    invocation = test_invocation()

    expect(Tuist.Bazel, :get_test_invocation, fn 123, "invocation-1" -> invocation end)
    expect(Tuist.Projects, :get_project_by_id, fn 123 -> %{id: 123} end)
    expect(Tuist.Bazel, :get_invocation, fn 123, "invocation-1" -> {:error, :not_found} end)

    assert {:snooze, 15} = perform_job(ProcessTestInvocationWorker, job_args())
  end

  test "processes all results as one run and stores ordered sanitized logs" do
    invocation = test_invocation()
    project = %{id: 123}

    bazel_invocation = %{
      invocation_id: "invocation-1",
      target_patterns: ["//..."],
      duration_ms: 400,
      exit_code: 0
    }

    results = [
      %{
        id: UUIDv7.generate(),
        invocation_id: "invocation-1",
        target_label: "//B:Tests",
        sequence_number: 20,
        started_at: ~U[2026-09-04 12:00:02Z],
        log_content: "Authorization: Bearer second-secret"
      },
      %{
        id: UUIDv7.generate(),
        invocation_id: "invocation-1",
        target_label: "//A:Tests",
        sequence_number: 10,
        started_at: ~U[2026-09-04 12:00:01Z],
        log_content: "--token first-secret"
      }
    ]

    summaries = [%{target_label: "//A:Tests", status: "success", duration_ms: 100}]

    expect(Tuist.Bazel, :get_test_invocation, fn 123, "invocation-1" -> invocation end)
    expect(Tuist.Projects, :get_project_by_id, fn 123 -> project end)
    expect(Tuist.Bazel, :get_invocation, fn 123, "invocation-1" -> {:ok, bazel_invocation} end)
    expect(Tuist.Bazel, :list_test_results, fn 123, "invocation-1" -> results end)
    expect(Tuist.Bazel, :list_test_summaries, fn 123, "invocation-1" -> summaries end)

    expect(Tuist.Bazel, :ingest_test_report, fn ^project, invocation_with_id, ^results, ^summaries ->
      assert invocation_with_id.test_run_id == invocation.test_run_id
      {:ok, %{id: invocation.test_run_id}}
    end)

    expect(Tuist.Bazel, :create_invocation_logs, fn logs ->
      assert Enum.map(logs, & &1.sequence_number) == [10, 20]
      assert Enum.map(logs, & &1.id) == Enum.map(Enum.reverse(results), & &1.id)
      assert Enum.at(logs, 0).message == "[Bazel test log for //A:Tests]\n--token <REDACTED>"
      assert Enum.at(logs, 1).message == "[Bazel test log for //B:Tests]\nAuthorization: <REDACTED>"
      {2, nil}
    end)

    expect(Tuist.Bazel, :mark_test_invocation_processed, fn ^invocation -> {:ok, invocation} end)
    expect(Tuist.Bazel, :delete_test_results, fn 123, "invocation-1" -> {2, nil} end)
    expect(Tuist.Bazel, :delete_test_summaries, fn 123, "invocation-1" -> {1, nil} end)

    assert :ok = perform_job(ProcessTestInvocationWorker, job_args())
  end

  defp job_args do
    %{"project_id" => 123, "invocation_id" => "invocation-1"}
  end

  defp test_invocation do
    %{
      state: "pending",
      updated_at: DateTime.add(DateTime.utc_now(), -16, :second),
      test_run_id: UUIDv7.generate()
    }
  end
end
