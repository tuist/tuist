defmodule Tuist.Registry.Swift.Workers.UpdatePackagesWorker do
  @moduledoc """
  A worker that adds a new Swift package and populates all its releases.
  """
  use Oban.Worker,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ],
    max_attempts: 3

  alias Tuist.Environment
  alias Tuist.Registry.Swift.Packages
  alias Tuist.VCS
  alias Tuist.VCS.Repositories.Content

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"" => project_id}} = _job) do
    app_build = Repo.preload(app_build, preview: [project: :account])

    with {:ok, qa_run} <- create_qa_run(%{app_build_id: app_build_id, prompt: prompt, status: "pending"}),
         app_build_url = generate_app_build_download_url(app_build),
         {:ok, auth_token} <- create_qa_auth_token(app_build) do
      # TODO: Wrap this in a worker
      Agent.test(%{
        preview_url: app_build_url,
        bundle_identifier: app_build.preview.bundle_identifier,
        prompt: prompt,
        server_url: Environment.app_url(),
        run_id: qa_run.id,
        auth_token: auth_token
      })

      token = Environment.github_token_update_packages()
    end
  end

  # TODO: should we use an account token stored in the database or would it be better to have a short-lived JWT with the given scope?
  # If so, then what would be the resource?
  defp create_qa_auth_token(%AppBuild{} = app_build) do
    account = app_build.preview.project.account

    case Accounts.create_account_token(%{
           account: account,
           scopes: [:project_qa_run_update, :project_qa_run_step_create]
         }) do
      {:ok, {_token_record, token_string}} -> {:ok, token_string}
      {:error, reason} -> {:error, reason}
    end
  end

  defp generate_app_build_download_url(%AppBuild{} = app_build) do
    storage_key =
      Tuist.AppBuilds.storage_key(%{
        account_handle: app_build.preview.project.account.name,
        project_handle: app_build.preview.project.name,
        app_build_id: app_build.id
      })

    Tuist.Storage.generate_download_url(storage_key)
  end
end
