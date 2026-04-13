defmodule TuistWeb.Webhooks.GitHubController do
  use TuistWeb, :controller

  alias Tuist.Runners
  alias Tuist.VCS

  require Logger

  def handle(conn, params) do
    event_type = conn |> get_req_header("x-github-event") |> List.first()

    case event_type do
      "installation" ->
        handle_installation(conn, params)

      "check_run" ->
        handle_check_run(conn, params)

      "workflow_job" ->
        handle_workflow_job(conn, params)

      _ ->
        conn
        |> put_status(:ok)
        |> json(%{status: "ok"})
    end
  end

  defp handle_installation(conn, %{"action" => "deleted", "installation" => %{"id" => installation_id}}) do
    {:ok, _} = delete_github_app_installation(installation_id)

    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp handle_installation(conn, %{
         "action" => "created",
         "installation" => %{"id" => installation_id, "html_url" => html_url}
       }) do
    case update_github_app_installation_html_url_with_retry(installation_id, html_url) do
      {:ok, _} ->
        conn
        |> put_status(:ok)
        |> json(%{status: "ok"})

      {:error, :not_found_after_retries} ->
        # After retries, the installation still doesn't exist. This indicates a broken user flow:
        # 1. The setup callback failed or was never called
        # 2. The user closed the browser before completing setup
        # 3. Network issues prevented the redirect
        # This means the installation exists in GitHub but not in our database,
        # creating an orphaned installation that requires manual reconciliation.
        Logger.error(
          "GitHub installation.created webhook for installation_id=#{installation_id} but installation not found after retries. Setup callback may have failed. Manual intervention may be required."
        )

        conn
        |> put_status(:ok)
        |> json(%{status: "ok"})
    end
  end

  defp handle_installation(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp handle_check_run(conn, %{
         "action" => "requested_action",
         "check_run" => %{"id" => check_run_id, "name" => "tuist/bundle-size"},
         "requested_action" => %{"identifier" => "accept_bundle_size"},
         "installation" => %{"id" => installation_id},
         "repository" => %{"full_name" => repository_full_name}
       }) do
    installation_id = to_string(installation_id)

    with {:ok, _installation} <- VCS.get_github_app_installation_by_installation_id(installation_id) do
      VCS.update_check_run(%{
        repository_full_handle: repository_full_name,
        check_run_id: check_run_id,
        installation_id: installation_id,
        conclusion: "success",
        output: %{
          title: "Bundle size increase accepted",
          summary: "The bundle size increase was manually accepted."
        }
      })
    end

    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp handle_check_run(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp handle_workflow_job(conn, %{
         "action" => "queued",
         "workflow_job" => workflow_job,
         "installation" => %{"id" => installation_id},
         "repository" => %{"full_name" => repository_full_name}
       }) do
    labels = Map.get(workflow_job, "labels", [])
    github_job_id = workflow_job["id"]
    github_run_id = workflow_job["run_id"]

    with {:ok, config} <- Runners.get_runner_configuration_by_installation_id(installation_id),
         true <- Runners.labels_match?(labels, config.label_prefix),
         {:error, :not_found} <- Runners.get_runner_job_by_github_id(github_job_id) do
      {:ok, job} =
        Runners.create_runner_job(%{
          runner_configuration_id: config.id,
          account_id: config.account_id,
          github_workflow_job_id: github_job_id,
          github_run_id: github_run_id,
          github_repository_full_name: repository_full_name,
          labels: labels,
          queued_at: DateTime.utc_now()
        })

      %{runner_job_id: job.id}
      |> Tuist.Runners.Workers.ProvisionRunnerWorker.new()
      |> Oban.insert()
    end

    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp handle_workflow_job(conn, %{"action" => "in_progress", "workflow_job" => %{"id" => github_job_id}}) do
    with {:ok, job} <- Runners.get_runner_job_by_github_id(github_job_id) do
      Runners.update_runner_job(job, %{
        status: :in_progress,
        started_at: DateTime.utc_now()
      })
    end

    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp handle_workflow_job(conn, %{
         "action" => "completed",
         "workflow_job" => %{"id" => github_job_id, "conclusion" => conclusion}
       }) do
    with {:ok, job} <- Runners.get_runner_job_by_github_id(github_job_id) do
      {:ok, job} =
        Runners.update_runner_job(job, %{
          status: :completed,
          conclusion: conclusion,
          completed_at: DateTime.utc_now()
        })

      if job.orchard_vm_name do
        %{runner_job_id: job.id}
        |> Tuist.Runners.Workers.CleanupRunnerWorker.new()
        |> Oban.insert()
      end
    end

    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp handle_workflow_job(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp delete_github_app_installation(installation_id) do
    case VCS.get_github_app_installation_by_installation_id(installation_id) do
      {:ok, github_app_installation} ->
        VCS.delete_github_app_installation(github_app_installation)

      {:error, :not_found} ->
        {:ok, :already_deleted}
    end
  end

  defp update_github_app_installation_html_url(installation_id, html_url) do
    case VCS.get_github_app_installation_by_installation_id(installation_id) do
      {:ok, github_app_installation} ->
        VCS.update_github_app_installation(github_app_installation, %{html_url: html_url})

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp update_github_app_installation_html_url_with_retry(installation_id, html_url, attempt \\ 1) do
    max_attempts = 3
    retry_delay_ms = 1000

    case update_github_app_installation_html_url(installation_id, html_url) do
      {:ok, result} ->
        {:ok, result}

      {:error, :not_found} when attempt < max_attempts ->
        Logger.info(
          "GitHub installation not found for installation_id=#{installation_id}, attempt #{attempt}/#{max_attempts}. Retrying in #{retry_delay_ms}ms..."
        )

        Process.sleep(retry_delay_ms)
        update_github_app_installation_html_url_with_retry(installation_id, html_url, attempt + 1)

      {:error, :not_found} ->
        {:error, :not_found_after_retries}
    end
  end
end
