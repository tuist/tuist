defmodule TuistWeb.RunnerJobRedirectController do
  @moduledoc """
  Resolves a runner name to the job that ran on it and redirects to the
  job's dashboard page.

  Runners link here from GitHub's "Set up job" step. The link is written
  before GitHub assigns the runner a job, so it can only carry the
  runner's name, not the job's ID.
  """
  use TuistWeb, :controller

  alias Tuist.Accounts
  alias Tuist.Authorization
  alias Tuist.FeatureFlags
  alias Tuist.Runners.WorkflowJobs
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.RunnerJobLive

  def show(conn, %{"account_handle" => account_handle, "runner_name" => runner_name}) do
    account = Accounts.get_account_by_handle(account_handle)
    user = Authentication.current_user(conn)

    with false <- is_nil(account),
         :ok <- Authorization.authorize(:runners_read, user, account),
         true <- FeatureFlags.runners_enabled?(account),
         {:ok, job} <- WorkflowJobs.get_executed_by_runner_name(account.id, runner_name),
         path when is_binary(path) <- RunnerJobLive.path(account.name, job) do
      redirect(conn, to: path)
    else
      _ ->
        raise NotFoundError,
              dgettext("dashboard_runners", "The job you are looking for doesn't exist or has been moved.")
    end
  end
end
