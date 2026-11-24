defmodule TuistWeb.API.CoverageController do
  @moduledoc """
  Code coverage over the API: what a client needs to send a run's coverage
  when it processed the bundle itself (the inline threshold and a signed
  upload URL), the signal that a commit's coverage pipeline finished, and
  the reads of a branch's, a commit's and a file's coverage, a commit's
  targets, and the history behind them: the branches, a branch's commits and
  the runs behind a commit or branch (`Tuist.Tests.Coverage.Query`).
  """
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Snapshots
  alias Tuist.Storage
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Query
  alias Tuist.Tests.Coverage.Report
  alias Tuist.Tests.Coverage.Schemas
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.API.Schemas.PaginationMetadata

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

  operation(:settings,
    summary: "Get the code coverage upload settings for a project.",
    description:
      "The size, in bytes of the uncompressed coverage, above which a client that processed the result bundle itself uploads the coverage to object storage (see `createCoverageUpload`) instead of sending it inline with the test run. The run's request body is held to its limit after it is inflated, so the comparison uses the uncompressed size even when the client compresses the request.",
    operation_id: "getCoverageSettings",
    parameters: @path_parameters,
    responses: %{
      ok:
        {"The settings", "application/json",
         %Schema{
           title: "CoverageSettings",
           type: :object,
           properties: %{
             inline_threshold_bytes: %Schema{
               type: :integer,
               description: "Coverage whose uncompressed size is larger than this goes through an upload."
             }
           },
           required: [:inline_threshold_bytes]
         }},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def settings(conn, _params) do
    json(conn, %{inline_threshold_bytes: Environment.coverage_inline_threshold_bytes()})
  end

  operation(:create_upload,
    summary: "Get a signed URL to upload a test run's code coverage.",
    description:
      "Returns where to PUT the DEFLATE-compressed coverage file (one JSON object per source file, as the client's parser writes it) for a test run the client is about to create with the given id. The run then references it through `coverage.storage_key` (or `xcode_coverage_storage_key`), and the server reads it back once the run exists. A second key and URL take the run's per-test coverage evidence, which the run references through `coverage_evidence.storage_key` and the server reads while it creates the run.",
    operation_id: "createCoverageUpload",
    parameters: @path_parameters,
    request_body:
      {"The run the coverage belongs to", "application/json",
       %Schema{
         title: "CoverageUploadRequest",
         type: :object,
         properties: %{
           test_run_id: %Schema{
             type: :string,
             format: :uuid,
             description: "The client-generated id of the test run the coverage belongs to."
           }
         },
         required: [:test_run_id]
       }},
    responses: %{
      ok:
        {"Where to upload the coverage", "application/json",
         %Schema{
           title: "CoverageUpload",
           type: :object,
           properties: %{
             storage_key: %Schema{
               type: :string,
               description: "The key to send with the run as `coverage.storage_key` (or `xcode_coverage_storage_key`)."
             },
             upload_url: %Schema{type: :string, description: "A short-lived URL to PUT the compressed coverage to."},
             evidence_storage_key: %Schema{
               type: :string,
               description: "The key to send with the run as `coverage_evidence.storage_key`."
             },
             evidence_upload_url: %Schema{
               type: :string,
               description:
                 "A short-lived URL to PUT the run's DEFLATE-compressed per-test coverage evidence to (see `coverage_evidence.storage_key` on the test run)."
             }
           },
           required: [:storage_key, :upload_url]
         }},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def create_upload(%{assigns: %{selected_project: project}, body_params: %{test_run_id: test_run_id}} = conn, _params) do
    storage_key = Coverage.storage_key(project, test_run_id)
    evidence_storage_key = Coverage.evidence_storage_key(project, test_run_id)

    json(conn, %{
      storage_key: storage_key,
      upload_url: Storage.generate_upload_url(storage_key, project.account),
      evidence_storage_key: evidence_storage_key,
      evidence_upload_url: Storage.generate_upload_url(evidence_storage_key, project.account)
    })
  end

  @sha_parameter [
    git_commit_sha: [in: :path, type: :string, required: true, description: "The commit SHA."]
  ]

  @access_responses %{
    unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
    forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error}
  }

  @not_found_responses Map.put(
                         @access_responses,
                         :not_found,
                         {"The run or commit was not found, or gathered no coverage", "application/json", Error}
                       )
  operation(:show,
    summary: "Get the code coverage of a branch.",
    description:
      "The coverage of the branch's latest complete commit: the newest commit whose pipeline signalled it finished (see `completeCommitCoverage`) and whose figure is whole, the point the branch's coverage trend ends at. The branch's commits are the ones its ref owns in the commit graph, newest first by when they were made, or, when its ref owns none, the commits its runs were labelled with, newest first by when they ran; one indexed read, newest first, finds the commit. Newer commits still in progress, or whose figure is a lower bound, are left out.",
    operation_id: "getBranchCoverage",
    parameters:
      @path_parameters ++
        [
          branch: [
            in: :query,
            type: :string,
            description: "The branch to read. The project's default branch when omitted."
          ]
        ],
    responses:
      Map.merge(@access_responses, %{
        ok: {"The coverage of the branch's latest complete commit", "application/json", Schemas.branch()},
        not_found:
          {"The project was not found, or no complete commit on the branch gathered coverage", "application/json", Error}
      })
  )

  def show(%{assigns: %{selected_project: project}} = conn, params) do
    project |> Query.branch(Map.get(params, :branch)) |> render_read(conn)
  end

  operation(:show_commit,
    summary: "Get the code coverage of a commit.",
    description:
      "The commit's coverage, complete or not: the union of every run that measured it, its measured set and its targets.",
    operation_id: "getCommitCoverage",
    parameters: @path_parameters ++ @sha_parameter,
    responses: Map.put(@not_found_responses, :ok, {"The commit's coverage", "application/json", Schemas.commit()})
  )

  def show_commit(%{assigns: %{selected_project: project}} = conn, %{git_commit_sha: sha}) do
    project |> Query.commit(sha) |> render_read(conn)
  end

  operation(:list_files,
    summary: "List the files of a commit's code coverage.",
    description:
      "One page of the product files the commit's runs measured, with their line coverage, least covered first by default. Per-file coverage is kept for a shorter time than a commit's figures, so an older commit can list no files.",
    operation_id: "listCommitCoverageFiles",
    parameters:
      @path_parameters ++
        @sha_parameter ++
        [
          page: [
            in: :query,
            type: %Schema{
              title: "CommitCoverageFilesPage",
              description: "The page number to return.",
              type: :integer,
              default: 1,
              minimum: 1
            }
          ],
          page_size: [
            in: :query,
            type: %Schema{
              title: "CommitCoverageFilesPageSize",
              description: "The maximum number of files to return in a single page.",
              type: :integer,
              default: 20,
              minimum: 1,
              maximum: 100
            }
          ],
          search: [
            in: :query,
            type: :string,
            description: "Keeps the files whose path contains it, ignoring case."
          ],
          sort_by: [
            in: :query,
            type: %Schema{
              title: "CommitCoverageFilesSortBy",
              type: :string,
              enum: ["coverage", "path"],
              default: "coverage"
            },
            description: "What to sort the files by."
          ],
          sort_order: [
            in: :query,
            type: %Schema{
              title: "CommitCoverageFilesSortOrder",
              type: :string,
              enum: ["asc", "desc"],
              default: "asc"
            },
            description: "The order to sort the files in."
          ]
        ],
    responses:
      Map.put(
        @not_found_responses,
        :ok,
        {"A page of the commit's files", "application/json", Schemas.files(PaginationMetadata)}
      )
  )

  def list_files(%{assigns: %{selected_project: project}} = conn, %{git_commit_sha: sha} = params) do
    project
    |> Query.files(sha,
      page: params.page,
      page_size: params.page_size,
      search: Map.get(params, :search),
      sort_by: params.sort_by,
      sort_order: params.sort_order
    )
    |> render_read(conn)
  end

  operation(:show_file,
    summary: "Get the code coverage of a file at a commit.",
    description:
      "The file's figures and functions at the commit, merged over every run that measured it, and its per-line execution counts with `include_lines`. Per-file coverage is kept for a shorter time than a commit's figures, so a commit can be found while its files are not.",
    operation_id: "getCommitCoverageFile",
    parameters:
      @path_parameters ++
        @sha_parameter ++
        [
          path: [
            in: :query,
            type: :string,
            required: true,
            description: "The file's path, relative to the repository's root."
          ],
          include_lines: [
            in: :query,
            type: %Schema{type: :boolean, default: false},
            description: "Whether to include every executable line and how many times it ran."
          ]
        ],
    responses:
      Map.merge(@access_responses, %{
        ok: {"The file's coverage", "application/json", Schemas.file()},
        not_found:
          {"The commit gathered no coverage, or no coverage of the file is kept for it", "application/json", Error}
      })
  )

  def show_file(%{assigns: %{selected_project: project}} = conn, %{git_commit_sha: sha, path: path} = params) do
    project |> Query.file(sha, path, include_lines: params.include_lines) |> render_read(conn)
  end

  @cursor_parameters [
    after: [
      in: :query,
      type: :string,
      description: "Read the page older than this cursor: a previous page's `end_cursor`."
    ],
    before: [
      in: :query,
      type: :string,
      description: "Read the page newer than this cursor: a previous page's `start_cursor`."
    ],
    page_size: [
      in: :query,
      type: %Schema{
        title: "CoverageHistoryPageSize",
        description: "The maximum number of rows to return in a single page.",
        type: :integer,
        default: 20,
        minimum: 1,
        maximum: 100
      }
    ]
  ]

  operation(:list_branches,
    summary: "List the branches with code coverage.",
    description:
      "The branches whose runs never named a pull request and that have a measured commit, the most recently measured first, at most 100. The project's default branch leads, whether or not it has coverage.",
    operation_id: "listCoverageBranches",
    parameters: @path_parameters,
    responses:
      Map.merge(@access_responses, %{
        ok: {"The branches", "application/json", Schemas.branches()},
        not_found: {"The project was not found", "application/json", Error}
      })
  )

  def list_branches(%{assigns: %{selected_project: project}} = conn, _params) do
    project |> Query.branches() |> render_read(conn)
  end

  operation(:list_commits,
    summary: "List a branch's commits with their code coverage.",
    description:
      "One page of the branch's commits, newest first, each with its status, its figure and the change from the complete commit before it. A branch the commit graph holds lists its unmeasured commits too (`not_measured`); otherwise its commits are the measured ones its runs were labelled with, by when they ran.",
    operation_id: "listCoverageCommits",
    parameters:
      @path_parameters ++
        [
          branch: [
            in: :query,
            type: :string,
            description: "The branch to read. The project's default branch when omitted."
          ],
          status: [
            in: :query,
            type: %Schema{
              title: "CoverageCommitsStatus",
              type: :string,
              enum: ["measured", "any", "complete", "incomplete", "in_progress", "not_measured"],
              default: "measured"
            },
            description: "Which commits to list: `measured` (every status but `not_measured`), `any`, or one status."
          ],
          search: [in: :query, type: :string, description: "Keeps the commits whose SHA starts with it."]
        ] ++ @cursor_parameters,
    responses:
      Map.merge(@access_responses, %{
        ok: {"A page of the branch's commits", "application/json", Schemas.commits()},
        not_found: {"The project was not found", "application/json", Error}
      })
  )

  def list_commits(%{assigns: %{selected_project: project}} = conn, params) do
    project
    |> Query.commits(Map.get(params, :branch),
      status: params.status,
      search: Map.get(params, :search),
      after: Map.get(params, :after),
      before: Map.get(params, :before),
      page_size: params.page_size
    )
    |> render_read(conn)
  end

  operation(:list_runs,
    summary: "List the test runs with code coverage behind a commit or a branch.",
    description:
      "One page of the runs with coverage of a commit (`git_commit_sha`) or, otherwise, of those that named a branch, newest first. Runs from a dirty checkout are listed as `discarded`: their coverage doesn't join the commit's.",
    operation_id: "listCoverageRuns",
    parameters:
      @path_parameters ++
        [
          git_commit_sha: [
            in: :query,
            type: :string,
            description: "The commit whose runs to list. Takes precedence over branch."
          ],
          branch: [
            in: :query,
            type: :string,
            description: "The branch whose runs to list. The project's default branch when neither is given."
          ],
          scheme: [in: :query, type: :string, description: "Keeps one scheme's runs."]
        ] ++ @cursor_parameters,
    responses:
      Map.merge(@access_responses, %{
        ok: {"A page of the runs", "application/json", Schemas.runs()},
        not_found: {"The project was not found", "application/json", Error}
      })
  )

  def list_runs(%{assigns: %{selected_project: project}} = conn, params) do
    project
    |> Query.runs(
      git_commit_sha: Map.get(params, :git_commit_sha),
      branch: Map.get(params, :branch),
      scheme: Map.get(params, :scheme),
      after: Map.get(params, :after),
      before: Map.get(params, :before),
      page_size: params.page_size
    )
    |> render_read(conn)
  end

  operation(:list_targets,
    summary: "List the targets of a commit's code coverage.",
    description:
      "One page of the targets the commit's runs measured, least covered first by default, followed by those its runs took from the binary cache without coverage counters (`measured: false`), which have no figure.",
    operation_id: "listCommitCoverageTargets",
    parameters:
      @path_parameters ++
        @sha_parameter ++
        [
          page: [
            in: :query,
            type: %Schema{
              title: "CommitCoverageTargetsPage",
              description: "The page number to return.",
              type: :integer,
              default: 1,
              minimum: 1
            }
          ],
          page_size: [
            in: :query,
            type: %Schema{
              title: "CommitCoverageTargetsPageSize",
              description: "The maximum number of targets to return in a single page.",
              type: :integer,
              default: 20,
              minimum: 1,
              maximum: 100
            }
          ],
          search: [in: :query, type: :string, description: "Keeps the targets whose name contains it, ignoring case."],
          sort_by: [
            in: :query,
            type: %Schema{
              title: "CommitCoverageTargetsSortBy",
              type: :string,
              enum: ["coverage", "name", "files"],
              default: "coverage"
            },
            description: "What to sort the measured targets by."
          ],
          sort_order: [
            in: :query,
            type: %Schema{
              title: "CommitCoverageTargetsSortOrder",
              type: :string,
              enum: ["asc", "desc"],
              default: "asc"
            },
            description: "The order to sort the measured targets in."
          ]
        ],
    responses:
      Map.put(
        @not_found_responses,
        :ok,
        {"A page of the commit's targets", "application/json", Schemas.targets(PaginationMetadata)}
      )
  )

  def list_targets(%{assigns: %{selected_project: project}} = conn, %{git_commit_sha: sha} = params) do
    project
    |> Query.targets(sha,
      page: params.page,
      page_size: params.page_size,
      search: Map.get(params, :search),
      sort_by: params.sort_by,
      sort_order: params.sort_order
    )
    |> render_read(conn)
  end

  operation(:complete_commit,
    summary: "Signal that a commit's CI pipeline finished.",
    description:
      "Tells the server that every run of the commit that gathers coverage or uploads snapshots has reported, which the data alone cannot show. The commit's coverage is republished as complete and it chains into its branch's trend, and its snapshots are marked complete. Runs landing afterwards still join the commit. Meant for a final CI job that depends on every test job (`tuist coverage complete`, or the Gradle plugin's `tuistCoverageComplete`).",
    operation_id: "completeCommitCoverage",
    parameters: @path_parameters ++ @sha_parameter,
    responses:
      Map.merge(@not_found_responses, %{
        ok: {"The commit's coverage, complete", "application/json", Schemas.commit()},
        accepted:
          {"No run of the commit gathered coverage yet: the signal is kept, and the commit's first fold publishes it complete",
           "application/json", Error}
      })
  )

  def complete_commit(%{assigns: %{selected_project: project}} = conn, %{git_commit_sha: sha}) do
    # One signal completes the commit for every feature that pools its runs.
    if FeatureFlags.snapshots_enabled?(project.account), do: Snapshots.signal_complete(project, sha)

    case Commits.signal_complete(project, sha) do
      nil ->
        conn
        |> put_status(:accepted)
        |> json(%{message: "No run of commit #{sha} gathered coverage yet; it is marked complete once one does"})

      summary ->
        json(conn, Report.commit(summary, Commits.targets(project.id, sha)))
    end
  end

  defp render_read({:ok, data}, conn), do: json(conn, data)

  defp render_read({:error, message}, conn), do: conn |> put_status(:not_found) |> json(%{message: message})
end
