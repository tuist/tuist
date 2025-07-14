defmodule TuistWeb.Webhooks.GitHubController do
  use TuistWeb, :controller

  import Ecto.Query

  alias Tuist.AppBuilds
  alias Tuist.AppBuilds.Preview
  alias Tuist.Projects
  alias Tuist.Repo

  require Logger

  def webhook(conn, params) do
    event_type = conn |> get_req_header("x-github-event") |> List.first()

    case event_type do
      "issue_comment" ->
        handle_issue_comment(conn, params)

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
           "comment" => comment,
           "repository" => repository,
           "issue" => %{"number" => issue_number, "pull_request" => _pull_request}
         } = _params
       ) do
    body = comment["body"] || ""

    case extract_tuist_qa_command(body) do
      {:ok, instructions} ->
        repository_slug = repository["full_name"]

        Logger.info("Received /tuist qa command for repo: #{repository_slug}, number: #{issue_number}")
        Logger.info("Instructions: #{instructions}")

        # Find project by repository slug
        case Projects.get_project_by_vcs_repository_full_handle(repository_slug) do
          nil ->
            Logger.error("No project found for repository: #{repository_slug}")

          project ->
            # Get latest previews with distinct bundle identifiers
            previews = latest_previews(%{git_ref: "refs/pull/#{issue_number}/merge", project: project})

            Logger.info("Found #{length(previews)} previews for project #{project.name}")

            for preview <- previews do
              Tuist.QA.run_qa_tests(%{
                preview_url: url(~p"/#{project.account.name}/#{project.name}/previews/#{preview.id}"),
                preview: preview
              })
            end

            # TODO: Pass previews and branch information to QA tests
            # opts = [
            #   tenant_id: "default-tenant",
            #   actor_id: "pr-review-#{comment["id"]}",
            #   instructions: instructions,
            #   project: project,
            #   previews: previews,
            #   git_ref: git_ref
            # ]

            # # Run QA tests asynchronously
            # Task.start(fn ->
            #   case Tuist.QA.run_qa_tests(opts) do
            #     :ok ->
            #       Logger.info("QA tests completed successfully")

            #     {:error, reason} ->
            #       Logger.error("QA tests failed: #{inspect(reason)}")
            #   end
            # end)
        end

      :error ->
        :ok
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

  defp latest_previews(%{git_ref: git_ref, project: project}) do
    from(p in Preview)
    |> where([p], p.project_id == ^project.id and p.git_ref == ^git_ref)
    |> order_by([p], desc: p.inserted_at)
    |> distinct([p], p.display_name)
    |> Repo.all()
    |> Repo.preload(:app_builds)
  end

  defp extract_tuist_qa_command(body) do
    case Regex.run(~r/\/tuist qa\s*(.*)$/im, body) do
      [_, instructions] ->
        instructions = String.trim(instructions)

        if instructions == "" do
          {:ok, "You are a QA agent. Test the application thoroughly and report any issues."}
        else
          {:ok, instructions}
        end

      _ ->
        :error
    end
  end
end
