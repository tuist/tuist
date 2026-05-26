defmodule Tuist.Automations.Actions.CreateGithubIssueAction do
  @moduledoc """
  Opens a GitHub issue on the project's connected repository for the test
  case that triggered the automation, and records an `IssueLink` so the
  `issues.closed` webhook can fan back out to subscribed automations.

  Idempotent on `(alert_id, test_case_id)`: when an open `IssueLink`
  already exists, no new issue is filed. The action only fires for
  projects with a github VCS connection; everything else is logged and
  skipped so a misconfigured project can't block other actions in the
  same chain.
  """
  alias Tuist.Automations
  alias Tuist.Environment
  alias Tuist.GitHub.Client
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Tests
  alias Tuist.VCS.GitHubAppInstallation

  require Logger

  def execute(automation, %{type: :test_case, id: test_case_id}, action) do
    with {:ok, test_case} <- Tests.get_test_case_by_id(test_case_id),
         project = Projects.get_project_by_id(automation.project_id),
         false <- is_nil(project),
         {:ok, %{installation: installation, repository_full_handle: repo}} <-
           resolve_target(project),
         :ok <- check_no_open_link(automation.id, test_case_id) do
      open_issue(automation, action, project, test_case, installation, repo)
    else
      {:error, :not_found} ->
        Logger.warning("Automation #{automation.id} create_github_issue skipped: test case #{test_case_id} not found")

        :ok

      true ->
        Logger.warning(
          "Automation #{automation.id} create_github_issue skipped: project #{automation.project_id} not found"
        )

        :ok

      {:error, :no_github_connection} ->
        Logger.warning(
          "Automation #{automation.id} create_github_issue skipped: project #{automation.project_id} has no GitHub connection"
        )

        :ok

      {:error, :already_open} ->
        :ok

      other ->
        Logger.warning(
          "Automation #{automation.id} create_github_issue skipped for test case #{test_case_id}: #{inspect(other)}"
        )

        :ok
    end
  end

  defp resolve_target(project) do
    case Repo.preload(project, vcs_connection: :github_app_installation) do
      %{
        vcs_connection: %{
          provider: :github,
          repository_full_handle: repo,
          github_app_installation: %GitHubAppInstallation{} = installation
        }
      } ->
        {:ok, %{installation: installation, repository_full_handle: repo}}

      _ ->
        {:error, :no_github_connection}
    end
  end

  defp check_no_open_link(alert_id, test_case_id) do
    case Automations.get_open_issue_link(alert_id, test_case_id) do
      nil -> :ok
      _link -> {:error, :already_open}
    end
  end

  defp open_issue(automation, action, project, test_case, installation, repo) do
    project = Repo.preload(project, :account)
    title = interpolate(action["title_template"], automation, project, test_case)
    body = interpolate(action["body_template"], automation, project, test_case)
    labels = Map.get(action, "labels", [])

    case Client.create_issue(%{
           repository_full_handle: repo,
           installation: installation,
           title: title,
           body: body,
           labels: labels
         }) do
      {:ok, %{"number" => _number} = issue} ->
        record_link(automation, project, test_case, installation, repo, issue)
        :ok

      {:error, reason} ->
        Logger.warning(
          "Automation #{automation.id} create_github_issue failed for test case #{test_case.id}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp record_link(automation, project, test_case, installation, repo, issue) do
    attrs = %{
      project_id: project.id,
      alert_id: automation.id,
      test_case_id: test_case.id,
      github_app_installation_id: installation.id,
      github_repository_full_handle: repo,
      github_issue_number: issue["number"],
      github_issue_node_id: issue["node_id"],
      state: "open",
      opened_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    case Automations.create_issue_link(attrs) do
      {:ok, _link} ->
        :ok

      {:error, changeset} ->
        # The most likely failure is the partial unique index
        # `(alert_id, test_case_id) WHERE state = 'open'` firing because a
        # concurrent action already inserted a link. The GitHub issue has
        # already been created at this point — log so we can reconcile.
        Logger.warning(
          "Automation #{automation.id} created GitHub issue ##{issue["number"]} but failed to record IssueLink: #{inspect(changeset.errors)}"
        )
    end
  end

  defp interpolate(nil, _automation, _project, _test_case), do: ""
  defp interpolate("", _automation, _project, _test_case), do: ""

  defp interpolate(template, automation, project, test_case) when is_binary(template) do
    base_url = Environment.app_url()
    account_name = project.account.name
    project_name = project.name
    test_case_url = "#{base_url}/#{account_name}/#{project_name}/tests/test-cases/#{test_case.id}"

    template
    |> String.replace("{{test_case.name}}", to_string(test_case.name || ""))
    |> String.replace("{{test_case.module_name}}", to_string(test_case.module_name || ""))
    |> String.replace("{{test_case.suite_name}}", to_string(test_case.suite_name || ""))
    |> String.replace("{{test_case.url}}", test_case_url)
    |> String.replace("{{automation.name}}", to_string(automation.name || ""))
  end
end
