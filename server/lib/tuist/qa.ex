defmodule Tuist.QA do
  @moduledoc """
  The QA context for managing QA runs.
  """

  import Ecto.Query, warn: false

  alias Tuist.Accounts
  alias Tuist.AppBuilds.AppBuild
  alias Tuist.Environment
  alias Tuist.QA.Agent
  alias Tuist.QA.Run
  alias Tuist.QA.RunStep
  alias Tuist.Repo

  @doc """
  Run a QA test run for the given app build.
  """
  def test(%{app_build: %AppBuild{id: app_build_id} = app_build, prompt: prompt}) do
    app_build = Repo.preload(app_build, preview: [project: :account])

    with {:ok, qa_run} <- create_qa_run(%{app_build_id: app_build_id, prompt: prompt, status: "pending"}),
         app_build_url = generate_app_build_download_url(app_build),
         {:ok, auth_token} <- create_qa_auth_token(app_build) do
      Agent.test(
        %{
          preview_url: app_build_url,
          bundle_identifier: app_build.preview.bundle_identifier,
          prompt: prompt,
          server_url: Environment.app_url(),
          run_id: qa_run.id,
          auth_token: auth_token
        },
        anthropic_api_key: Environment.anthropic_api_key()
      )
    end
  end

  @doc """
  Creates a new QA run.
  """
  def create_qa_run(attrs) do
    %Run{}
    |> Run.create_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a QA run.
  """
  def update_qa_run(%Run{} = qa_run, attrs) do
    qa_run
    |> Run.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Creates a new QA run step.
  """
  def create_qa_run_step(attrs) do
    %RunStep{}
    |> RunStep.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a QA run by ID.
  """
  def qa_run(id) do
    case Repo.get(Run, id) do
      nil -> {:error, :not_found}
      run -> {:ok, run}
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
end
