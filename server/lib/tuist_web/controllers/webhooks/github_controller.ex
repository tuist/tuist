defmodule TuistWeb.Webhooks.GitHubController do
  use TuistWeb, :controller

  alias Tuist.AppBuilds
  alias Tuist.Environment
  alias Tuist.Projects
  alias Tuist.QA
  alias Tuist.Repo
  alias Tuist.Runners
  alias Tuist.VCS

  require Logger

  def handle(conn, params) do
    event_type = conn |> get_req_header("x-github-event") |> List.first()
    delivery_id = conn |> get_req_header("x-github-delivery") |> List.first()

    Logger.info(
      "GitHub webhook received: event_type=#{event_type} delivery_id=#{delivery_id} params_keys=#{inspect(Map.keys(params))}"
    )

    Logger.info("GitHub webhook full params: #{inspect(params, pretty: true)}")

    case event_type do
      "issue_comment" ->
        Logger.info("Routing to issue_comment handler: delivery_id=#{delivery_id}")
        handle_issue_comment(conn, params)

      "installation" ->
        Logger.info("Routing to installation handler: delivery_id=#{delivery_id}")
        handle_installation(conn, params)

      "workflow_job" ->
        Logger.info("Routing to workflow_job handler: delivery_id=#{delivery_id}")
        handle_workflow_job(conn, params)

      _ ->
        Logger.info("Unhandled event type, returning ok: event_type=#{event_type} delivery_id=#{delivery_id}")

        conn
        |> put_status(:ok)
        |> json(%{status: "ok"})
    end
  end

  defp handle_issue_comment(
         conn,
         %{
           "action" => "created",
           "comment" => %{"body" => comment_body},
           "repository" => repository,
           "issue" => %{"number" => issue_number, "pull_request" => _pull_request}
         } = _params
       ) do
    qa_result = tuist_qa_prompt(comment_body)

    if qa_result do
      repository_full_name = repository["full_name"]
      git_ref = "refs/pull/#{issue_number}/merge"

      case get_project_for_qa(qa_result, repository_full_name) do
        {:ok, project} ->
          {_, prompt} = qa_result
          test_qa_prompt(project, prompt, git_ref, repository_full_name)

        {:error, :not_found} ->
          case qa_result do
            {project_name, _} when not is_nil(project_name) ->
              VCS.create_comment(%{
                repository_full_handle: repository_full_name,
                git_ref: git_ref,
                body: "Project '#{project_name}' is not connected to this repository.",
                project: nil
              })

            _ ->
              :ok
          end

        {:error, {:multiple_projects, projects}} ->
          project_handles = Enum.map_join(projects, ", ", & &1.name)

          VCS.create_comment(%{
            repository_full_handle: repository_full_name,
            git_ref: git_ref,
            body:
              "Multiple Tuist projects are connected to this repository. Please specify the project handle: `/tuist <project-handle> qa <your-prompt>`\n\nAvailable projects: #{project_handles}",
            project: List.first(projects)
          })
      end
    end

    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp handle_issue_comment(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
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

  defp handle_workflow_job(
         conn,
         %{
           "action" => "queued",
           "workflow_job" => workflow_job,
           "organization" => organization,
           "installation" => %{"id" => installation_id}
         } = _params
       ) do
    github_job_id = workflow_job["id"]
    labels = workflow_job["labels"] || []
    org_login = organization["login"]

    Logger.info(
      "Processing queued workflow_job: github_job_id=#{github_job_id} installation_id=#{installation_id} org_login=#{org_login} labels=#{inspect(labels)} workflow_name=#{workflow_job["workflow_name"]} run_id=#{workflow_job["run_id"]} run_attempt=#{workflow_job["run_attempt"]}"
    )

    Logger.info("Full workflow_job details: #{inspect(workflow_job, pretty: true, limit: :infinity)}")

    Logger.info("Full organization details: #{inspect(organization, pretty: true, limit: :infinity)}")

    case Runners.should_handle_job?(labels, installation_id) do
      {:ok, runner_org} ->
        Logger.info(
          "Job should be handled by runner organization: github_job_id=#{github_job_id} runner_org_id=#{runner_org.id} runner_org_account_id=#{runner_org.account_id} max_concurrent_jobs=#{runner_org.max_concurrent_jobs}"
        )

        if Runners.organization_has_capacity?(runner_org) do
          Logger.info(
            "Runner organization has capacity, creating job: github_job_id=#{github_job_id} runner_org_id=#{runner_org.id}"
          )

          case Runners.create_job_from_webhook(workflow_job, organization, runner_org) do
            {:ok, job} ->
              Logger.info(
                "Successfully created runner job: runner_job_id=#{job.id} github_job_id=#{github_job_id} org_login=#{org_login} status=#{job.status} github_repository=#{job.org}/#{job.repo} github_run_id=#{job.run_id}"
              )

              Logger.info("Full created job: #{inspect(job, pretty: true)}")

              worker = Runners.Workers.SpawnRunnerWorker.new(%{job_id: job.id})

              case Oban.insert(worker) do
                {:ok, oban_job} ->
                  Logger.info(
                    "SpawnRunnerWorker enqueued successfully: runner_job_id=#{job.id} oban_job_id=#{oban_job.id} oban_job_state=#{oban_job.state}"
                  )

                {:error, changeset} ->
                  Logger.error(
                    "Failed to enqueue SpawnRunnerWorker: runner_job_id=#{job.id} errors=#{inspect(changeset.errors)}"
                  )
              end

            {:error, changeset} ->
              Logger.error(
                "Failed to create runner job from webhook: github_job_id=#{github_job_id} installation_id=#{installation_id} org_login=#{org_login} errors=#{inspect(changeset.errors)} changeset=#{inspect(changeset, pretty: true)}"
              )
          end
        else
          current_jobs = Runners.get_organization_active_job_count(runner_org.id)

          Logger.warning(
            "Runner organization at capacity, ignoring job: runner_org_id=#{runner_org.id} github_job_id=#{github_job_id} current_jobs=#{current_jobs} max_concurrent_jobs=#{runner_org.max_concurrent_jobs}"
          )
        end

      {:ignore, reason} ->
        Logger.info(
          "Ignoring workflow_job event: github_job_id=#{github_job_id} installation_id=#{installation_id} reason=#{reason} labels=#{inspect(labels)}"
        )
    end

    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp handle_workflow_job(
         conn,
         %{"action" => "in_progress", "workflow_job" => %{"id" => github_job_id, "runner_name" => runner_name}} = params
       ) do
    Logger.info("Processing in_progress workflow_job: github_job_id=#{github_job_id} runner_name=#{runner_name}")

    Logger.info("Full in_progress webhook params: #{inspect(params, pretty: true)}")

    case Runners.get_runner_job_by_github_job_id(github_job_id) do
      nil ->
        Logger.warning(
          "Received in_progress for unknown job, ignoring: github_job_id=#{github_job_id} runner_name=#{runner_name}"
        )

      job ->
        Logger.info(
          "Found runner job for in_progress event: runner_job_id=#{job.id} github_job_id=#{github_job_id} previous_status=#{job.status} runner_name=#{runner_name}"
        )

        case Runners.update_runner_job(job, %{
               status: :running,
               started_at: DateTime.utc_now(),
               github_runner_name: runner_name
             }) do
          {:ok, updated_job} ->
            Logger.info(
              "Runner job successfully transitioned to running: runner_job_id=#{updated_job.id} github_job_id=#{github_job_id} runner_name=#{runner_name} started_at=#{updated_job.started_at}"
            )

          {:error, changeset} ->
            Logger.error(
              "Failed to update runner job to running: runner_job_id=#{job.id} github_job_id=#{github_job_id} errors=#{inspect(changeset.errors)} changeset=#{inspect(changeset, pretty: true)}"
            )
        end
    end

    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp handle_workflow_job(
         conn,
         %{"action" => "completed", "workflow_job" => %{"id" => github_job_id, "conclusion" => conclusion}} = params
       ) do
    Logger.info("Processing completed workflow_job: github_job_id=#{github_job_id} conclusion=#{conclusion}")

    Logger.info("Full completed webhook params: #{inspect(params, pretty: true)}")

    case Runners.get_runner_job_by_github_job_id(github_job_id) do
      nil ->
        Logger.warning(
          "Received completed for unknown job, ignoring: github_job_id=#{github_job_id} conclusion=#{conclusion}"
        )

      job ->
        Logger.info(
          "Found runner job for completed event: runner_job_id=#{job.id} github_job_id=#{github_job_id} previous_status=#{job.status} conclusion=#{conclusion}"
        )

        status =
          case conclusion do
            "success" -> :cleanup
            "failure" -> :failed
            "cancelled" -> :cancelled
            _ -> :cleanup
          end

        Logger.info("Mapping conclusion to status: conclusion=#{conclusion} mapped_status=#{status}")

        case Runners.update_runner_job(job, %{
               status: status,
               completed_at: DateTime.utc_now()
             }) do
          {:ok, updated_job} ->
            Logger.info(
              "Runner job successfully transitioned to completed state: runner_job_id=#{updated_job.id} github_job_id=#{github_job_id} status=#{status} completed_at=#{updated_job.completed_at}"
            )

            if status == :cleanup do
              worker = Runners.Workers.CleanupRunnerWorker.new(%{job_id: updated_job.id})

              case Oban.insert(worker) do
                {:ok, oban_job} ->
                  Logger.info(
                    "CleanupRunnerWorker enqueued successfully: runner_job_id=#{updated_job.id} oban_job_id=#{oban_job.id} oban_job_state=#{oban_job.state}"
                  )

                {:error, changeset} ->
                  Logger.error(
                    "Failed to enqueue CleanupRunnerWorker: runner_job_id=#{updated_job.id} errors=#{inspect(changeset.errors)}"
                  )
              end
            else
              Logger.info(
                "Skipping cleanup worker for non-cleanup status: runner_job_id=#{updated_job.id} status=#{status}"
              )
            end

          {:error, changeset} ->
            Logger.error(
              "Failed to update runner job to completed state: runner_job_id=#{job.id} github_job_id=#{github_job_id} target_status=#{status} errors=#{inspect(changeset.errors)} changeset=#{inspect(changeset, pretty: true)}"
            )
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

  defp get_project_for_qa(qa_result, repository_full_name) do
    case qa_result do
      {project_name, _prompt} when not is_nil(project_name) ->
        Projects.project_by_name_and_vcs_repository_full_handle(
          project_name,
          repository_full_name,
          preload: :account
        )

      {nil, _prompt} ->
        projects =
          Projects.projects_by_vcs_repository_full_handle(repository_full_name, preload: :account)

        case projects do
          [] -> {:error, :not_found}
          [project] -> {:ok, project}
          multiple -> {:error, {:multiple_projects, multiple}}
        end
    end
  end

  defp test_qa_prompt(project, prompt, git_ref, repository_full_handle) do
    if FunWithFlags.enabled?(:qa, for: project.account) do
      start_or_enqueue_qa_run(project, prompt, git_ref)
    else
      VCS.create_comment(%{
        repository_full_handle: repository_full_handle,
        git_ref: git_ref,
        body:
          "Tuist QA is currently not generally available. Contact us at contact@tuist.dev if you'd like an early preview of the feature.",
        project: project
      })
    end
  end

  defp start_or_enqueue_qa_run(project, prompt, git_ref) do
    project = Repo.preload(project, :vcs_connection)

    simulator_app_build =
      AppBuilds.latest_app_build(git_ref, project, supported_platform: :ios_simulator)

    {:ok, qa_run} =
      QA.create_qa_run(%{
        app_build_id: simulator_app_build && simulator_app_build.id,
        prompt: prompt,
        status: "pending",
        git_ref: git_ref,
        issue_comment_id: nil
      })

    {:ok, %{"id" => comment_id}} =
      post_initial_comment(
        simulator_app_build,
        project.vcs_connection && project.vcs_connection.repository_full_handle,
        git_ref,
        project,
        qa_run
      )

    {:ok, updated_qa_run} = QA.update_qa_run(qa_run, %{issue_comment_id: comment_id})

    if simulator_app_build do
      QA.enqueue_test_worker(updated_qa_run)
    end
  end

  defp post_initial_comment(simulator_app_build, repository_full_handle, git_ref, project, qa_run) do
    qa_run_url =
      "#{Environment.app_url()}/#{project.account.name}/#{project.name}/qa/#{qa_run.id}"

    body =
      if simulator_app_build do
        simulator_app_build = Repo.preload(simulator_app_build, :preview)
        preview = simulator_app_build.preview

        preview_url =
          "#{Environment.app_url()}/#{project.account.name}/#{project.name}/previews/#{preview.id}"

        "Running QA for [#{preview.display_name}](#{preview_url}). [See the live QA session](#{qa_run_url})."
      else
        "No preview found for your PR. Tuist QA will be triggered as soon as a Tuist Preview is available. Make sure to include `tuist share` as part of your CI pipeline. For more details on how to set up Previews, head over to our [documentation](https://docs.tuist.dev/en/guides/features/previews)."
      end

    VCS.create_comment(%{
      repository_full_handle: repository_full_handle,
      git_ref: git_ref,
      body: body,
      project: project
    })
  end

  defp tuist_qa_prompt(body) do
    base_command =
      cond do
        Environment.stag?() -> "/tuist-staging"
        Environment.dev?() -> "/tuist-development"
        Environment.can?() -> "/tuist-canary"
        true -> "/tuist"
      end

    # Pattern 1: /tuist <project-name> qa <prompt> (with project name)
    pattern_with_project = ~r/^\s*#{Regex.escape(base_command)}\s+(\S+)\s+qa\s+(.*)$/im

    # Pattern 2: /tuist qa <prompt> (no project name, valid in case only a single Tuist project is connected to the GitHub repository)
    pattern_without_project = ~r/^\s*#{Regex.escape(base_command)}\s+qa\s+(.*)$/im

    case Regex.run(pattern_with_project, body) do
      [_, project_name, prompt] ->
        {String.trim(project_name), String.trim(prompt)}

      _ ->
        case Regex.run(pattern_without_project, body) do
          [_, prompt] ->
            {nil, String.trim(prompt)}

          _ ->
            nil
        end
    end
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
