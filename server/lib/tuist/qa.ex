defmodule Tuist.QA do
  @moduledoc """
  QA module for interacting with Tuist QA.
  """

  import Ecto.Query

  alias Tuist.AppBuilds
  alias Tuist.AppBuilds.AppBuild
  alias Tuist.Authentication
  alias Tuist.Environment
  alias Tuist.QA.Agent
  alias Tuist.QA.Run
  alias Tuist.QA.RunStep
  alias Tuist.QA.Screenshot
  alias Tuist.Repo
  alias Tuist.Storage

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
          auth_token: auth_token,
          account_handle: app_build.preview.project.account.name,
          project_handle: app_build.preview.project.name
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
  def qa_run(id, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    case Run |> Repo.get(id) |> Repo.preload(preload) do
      nil -> {:error, :not_found}
      run -> {:ok, run}
    end
  end

  @doc """
  Creates a new QA screenshot.
  """
  def create_qa_screenshot(attrs) do
    %Screenshot{}
    |> Screenshot.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates screenshots to associate them with a QA run step.
  """
  def update_screenshots_with_step_id(qa_run_id, qa_run_step_id) do
    Repo.update_all(from(s in Screenshot, where: s.qa_run_id == ^qa_run_id and is_nil(s.qa_run_step_id)),
      set: [qa_run_step_id: qa_run_step_id]
    )
  end

  @doc """
  Generates a storage key for a QA screenshot.
  """
  def screenshot_storage_key(%{
        account_handle: account_handle,
        project_handle: project_handle,
        qa_run_id: qa_run_id,
        file_name: file_name
      }) do
    "#{String.downcase(account_handle)}/#{String.downcase(project_handle)}/qa/screenshots/#{qa_run_id}/#{file_name}.png"
  end

  defp generate_app_build_download_url(%AppBuild{} = app_build) do
    storage_key =
      AppBuilds.storage_key(%{
        account_handle: app_build.preview.project.account.name,
        project_handle: app_build.preview.project.name,
        app_build_id: app_build.id
      })

    Storage.generate_download_url(storage_key)
  end

  defp create_qa_auth_token(%AppBuild{} = app_build) do
    account = app_build.preview.project.account

    claims = %{
      "type" => "account",
      "scopes" => ["project_qa_run_update", "project_qa_run_step_create", "project_qa_screenshot_create"],
      "project_id" => app_build.preview.project.id
    }

    case Authentication.encode_and_sign(account, claims, token_type: :access, ttl: {1, :hour}) do
      {:ok, token, _claims} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  end
end
