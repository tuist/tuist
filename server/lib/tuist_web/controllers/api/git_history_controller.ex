defmodule TuistWeb.API.GitHistoryController do
  @moduledoc """
  The client's side of `Tuist.GitHistory`: the settings that bound how much
  history it collects, which commits the server still lacks, and the upload
  of those commits. Uploads only add what is missing and repeating one changes
  nothing, so a client can retry freely.
  """
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.GitHistory
  alias TuistWeb.API.Schemas.Error

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)

  tags ["Tests"]

  @path_parameters [
    account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
    project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."]
  ]

  @sha %Schema{type: :string, description: "A commit SHA (40 hex digits, or 64 in a SHA-256 repository)."}

  operation(:settings,
    summary: "Get the Git history settings in effect for a project.",
    description:
      "How much repository history the client should collect and upload with a test run: the window in days and commits, the time it may spend deepening a shallow clone, and how many commits to send per upload request. Server defaults with the project's overrides applied.",
    operation_id: "getGitHistorySettings",
    parameters: @path_parameters,
    responses: %{
      ok:
        {"The settings", "application/json",
         %Schema{
           title: "GitHistorySettings",
           type: :object,
           properties: %{
             window_days: %Schema{type: :integer, description: "How many days back history is collected and kept."},
             window_commits: %Schema{type: :integer, description: "How many commits back history is collected and kept."},
             deepen_budget_seconds: %Schema{
               type: :integer,
               description: "How long the client may spend deepening a shallow clone to find the merge base."
             },
             upload_batch_size: %Schema{type: :integer, description: "How many commits to send per upload request."},
             tracked_file_globs: %Schema{
               type: :array,
               items: %Schema{type: :string},
               description:
                 "Git pathspec globs, relative to the repository root, of the files whose identity a run's evidence depends on (dependency manifests, generator configuration, fixtures, snapshots). The client sends the matched files with their blobs as `tracked_files`."
             },
             tracked_file_limit: %Schema{
               type: :integer,
               description: "How many tracked files to send; beyond it the run is marked `tracked_files_truncated`."
             }
           },
           required: [
             :window_days,
             :window_commits,
             :deepen_budget_seconds,
             :upload_batch_size,
             :tracked_file_globs,
             :tracked_file_limit
           ]
         }},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def settings(%{assigns: %{selected_project: project}} = conn, _params) do
    settings = GitHistory.settings(project)

    json(conn, %{
      window_days: settings.window_days,
      window_commits: settings.window_commits,
      deepen_budget_seconds: settings.deepen_budget_seconds,
      upload_batch_size: settings.upload_batch_size,
      tracked_file_globs: settings.tracked_file_globs,
      tracked_file_limit: settings.tracked_file_limit
    })
  end

  operation(:missing_commits,
    summary: "Find which commits the server has not stored yet.",
    description:
      "Given the SHAs of the commits a client can see, returns the ones the project's commit graph lacks, so the client uploads only those.",
    operation_id: "findMissingCommits",
    parameters: @path_parameters,
    request_body:
      {"The SHAs to check", "application/json",
       %Schema{
         title: "MissingCommitsRequest",
         type: :object,
         properties: %{shas: %Schema{type: :array, items: @sha, maxItems: 10_000}},
         required: [:shas]
       }},
    responses: %{
      ok:
        {"The SHAs the server lacks", "application/json",
         %Schema{
           title: "MissingCommitsResponse",
           type: :object,
           properties: %{missing: %Schema{type: :array, items: @sha}},
           required: [:missing]
         }},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def missing_commits(%{assigns: %{selected_project: project}, body_params: %{shas: shas}} = conn, _params) do
    json(conn, %{missing: GitHistory.missing_shas(project.id, shas)})
  end

  operation(:upload_commits,
    summary: "Upload commits to the project's commit graph.",
    description:
      "Adds commits and their parent edges to the project's commit graph, oldest first for exact generation numbers, and records the newest commit seen on each given branch. Commits already stored are left untouched, so a repeated upload changes nothing.",
    operation_id: "uploadCommits",
    parameters: @path_parameters,
    request_body:
      {"The commits", "application/json",
       %Schema{
         title: "UploadCommitsRequest",
         type: :object,
         properties: %{
           object_format: %Schema{
             type: :string,
             enum: ["sha1", "sha256"],
             description: "The repository's Git object format."
           },
           commits: %Schema{
             type: :array,
             maxItems: 10_000,
             items: %Schema{
               type: :object,
               properties: %{
                 sha: @sha,
                 parents: %Schema{type: :array, items: @sha, description: "The parent SHAs, first parent first."},
                 committed_at: %Schema{type: :string, format: :"date-time", description: "The committer date."}
               },
               required: [:sha, :parents, :committed_at]
             }
           },
           branch_heads: %Schema{
             type: :array,
             items: %Schema{
               type: :object,
               properties: %{branch: %Schema{type: :string}, sha: @sha},
               required: [:branch, :sha]
             },
             description: "The newest commit the client saw on each branch."
           }
         },
         required: [:object_format, :commits]
       }},
    responses: %{
      no_content: "The commits were stored",
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def upload_commits(%{assigns: %{selected_project: project}, body_params: body} = conn, _params) do
    commits =
      Enum.map(body.commits, fn commit ->
        %{sha: commit.sha, parents: commit.parents, committed_at: commit.committed_at}
      end)

    GitHistory.record_commits(project.id, body.object_format, commits)

    for head <- Map.get(body, :branch_heads) || [] do
      GitHistory.record_branch_head(project.id, head.branch, head.sha)
    end

    send_resp(conn, :no_content, "")
  end
end
