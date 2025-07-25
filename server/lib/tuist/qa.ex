defmodule Tuist.QA do
  @moduledoc """
  The QA context for managing QA runs.
  """
  
  import Ecto.Query, warn: false
  
  alias Tuist.Accounts
  alias Tuist.QA.Agent
  alias Tuist.QA.Run
  alias Tuist.QA.RunStep
  alias Tuist.Repo
  alias Tuist.AppBuilds.AppBuild
  
  require Logger

  @doc """
  Starts a QA test run for the given app build.
  
  ## Examples
  
      iex> test(%{app_build_id: "123", prompt: "Test login flow", server_url: "https://api.tuist.dev/api"})
      {:ok, :completed}
      
  """
  def test(%{app_build_id: app_build_id, prompt: prompt, server_url: server_url}) do
    with {:ok, app_build} <- get_app_build(app_build_id),
         {:ok, qa_run} <- create_qa_run(%{app_build_id: app_build_id, prompt: prompt}),
         {:ok, _} <- update_qa_run(qa_run, %{status: "running"}),
         {:ok, app_build_url} <- get_app_build_url(app_build),
         {:ok, auth_token} <- create_qa_auth_token(app_build),
         result <- Agent.test(%{
           preview_url: app_build_url,
           bundle_identifier: app_build.preview.bundle_identifier,
           prompt: prompt,
           server_url: server_url,
           run_id: qa_run.id,
           auth_token: auth_token
         }) do
      
      final_status = case result do
        :ok -> "completed"
        {:error, _} -> "failed"
      end
      
      {:ok, _} = update_qa_run(qa_run, %{status: final_status})
      
      {:ok, final_status}
    else
      {:error, reason} ->
        Logger.error("QA test failed: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  @doc """
  Creates a new QA run.
  """
  def create_qa_run(attrs) do
    %Run{}
    |> Run.changeset(attrs)
    |> Repo.insert()
  end
  
  @doc """
  Updates a QA run.
  """
  def update_qa_run(%Run{} = qa_run, attrs) do
    qa_run
    |> Run.changeset(attrs)
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
  def get_qa_run(id) do
    case Repo.get(Run, id) do
      nil -> {:error, :not_found}
      run -> {:ok, run}
    end
  end
  
  defp get_app_build(app_build_id) do
    app_build = 
      AppBuild
      |> preload(preview: [project: :account])
      |> Repo.get(app_build_id)
      
    case app_build do
      nil -> {:error, :app_build_not_found}
      app_build -> {:ok, app_build}
    end
  end
  
  defp get_app_build_url(%AppBuild{} = app_build) do
    account = app_build.preview.project.account
    project = app_build.preview.project
    
    storage_key = Tuist.AppBuilds.storage_key(%{
      account_handle: account.name,
      project_handle: project.slug,
      app_build_id: app_build.id
    })
    
    Tuist.Storage.generate_download_url(storage_key)
  end
  
  defp create_qa_auth_token(%AppBuild{} = app_build) do
    account = app_build.preview.project.account
    
    case Accounts.create_account_token(%{
      account: account,
      scopes: [:project_qa_run]
    }) do
      {:ok, {_token_record, token_string}} -> {:ok, token_string}
      {:error, reason} -> {:error, reason}
    end
  end
end