defmodule TuistWeb.Webhooks.GitHubController do
  use TuistWeb, :controller

  alias Tuist.AppBuilds
  alias Tuist.Environment
  alias Tuist.Projects
  alias Tuist.QA
  alias Tuist.Repo
  alias Tuist.VCS

  require Logger

  def handle(conn, params) do
    event_type = conn |> get_req_header("x-github-event") |> List.first()

    case event_type do
      "issue_comment" ->
        handle_issue_comment(conn, params)

      "installation" ->
        handle_installation(conn, params)

      _ ->
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
