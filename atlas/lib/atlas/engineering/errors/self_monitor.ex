defmodule Atlas.Engineering.Errors.SelfMonitor do
  @moduledoc """
  Bootstraps the "Atlas" self-project so Atlas' own crashes can be recorded
  through the same pipeline external SDKs use, and registers the Erlang
  logger handler that captures them.

  Only installs the handler when Atlas' primary Sentry.LoggerHandler is not
  active — otherwise the two would double-report. The primary handler is
  active whenever a Sentry DSN is configured.
  """

  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Errors.LoggerHandler
  alias Atlas.Engineering.Errors.ProjectKey
  alias Atlas.Engineering.Projects
  alias Atlas.Engineering.Projects.Project
  alias Atlas.Repo

  require Logger

  @project_name "Atlas"

  def install do
    with true <- Errors.enabled?(),
         true <- primary_sentry_handler_absent?(),
         {:ok, project} <- ensure_project(),
         {:ok, _key} <- ensure_default_key(project) do
      Application.put_env(:atlas, :errors_self_project_id, project.id)
      LoggerHandler.attach()
      :ok
    else
      false ->
        :ok

      error ->
        Logger.warning("errors.self_monitor: bootstrap failed: #{inspect(error)}")
        :ok
    end
  rescue
    error ->
      Logger.warning("errors.self_monitor: bootstrap crashed: #{Exception.message(error)}")
      :ok
  end

  def self_project_id, do: Application.get_env(:atlas, :errors_self_project_id)

  defp primary_sentry_handler_absent? do
    is_nil(Application.get_env(:sentry, :dsn))
  end

  defp ensure_project do
    case Repo.get_by(Project, name: @project_name) do
      %Project{} = project ->
        {:ok, project}

      nil ->
        Projects.create_project(%{
          "name" => @project_name,
          "description" => "Errors captured from the running Atlas instance.",
          "visibility" => "private"
        })
    end
  end

  defp ensure_default_key(project) do
    case Errors.list_project_keys(project.id) do
      [%ProjectKey{} = key | _] -> {:ok, key}
      [] -> Errors.create_project_key(project.id, %{"name" => "self"})
    end
  end
end
