defmodule Tuist.QA do
  @moduledoc """
  QA module for interacting with Tuist QA.
  """

  import Ecto.Query

  alias Tuist.AppBuilds
  alias Tuist.AppBuilds.AppBuild
  alias Tuist.Authentication
  alias Tuist.Environment
  alias Tuist.Projects
  alias Tuist.QA.Agent
  alias Tuist.QA.Run
  alias Tuist.QA.Screenshot
  alias Tuist.QA.Step
  alias Tuist.Repo
  alias Tuist.Storage
  alias Tuist.VCS

  require EEx

  @qa_summary_template """
  ### 🤖 QA Test Summary
  **Prompt:** <%= @prompt %>
  **Preview:** [<%= @preview_display_name %>](<%= @preview_url %>)
  **Commit:** [<%= String.slice(@commit_sha, 0, 9) %>](<%= @git_remote_url_origin %>/commit/<%= @commit_sha %>)<%= if @summary do %>

  <%= @summary %><% end %><%= if not Enum.empty?(@run_steps) do %>

  <details>
  <summary>🚶 QA Steps</summary>

  <%= for {step, index} <- Enum.with_index(@run_steps, 1) do %>
  #### <%= index %>. <%= step.summary %>

  <%= step.description %><%= if not Enum.empty?(step.issues) do %>

  **⚠️ Issues Found:**<%= for issue <- step.issues do %>
  1. <%= issue %>
  <% end %><% end %><%= if not Enum.empty?(step.screenshots) do %><%= for {screenshot, screenshot_index} <- step.screenshots |> Enum.sort_by(& &1.inserted_at) |> Enum.with_index(1) do %>

  <details>
  <summary><%= screenshot_index %>. <%= screenshot.title %></summary>

  <img src="<%= @app_url %>/<%= @account_handle %>/<%= @project_handle %>/qa/runs/<%= @qa_run_id %>/screenshots/<%= screenshot.id %>" alt="<%= screenshot.title %>" width="500" />
  </details><% end %><% end %>

  <% end %>
  </details>

  <% end %>
  """
  EEx.function_from_string(:defp, :render_qa_summary, @qa_summary_template, [:assigns])

  @doc """
  Run a QA test run for the given app build.
  """
  def test(%{app_build: %AppBuild{id: app_build_id} = app_build, prompt: prompt} = params) do
    app_build = Repo.preload(app_build, preview: [project: :account])
    issue_comment_id = Map.get(params, :issue_comment_id)

    with {:ok, qa_run} <-
           create_qa_run(%{
             app_build_id: app_build_id,
             prompt: prompt,
             status: "pending",
             issue_comment_id: issue_comment_id,
             git_ref: app_build.preview.git_ref,
             vcs_provider: app_build.preview.project.vcs_provider,
             vcs_repository_full_handle: app_build.preview.project.vcs_repository_full_handle
           }),
         app_build_url = generate_app_build_download_url(app_build),
         {:ok, auth_token} <- create_qa_auth_token(app_build),
         :ok <-
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
           ) do
      qa_run(qa_run.id)
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
  def create_qa_step(attrs) do
    %Step{}
    |> Step.changeset(attrs)
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
  Gets a screenshot by ID and optionally by QA run ID.
  """
  def screenshot(screenshot_id, opts \\ []) do
    qa_run_id = Keyword.get(opts, :qa_run_id)

    screenshot =
      if qa_run_id do
        Repo.one(from(s in Screenshot, where: s.id == ^screenshot_id and s.qa_run_id == ^qa_run_id))
      else
        Repo.get(Screenshot, screenshot_id)
      end

    case screenshot do
      nil -> {:error, :not_found}
      screenshot -> {:ok, screenshot}
    end
  end

  @doc """
  Updates screenshots to associate them with a QA run step.
  """
  def update_screenshots_with_step_id(qa_run_id, qa_step_id) do
    Repo.update_all(from(s in Screenshot, where: s.qa_run_id == ^qa_run_id and is_nil(s.qa_step_id)),
      set: [qa_step_id: qa_step_id]
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

  @doc """
  Finds pending QA runs for the given app build.

  Returns a list of pending QA runs that match the app build's repository URL
  and git_ref, and have no app_build_id assigned yet.
  """
  def find_pending_qa_runs_for_app_build(app_build) do
    app_build = Repo.preload(app_build, preview: [project: :account])
    project = app_build.preview.project
    preview = app_build.preview

    if project.vcs_repository_full_handle && project.vcs_provider && preview.git_ref do
      Repo.all(
        from(run in Run,
          where:
            is_nil(run.app_build_id) and run.status == "pending" and
              run.vcs_repository_full_handle == ^project.vcs_repository_full_handle and
              run.vcs_provider == ^project.vcs_provider and
              run.git_ref == ^preview.git_ref
        )
      )
    else
      []
    end
  end

  @doc """
  Posts a QA test summary comment to VCS for the given QA run.
  """
  def post_vcs_test_summary(qa_run) do
    qa_run =
      Repo.preload(qa_run,
        app_build: [preview: [project: :account]],
        run_steps: :screenshots
      )

    preview = qa_run.app_build.preview
    project = preview.project
    comment_body = render_qa_summary_comment_body(qa_run, project)

    if qa_run.issue_comment_id do
      VCS.update_comment(%{
        repository_full_handle: project.vcs_repository_full_handle,
        comment_id: qa_run.issue_comment_id,
        body: comment_body,
        project: project
      })
    else
      VCS.create_comment(%{
        repository_full_handle: project.vcs_repository_full_handle,
        git_ref: preview.git_ref,
        body: comment_body,
        project: project
      })
    end
  end

  defp render_qa_summary_comment_body(qa_run, project) do
    preview = qa_run.app_build.preview
    preview_url = "#{Environment.app_url()}/#{project.account.name}/#{project.name}/previews/#{preview.id}"

    render_qa_summary(%{
      summary: qa_run.summary,
      run_steps: qa_run.run_steps,
      app_url: Environment.app_url(),
      account_handle: project.account.name,
      project_handle: project.name,
      qa_run_id: qa_run.id,
      prompt: qa_run.prompt,
      preview_url: preview_url,
      preview_display_name: preview.display_name,
      commit_sha: preview.git_commit_sha,
      git_remote_url_origin: Projects.get_repository_url(project)
    })
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
      "scopes" => ["project_qa_run_update", "project_qa_step_create", "project_qa_screenshot_create"],
      "project_id" => app_build.preview.project.id
    }

    case Authentication.encode_and_sign(account, claims, token_type: :access, ttl: {1, :hour}) do
      {:ok, token, _claims} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  end
end
