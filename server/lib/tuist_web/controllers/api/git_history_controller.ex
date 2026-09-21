defmodule TuistWeb.API.GitHistoryController do
  @moduledoc """
  The client's side of `Tuist.GitHistory`: the settings that bound how much
  history it collects, which commits and commit listings the server still
  lacks, and their upload. The repository is named by its remote URL, since
  the graph belongs to the repository rather than to the project. Uploads
  only add what is missing and repeating one changes nothing, so a client
  can retry freely.
  """
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.GitHistory
  alias Tuist.VCS.RemoteURL
  alias TuistWeb.API.Schemas.Error

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :test)
  plug(TuistWeb.Plugs.RequireCoveragePlug)

  tags ["Tests"]

  @path_parameters [
    account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
    project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."]
  ]

  @sha %Schema{type: :string, description: "A commit SHA (40 hex digits, or 64 in a SHA-256 repository)."}

  @repository_url %Schema{
    type: :string,
    description:
      "The repository's remote URL (`git remote get-url origin`), which identifies the commit graph: several projects can share one repository and a fork has its own. Credentials in the URL are stripped."
  }

  @common_responses %{
    bad_request: {"The repository URL names no repository", "application/json", Error},
    unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
    forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
    not_found: {"The project was not found", "application/json", Error}
  }

  operation(:settings,
    summary: "Get the Git history settings in effect for a project.",
    description:
      "How much repository history the client should collect and upload with a test run: the window in days and commits, the time it may spend deepening a shallow clone, how many commits to send per upload request, and how many files of a commit's tree to list. Server defaults with the project's overrides applied.",
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
             commit_file_limit: %Schema{
               type: :integer,
               description:
                 "How many files of a commit's tree to list (`uploadCommitListing`); beyond it the listing is marked truncated."
             }
           },
           required: [:window_days, :window_commits, :deepen_budget_seconds, :upload_batch_size, :commit_file_limit]
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
      commit_file_limit: settings.commit_file_limit
    })
  end

  operation(:missing_commits,
    summary: "Find which commits the server has not stored yet.",
    description:
      "Given the SHAs of the commits a client can see, returns the ones the repository's commit graph lacks, so the client uploads only those.",
    operation_id: "findMissingCommits",
    parameters: @path_parameters,
    request_body:
      {"The SHAs to check", "application/json",
       %Schema{
         title: "MissingCommitsRequest",
         type: :object,
         properties: %{repository_url: @repository_url, shas: %Schema{type: :array, items: @sha, maxItems: 10_000}},
         required: [:repository_url, :shas]
       }},
    responses:
      Map.put(
        @common_responses,
        :ok,
        {"The SHAs the server lacks", "application/json",
         %Schema{
           title: "MissingCommitsResponse",
           type: :object,
           properties: %{missing: %Schema{type: :array, items: @sha}},
           required: [:missing]
         }}
      )
  )

  def missing_commits(%{assigns: %{selected_project: project}, body_params: body} = conn, _params) do
    case repository_id(project, body.repository_url) do
      nil -> bad_request(conn)
      repository_id -> json(conn, %{missing: GitHistory.missing_shas(repository_id, body.shas)})
    end
  end

  operation(:upload_commits,
    summary: "Upload commits to the repository's commit graph.",
    description:
      "Adds commits and their parent edges to the repository's commit graph, oldest first for exact generation numbers, and records the newest commit seen on each given branch. Commits already stored are left untouched, so a repeated upload changes nothing.",
    operation_id: "uploadCommits",
    parameters: @path_parameters,
    request_body:
      {"The commits", "application/json",
       %Schema{
         title: "UploadCommitsRequest",
         type: :object,
         properties: %{
           repository_url: @repository_url,
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
         required: [:repository_url, :object_format, :commits]
       }},
    responses: Map.put(@common_responses, :no_content, "The commits were stored")
  )

  def upload_commits(%{assigns: %{selected_project: project}, body_params: body} = conn, _params) do
    case repository_id(project, body.repository_url) do
      nil ->
        bad_request(conn)

      repository_id ->
        commits =
          Enum.map(body.commits, fn commit ->
            %{sha: commit.sha, parents: commit.parents, committed_at: commit.committed_at}
          end)

        GitHistory.record_commits(repository_id, body.object_format, commits)

        for head <- Map.get(body, :branch_heads) || [] do
          GitHistory.record_branch_head(repository_id, head.branch, head.sha)
        end

        send_resp(conn, :no_content, "")
    end
  end

  operation(:missing_listings,
    summary: "Find which commits have no file listing stored yet.",
    description:
      "Given commit SHAs, returns the ones whose file listing (every file of the commit's tree with its blob) the server lacks, so a clean checkout uploads it once per commit. The listing is what coverage is measured against, where the project's tracked files are read, and what evidence reuse compares.",
    operation_id: "findMissingCommitListings",
    parameters: @path_parameters,
    request_body:
      {"The SHAs to check", "application/json",
       %Schema{
         title: "MissingCommitListingsRequest",
         type: :object,
         properties: %{repository_url: @repository_url, shas: %Schema{type: :array, items: @sha, maxItems: 1_000}},
         required: [:repository_url, :shas]
       }},
    responses:
      Map.put(
        @common_responses,
        :ok,
        {"The SHAs whose listing the server lacks", "application/json",
         %Schema{
           title: "MissingCommitListingsResponse",
           type: :object,
           properties: %{missing: %Schema{type: :array, items: @sha}},
           required: [:missing]
         }}
      )
  )

  def missing_listings(%{assigns: %{selected_project: project}, body_params: body} = conn, _params) do
    case repository_id(project, body.repository_url) do
      nil -> bad_request(conn)
      repository_id -> json(conn, %{missing: GitHistory.missing_listings(repository_id, body.shas)})
    end
  end

  operation(:upload_listing,
    summary: "Upload a commit's file listing.",
    description:
      "Stores the files of a commit's tree with their blobs, as `git ls-files --stage` lists them at a clean checkout, capped at the project's `commit_file_limit`. A large listing is sent in several requests; the last one carries `complete: true`, which records the listing as stored. Repeating a request changes nothing.",
    operation_id: "uploadCommitListing",
    parameters: @path_parameters,
    request_body:
      {"The listing", "application/json",
       %Schema{
         title: "UploadCommitListingRequest",
         type: :object,
         properties: %{
           repository_url: @repository_url,
           sha: @sha,
           files: %Schema{
             type: :array,
             maxItems: 20_000,
             items: %Schema{
               type: :object,
               properties: %{
                 path: %Schema{type: :string, description: "Relative to the repository root."},
                 git_blob_id: %Schema{type: :string, description: "The file's blob at the commit."},
                 mode: %Schema{type: :integer, description: "The Git file mode as an integer (33188 for 100644)."}
               },
               required: [:path, :git_blob_id]
             }
           },
           complete: %Schema{type: :boolean, description: "Whether this request ends the listing (true by default)."},
           truncated: %Schema{type: :boolean, description: "Whether the client stopped at the limit."},
           files_count: %Schema{
             type: :integer,
             description: "How many files the whole listing has, sent with the last request."
           }
         },
         required: [:repository_url, :sha, :files]
       }},
    responses: Map.put(@common_responses, :no_content, "The listing was stored")
  )

  def upload_listing(%{assigns: %{selected_project: project}, body_params: body} = conn, _params) do
    case repository_id(project, body.repository_url) do
      nil ->
        bad_request(conn)

      repository_id ->
        files = Enum.map(body.files, &%{path: &1.path, git_blob_id: &1.git_blob_id, mode: Map.get(&1, :mode)})

        opts =
          [complete: Map.get(body, :complete, true), truncated: Map.get(body, :truncated, false)] ++
            case Map.get(body, :files_count) do
              nil -> []
              count -> [files_count: count]
            end

        GitHistory.record_listing(repository_id, body.sha, files, opts)
        send_resp(conn, :no_content, "")
    end
  end

  defp repository_id(project, url), do: GitHistory.repository_id(project.account_id, RemoteURL.strip_credentials(url))

  defp bad_request(conn) do
    conn |> put_status(:bad_request) |> json(%{message: "repository_url does not name a repository"})
  end
end
