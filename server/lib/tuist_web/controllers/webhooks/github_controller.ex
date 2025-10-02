defmodule TuistWeb.Webhooks.GitHubController do
  use TuistWeb, :controller

  alias Tuist.AppBuilds
  alias Tuist.Environment
  alias Tuist.GitHubAppInstallations
  alias Tuist.Projects
  alias Tuist.QA
  alias Tuist.Repo
  alias Tuist.VCS

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
    qa_prompt = tuist_qa_prompt(comment_body)

    if qa_prompt do
      test_qa_prompt(repository["full_name"], issue_number, qa_prompt)
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
    {:ok, _} = update_github_app_installation_html_url(installation_id, html_url)

    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp handle_installation(conn, _params) do
    conn
    |> put_status(:ok)
    |> json(%{status: "ok"})
  end

  defp test_qa_prompt(repository_full_handle, issue_number, prompt) do
    case Projects.project_by_vcs_repository_full_handle(repository_full_handle, preload: :account) do
      {:error, :not_found} ->
        :ok

      {:ok, project} ->
        git_ref = "refs/pull/#{issue_number}/merge"

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
    base_prompt =
      cond do
        Environment.stag?() -> "/tuist-staging qa"
        Environment.dev?() -> "/tuist-development qa"
        Environment.can?() -> "/tuist-canary qa"
        true -> "/tuist qa"
      end

    pattern = ~r/^\s*#{Regex.escape(base_prompt)}\s*(.*)$/im

    case Regex.run(pattern, body) do
      [_, prompt] ->
        String.trim(prompt)

      _ ->
        nil
    end
  end

  defp delete_github_app_installation(installation_id) do
    {:ok, github_app_installation} = GitHubAppInstallations.get_by_installation_id(installation_id)
    GitHubAppInstallations.delete(github_app_installation)
  end

  defp update_github_app_installation_html_url(installation_id, html_url) do
    {:ok, github_app_installation} = GitHubAppInstallations.get_by_installation_id(installation_id)
    GitHubAppInstallations.update(github_app_installation, %{html_url: html_url})
  end
end
