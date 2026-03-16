defmodule FlakyFixRunnerWeb.WebhookController do
  use FlakyFixRunnerWeb, :controller

  alias FlakyFixRunner.FlakyFix

  require Logger

  def fix_flaky_test(
        conn,
        %{
          "job_id" => job_id,
          "test_case_id" => test_case_id,
          "repository_full_handle" => repository_full_handle,
          "callback_url" => _callback_url
        } = params
      ) do
    Logger.info(
      "Accepted flaky fix job #{job_id} for #{repository_full_handle} test case #{test_case_id}"
    )

    Task.Supervisor.start_child(FlakyFixRunner.TaskSupervisor, fn ->
      FlakyFix.process(params)
    end)

    conn
    |> put_status(:accepted)
    |> json(%{job_id: job_id, status: "accepted"})
  end

  def fix_flaky_test(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "Invalid payload"})
  end
end
