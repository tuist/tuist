defmodule Tuist.Tests.Workers.EnqueueFlakyFixWorker do
  @moduledoc """
  Enqueues a flaky test fix job on the external processor service.
  """
  use Oban.Worker,
    max_attempts: 3,
    unique: [keys: [:test_case_id], states: [:available, :scheduled, :executing, :retryable]]

  alias Tuist.Environment
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Tests

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id, args: %{"project_id" => project_id, "test_case_id" => test_case_id}}) do
    runner_url = Environment.flaky_fix_runner_url()
    webhook_secret = Environment.flaky_fix_runner_webhook_secret()

    cond do
      is_nil(runner_url) or runner_url == "" ->
        Logger.info("Skipping flaky fix job #{job_id}: flaky_fix_runner_url is not configured")
        :ok

      is_nil(webhook_secret) or webhook_secret == "" ->
        Logger.info("Skipping flaky fix job #{job_id}: flaky_fix_runner_webhook_secret is not configured")
        :ok

      true ->
        send_to_runner(job_id, project_id, test_case_id, runner_url, webhook_secret)
    end
  end

  defp send_to_runner(job_id, project_id, test_case_id, runner_url, webhook_secret) do
    with {:ok, test_case} <- Tests.get_test_case_by_id(test_case_id),
         %Projects.Project{} = project <- Projects.get_project_by_id(project_id) do
      project = Repo.preload(project, :vcs_connection)

      case project.vcs_connection do
        %{provider: :github, repository_full_handle: repository_full_handle} ->
          payload = %{
            job_id: job_id,
            account_handle: project.account.name,
            project_handle: project.name,
            test_case_id: test_case_id,
            test_case_url: test_case_url(project, test_case),
            repository_full_handle: repository_full_handle,
            repository_url: Projects.get_repository_url(project),
            base_branch: project.default_branch || "main",
            callback_url: Environment.app_url(path: "/webhooks/flaky-fix-runner")
          }

          post_payload(runner_url, payload, webhook_secret)

        _ ->
          Logger.info("Skipping flaky fix job #{job_id}: project #{project_id} has no GitHub VCS connection")
          :ok
      end
    else
      _ ->
        Logger.warning("Skipping flaky fix job #{job_id}: missing project or test case")
        :ok
    end
  end

  defp post_payload(runner_url, payload, webhook_secret) do
    json_body = Jason.encode!(payload)

    signature =
      :hmac
      |> :crypto.mac(:sha256, webhook_secret, json_body)
      |> Base.encode16(case: :lower)

    case Req.post("#{runner_url}/webhooks/fix-flaky-test",
           body: json_body,
           headers: [
             {"content-type", "application/json"},
             {"x-webhook-signature", signature}
           ],
           receive_timeout: 30_000
         ) do
      {:ok, %{status: status}} when status in [200, 202] ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Flaky fix runner returned #{status}: #{inspect(body)}")
        {:error, "flaky_fix_runner_error_#{status}"}

      {:error, reason} ->
        Logger.warning("Flaky fix runner request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp test_case_url(project, test_case) do
    Environment.app_url(path: "/#{project.account.name}/#{project.name}/tests/test-cases/#{test_case.id}")
  end
end
