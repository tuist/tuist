defmodule TuistWeb.RunsController do
  use TuistWeb, :controller

  alias Tuist.Authorization
  alias Tuist.CommandEvents
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Tests
  alias TuistWeb.Authentication

  # `run_id` is a command_event id for CLI `tuist test` runs, or a test run id
  # for remote-processed `tuist inspect test` runs — those have no
  # command_event and store the bundle under the test run id. Try both.
  def download(conn, %{"run_id" => run_id}) do
    user = Authentication.current_user(conn)

    with :error <- command_event_bundle_url(run_id, user),
         :error <- test_run_bundle_url(run_id, user) do
      {:error, :not_found}
    else
      {:ok, url} -> conn |> redirect(external: url) |> halt()
    end
  end

  def download_session(conn, %{"run_id" => command_event_id}) do
    user = Authentication.current_user(conn)

    with {:ok, command_event} <- CommandEvents.get_command_event_by_id(command_event_id),
         {:ok, project} <- CommandEvents.get_project_for_command_event(command_event, preload: :account),
         :ok <- Authorization.authorize(:run_read, user, project) do
      conn
      |> redirect(external: CommandEvents.generate_session_url(command_event))
      |> halt()
    end
  end

  defp command_event_bundle_url(run_id, user) do
    with {:ok, command_event} <- CommandEvents.get_command_event_by_id(run_id),
         {:ok, project} <- CommandEvents.get_project_for_command_event(command_event, preload: :account),
         :ok <- Authorization.authorize(:run_read, user, project) do
      {:ok, CommandEvents.generate_result_bundle_url(command_event)}
    else
      _ -> :error
    end
  end

  defp download_bundle_ids(%{reporting_version: 1} = test_run, _requested_id), do: Tests.result_bundle_run_ids(test_run)

  defp download_bundle_ids(test_run, requested_id), do: Enum.uniq([requested_id, test_run.id])

  defp test_run_bundle_url(run_id, user) do
    with {:ok, test_run} <- Tests.get_test(run_id),
         %Projects.Project{} = project <- Projects.get_project_by_id(test_run.project_id),
         project = Repo.preload(project, :account),
         :ok <- Authorization.authorize(:run_read, user, project),
         bundle_id when is_binary(bundle_id) <-
           Enum.find(download_bundle_ids(test_run, run_id), &CommandEvents.has_result_bundle?(&1, project)) do
      {:ok, CommandEvents.generate_result_bundle_url(bundle_id, project)}
    else
      _ -> :error
    end
  end
end
