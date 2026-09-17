defmodule TuistWeb.API.CoverageController do
  @moduledoc """
  Code coverage over the API: what a client needs to send a run's coverage
  when it processed the bundle itself (the inline threshold and a signed
  upload URL), and what the dashboard shows, for agents and integrations: a
  run's coverage with its targets, files and Git history, its comparison
  with the baseline (deltas, patch coverage, gaps), the branches' coverage
  and a pull request's coverage.
  """
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Environment
  alias Tuist.Storage
  alias Tuist.Tests
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.Tests.Coverage.History
  alias Tuist.Tests.Coverage.Report
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

  operation(:settings,
    summary: "Get the code coverage upload settings for a project.",
    description:
      "The size, in bytes of the DEFLATE-compressed coverage, above which a client that processed the result bundle itself uploads the coverage to object storage (see `createCoverageUpload`) instead of sending it inline with the test run.",
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
               description: "Compressed coverage larger than this goes through an upload."
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
      "Returns where to PUT the DEFLATE-compressed coverage file (one JSON object per source file, as the client's parser writes it) for a test run the client is about to create with the given id. The run then references it through `xcode_coverage_storage_key`, and the server reads it back once the run exists.",
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
               description: "The key to send with the run as `xcode_coverage_storage_key`."
             },
             upload_url: %Schema{type: :string, description: "A short-lived URL to PUT the compressed coverage to."}
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
    json(conn, %{storage_key: storage_key, upload_url: Storage.generate_upload_url(storage_key, project.account)})
  end

  @run_id_parameter [
    test_run_id: [
      in: :path,
      schema: %Schema{type: :string, format: :uuid},
      required: true,
      description: "The ID of the test run."
    ]
  ]

  @reason %Schema{
    title: "CoverageReason",
    type: :object,
    nullable: true,
    description: "Why a figure is missing: a machine-readable kind and a sentence.",
    properties: %{
      kind: %Schema{
        type: :string,
        description:
          "`no_merge_base`, `no_history`, `no_full_runs` or `no_ancestor_run` for a missing baseline; `partial_run` or `no_history` for an unavailable patch coverage."
      },
      message: %Schema{type: :string}
    },
    required: [:kind, :message]
  }

  @baseline %Schema{
    title: "CoverageBaseline",
    type: :object,
    nullable: true,
    description:
      "The newest full run of the same scheme on the base branch, at the run's merge base or the nearest ancestor of it in the project's Git history.",
    properties: %{
      test_run_id: %Schema{type: :string, format: :uuid},
      commit: %Schema{type: :string, description: "The commit the baseline run tested."},
      branch: %Schema{type: :string, description: "The base branch the baseline was taken from."},
      depth: %Schema{
        type: :integer,
        description: "How many commits before the merge base the baseline commit is (0 at the merge base)."
      },
      ran_at: %Schema{type: :string, format: :"date-time"},
      covered_lines: %Schema{type: :integer},
      executable_lines: %Schema{type: :integer},
      coverage: %Schema{type: :number, description: "Line coverage, in percent."}
    },
    required: [:test_run_id, :commit, :branch, :depth, :covered_lines, :executable_lines, :coverage]
  }

  @git_history %Schema{
    title: "TestRunGitHistory",
    type: :object,
    description: "Where the run sits in the repository's history, as the client or the VCS provider recorded it.",
    properties: %{
      base_branch: %Schema{type: :string, description: "The branch the run's commit will merge into; empty when unknown."},
      merge_base_sha: %Schema{type: :string, description: "The merge base with the base branch; empty when unknown."},
      is_pull_request: %Schema{type: :boolean},
      pull_request_number: %Schema{type: :integer, description: "0 when the run is not a pull request's."},
      git_object_format: %Schema{type: :string, description: "`sha1` or `sha256`; empty when unknown."},
      history_source: %Schema{type: :string, description: "`client`, `provider`, `mixed` or `none`."},
      history_fallback_reason: %Schema{
        type: :string,
        description: "What could not be collected, and why; empty when everything was."
      }
    },
    required: [
      :base_branch,
      :merge_base_sha,
      :is_pull_request,
      :pull_request_number,
      :git_object_format,
      :history_source,
      :history_fallback_reason
    ]
  }

  @target %Schema{
    title: "CoverageTarget",
    type: :object,
    properties: %{
      name: %Schema{type: :string},
      files_count: %Schema{type: :integer},
      covered_lines: %Schema{type: :integer},
      executable_lines: %Schema{type: :integer},
      coverage: %Schema{type: :number}
    },
    required: [:name, :files_count, :covered_lines, :executable_lines, :coverage]
  }

  @coverage_file %Schema{
    title: "CoverageFile",
    type: :object,
    properties: %{
      path: %Schema{type: :string, description: "Repository-relative path."},
      git_blob_id: %Schema{
        type: :string,
        description: "The Git blob of the file the run measured; empty when Git did not track it."
      },
      targets: %Schema{type: :array, items: %Schema{type: :string}},
      covered_lines: %Schema{type: :integer},
      executable_lines: %Schema{type: :integer},
      coverage: %Schema{type: :number}
    },
    required: [:path, :git_blob_id, :targets, :covered_lines, :executable_lines, :coverage]
  }

  @file_detail %Schema{
    title: "CoverageFileDetail",
    type: :object,
    properties:
      Map.merge(@coverage_file.properties, %{
        lines: %Schema{
          type: :array,
          description:
            "Every executable line with its execution count, as `[line, count]` pairs in line order; empty when the run has no per-line data for the file.",
          items: %Schema{type: :array, items: %Schema{type: :integer}}
        },
        uncovered_ranges: %Schema{
          type: :array,
          nullable: true,
          description:
            "Ranges of executable lines no test ran, as `[first, last]` pairs; null when the lines are unknown.",
          items: %Schema{type: :array, items: %Schema{type: :integer}}
        },
        functions: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              name: %Schema{type: :string},
              line_number: %Schema{type: :integer},
              execution_count: %Schema{type: :integer},
              covered_lines: %Schema{
                type: :integer,
                nullable: true,
                description: "Null when several shards covered the function and the union cannot be told."
              },
              executable_lines: %Schema{type: :integer}
            },
            required: [:name, :line_number, :execution_count, :executable_lines]
          }
        }
      }),
    required: @coverage_file.required ++ [:lines, :functions]
  }

  @delta_entry %Schema{
    type: :object,
    properties: %{
      covered_lines: %Schema{type: :integer, nullable: true},
      executable_lines: %Schema{type: :integer, nullable: true},
      coverage: %Schema{type: :number, nullable: true, description: "Null when only the baseline has the entry."},
      baseline_coverage: %Schema{
        type: :number,
        nullable: true,
        description: "Null when only the run has the entry, or there is no baseline."
      },
      delta: %Schema{
        type: :number,
        nullable: true,
        description: "Percentage points; null when the entry cannot be compared."
      }
    }
  }

  @patch %Schema{
    title: "PatchCoverage",
    type: :object,
    description:
      "The share of the changed executable lines the run covered, from the changed files' hunks against the merge base and the run's per-line counts.",
    properties: %{
      status: %Schema{type: :string, enum: ["available", "unavailable"]},
      reason: Map.put(@reason, :description, "Present when unavailable."),
      covered_lines: %Schema{type: :integer},
      executable_lines: %Schema{
        type: :integer,
        description: "Changed lines the compiler instrumented; 0 when the change touched no executable line."
      },
      coverage: %Schema{type: :number},
      files: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{
            path: %Schema{type: :string},
            status: %Schema{type: :string, description: "`added`, `modified` or `renamed`."},
            covered_lines: %Schema{type: :integer},
            executable_lines: %Schema{type: :integer},
            coverage: %Schema{type: :number},
            uncovered_ranges: %Schema{type: :array, items: %Schema{type: :array, items: %Schema{type: :integer}}}
          },
          required: [:path, :status, :covered_lines, :executable_lines, :coverage, :uncovered_ranges]
        }
      },
      skipped: %Schema{
        type: :array,
        description:
          "Changed files left out of the patch and why: `stale` (measured on another version of the file), `no_line_data`, `truncated` (diff too large to record) or `not_instrumented`.",
        items: %Schema{
          type: :object,
          properties: %{path: %Schema{type: :string}, reason: %Schema{type: :string}},
          required: [:path, :reason]
        }
      }
    },
    required: [:status]
  }

  @comparison %Schema{
    title: "CoverageComparison",
    type: :object,
    properties: %{
      run: %Schema{
        type: :object,
        properties: %{
          id: %Schema{type: :string, format: :uuid},
          partial: %Schema{
            type: :boolean,
            description: "Whether the run left tests out on purpose; a partial run has no total delta."
          },
          covered_lines: %Schema{type: :integer},
          executable_lines: %Schema{type: :integer},
          coverage: %Schema{type: :number}
        },
        required: [:id, :partial, :covered_lines, :executable_lines, :coverage]
      },
      baseline: @baseline,
      baseline_reason: @reason,
      total_delta: %Schema{
        type: :number,
        nullable: true,
        description: "Percentage points against the baseline; null on a partial run or without a baseline."
      },
      targets: %Schema{
        type: :array,
        items: Map.update!(@delta_entry, :properties, &Map.put(&1, :name, %Schema{type: :string}))
      },
      files: %Schema{
        type: :array,
        description:
          "Only the files whose coverage moved or that one side lacks; on a partial run only files some test executed.",
        items: Map.update!(@delta_entry, :properties, &Map.put(&1, :path, %Schema{type: :string}))
      },
      patch: @patch,
      gaps: %Schema{
        type: :array,
        description: "Changed files with executable lines in their hunks none of which ran.",
        items: %Schema{
          type: :object,
          properties: %{path: %Schema{type: :string}, executable_lines: %Schema{type: :integer}},
          required: [:path, :executable_lines]
        }
      }
    },
    required: [:run, :baseline, :baseline_reason, :total_delta, :targets, :files, :patch, :gaps]
  }

  @run_coverage %Schema{
    title: "TestRunCoverage",
    type: :object,
    properties: %{
      test_run_id: %Schema{type: :string, format: :uuid},
      scheme: %Schema{type: :string},
      git_branch: %Schema{type: :string},
      git_commit_sha: %Schema{type: :string},
      ran_at: %Schema{type: :string, format: :"date-time"},
      partial: %Schema{type: :boolean},
      covered_lines: %Schema{type: :integer},
      executable_lines: %Schema{type: :integer},
      coverage: %Schema{type: :number, description: "Line coverage over the run's product files, in percent."},
      execution_mode: %Schema{type: :string, description: "`parallel`, `serial`, or empty when unknown."},
      targets: %Schema{type: :array, items: @target},
      git_history: @git_history,
      baseline: @baseline,
      baseline_reason: @reason
    },
    required: [
      :test_run_id,
      :scheme,
      :git_branch,
      :git_commit_sha,
      :partial,
      :covered_lines,
      :executable_lines,
      :coverage,
      :targets,
      :git_history,
      :baseline,
      :baseline_reason
    ]
  }

  @pagination %Schema{
    type: :object,
    properties: %{
      current_page: %Schema{type: :integer},
      page_size: %Schema{type: :integer},
      total_count: %Schema{type: :integer},
      total_pages: %Schema{type: :integer}
    },
    required: [:current_page, :page_size, :total_count, :total_pages]
  }

  @not_found_responses %{
    unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
    forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
    not_found: {"The run was not found, or gathered no coverage", "application/json", Error}
  }

  operation(:show_run,
    summary: "Get a test run's code coverage.",
    description:
      "The run's line coverage over its product files (test code is excluded), its targets least covered first, where the run sits in Git history, and its baseline (the newest full run of the same scheme on the base branch at the merge base or the nearest ancestor of it) or why there is none.",
    operation_id: "getTestRunCoverage",
    parameters: @path_parameters ++ @run_id_parameter,
    responses: Map.put(@not_found_responses, :ok, {"The run's coverage", "application/json", @run_coverage})
  )

  def show_run(%{assigns: %{selected_project: project}} = conn, %{test_run_id: test_run_id}) do
    with_run_coverage(conn, test_run_id, fn run, summary -> json(conn, Report.run(project, run, summary)) end)
  end

  operation(:list_run_files,
    summary: "List a test run's files with their coverage, least covered first.",
    operation_id: "listTestRunCoverageFiles",
    parameters:
      @path_parameters ++
        @run_id_parameter ++
        [
          page: [in: :query, type: :integer, required: false, description: "The page number, starting at 1."],
          page_size: [
            in: :query,
            type: :integer,
            required: false,
            description: "Files per page (default 20, at most 100)."
          ]
        ],
    responses:
      Map.put(
        @not_found_responses,
        :ok,
        {"The files", "application/json",
         %Schema{
           title: "TestRunCoverageFiles",
           type: :object,
           properties: %{files: %Schema{type: :array, items: @coverage_file}, pagination_metadata: @pagination},
           required: [:files, :pagination_metadata]
         }}
      )
  )

  def list_run_files(%{assigns: %{selected_project: project}} = conn, %{test_run_id: test_run_id} = params) do
    page = max(Map.get(params, :page) || 1, 1)
    page_size = params |> Map.get(:page_size) |> Kernel.||(20) |> max(1) |> min(100)

    with_run_coverage(conn, test_run_id, fn run, _summary ->
      {files, count} = Coverage.list_files(project.id, run.id, page, page_size)

      json(conn, %{
        files: Enum.map(files, &Report.file/1),
        pagination_metadata: %{
          current_page: page,
          page_size: page_size,
          total_count: count,
          total_pages: max(1, ceil(count / page_size))
        }
      })
    end)
  end

  operation(:show_run_file,
    summary: "Get one file's coverage in a test run, line by line.",
    operation_id: "getTestRunCoverageFile",
    parameters:
      @path_parameters ++
        @run_id_parameter ++
        [path: [in: :query, type: :string, required: true, description: "The file's repository-relative path."]],
    responses: Map.put(@not_found_responses, :ok, {"The file's coverage", "application/json", @file_detail})
  )

  def show_run_file(%{assigns: %{selected_project: project}} = conn, %{test_run_id: test_run_id, path: path}) do
    with_run_coverage(conn, test_run_id, fn run, _summary ->
      case Coverage.file_detail(project.id, run.id, path) do
        nil -> not_found(conn, "The run has no coverage for #{path}")
        detail -> json(conn, Report.file_detail(detail))
      end
    end)
  end

  operation(:show_run_comparison,
    summary: "Compare a test run's coverage with its baseline.",
    description:
      "The total delta (full runs only), the per-target and per-file deltas, the patch coverage of the changed lines with the files not counted and why, and the gaps: changed files no test executed. When no baseline can be resolved the comparison says why instead of comparing with another run.",
    operation_id: "getTestRunCoverageComparison",
    parameters: @path_parameters ++ @run_id_parameter,
    responses: Map.put(@not_found_responses, :ok, {"The comparison", "application/json", @comparison})
  )

  def show_run_comparison(%{assigns: %{selected_project: project}} = conn, %{test_run_id: test_run_id}) do
    with_run_coverage(conn, test_run_id, fn run, summary ->
      json(conn, Report.comparison(Comparison.compare(project, run, run_summary: summary)))
    end)
  end

  operation(:list_branches,
    summary: "List every branch's newest full-run coverage.",
    description:
      "For the given scheme (by default the one with most full runs on the default branch), every branch with a full run in the period, newest first, with its difference from the default branch in percentage points.",
    operation_id: "listCoverageBranches",
    parameters:
      @path_parameters ++
        [
          scheme: [
            in: :query,
            type: :string,
            required: false,
            description: "The scheme to report; figures are never pooled across schemes."
          ],
          days: [in: :query, type: :integer, required: false, description: "How many days back to look (default 30)."]
        ],
    responses: %{
      ok:
        {"The branches", "application/json",
         %Schema{
           title: "CoverageBranches",
           type: :object,
           properties: %{
             scheme: %Schema{
               type: :string,
               nullable: true,
               description: "The scheme reported; null when no full run exists."
             },
             branches: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   git_branch: %Schema{type: :string},
                   test_run_id: %Schema{type: :string, format: :uuid},
                   git_commit_sha: %Schema{type: :string},
                   ran_at: %Schema{type: :string, format: :"date-time"},
                   covered_lines: %Schema{type: :integer},
                   executable_lines: %Schema{type: :integer},
                   coverage: %Schema{type: :number},
                   delta: %Schema{
                     type: :number,
                     nullable: true,
                     description: "Against the default branch's newest full run; null when it has none."
                   }
                 },
                 required: [
                   :git_branch,
                   :test_run_id,
                   :git_commit_sha,
                   :ran_at,
                   :covered_lines,
                   :executable_lines,
                   :coverage,
                   :delta
                 ]
               }
             }
           },
           required: [:scheme, :branches]
         }},
      unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
      forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
      not_found: {"The project was not found", "application/json", Error}
    }
  )

  def list_branches(%{assigns: %{selected_project: project}} = conn, params) do
    days = params |> Map.get(:days) |> Kernel.||(30) |> max(1)
    opts = [since: NaiveDateTime.add(NaiveDateTime.utc_now(), -days, :day)]

    scheme =
      Map.get(params, :scheme) ||
        case History.schemes(project.id, project.default_branch, opts) do
          [%{scheme: scheme} | _] -> scheme
          [] -> nil
        end

    branches = if scheme, do: History.branches(project, scheme, opts), else: []
    json(conn, %{scheme: scheme, branches: Enum.map(branches, &Report.branch/1)})
  end

  operation(:show_pull_request,
    summary: "Get a pull request's code coverage against its baseline.",
    description:
      "Every run of the pull request that gathered coverage, newest first, and the comparison of one of them (the newest, or `test_run_id`) with its baseline: deltas, patch coverage and gaps.",
    operation_id: "getPullRequestCoverage",
    parameters:
      @path_parameters ++
        [
          pull_request_number: [in: :path, type: :integer, required: true, description: "The pull request number."],
          test_run_id: [
            in: :query,
            schema: %Schema{type: :string, format: :uuid},
            required: false,
            description: "The run to compare; the newest by default."
          ]
        ],
    responses:
      Map.put(
        @not_found_responses,
        :ok,
        {"The pull request's coverage", "application/json",
         %Schema{
           title: "PullRequestCoverage",
           type: :object,
           properties: %{
             pull_request_number: %Schema{type: :integer},
             runs: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   test_run_id: %Schema{type: :string, format: :uuid},
                   scheme: %Schema{type: :string},
                   git_branch: %Schema{type: :string},
                   base_branch: %Schema{type: :string},
                   git_commit_sha: %Schema{type: :string},
                   ran_at: %Schema{type: :string, format: :"date-time"},
                   partial: %Schema{type: :boolean},
                   covered_lines: %Schema{type: :integer},
                   executable_lines: %Schema{type: :integer},
                   coverage: %Schema{type: :number}
                 },
                 required: [
                   :test_run_id,
                   :scheme,
                   :git_branch,
                   :base_branch,
                   :git_commit_sha,
                   :ran_at,
                   :partial,
                   :covered_lines,
                   :executable_lines,
                   :coverage
                 ]
               }
             },
             comparison: @comparison
           },
           required: [:pull_request_number, :runs, :comparison]
         }}
      )
  )

  def show_pull_request(%{assigns: %{selected_project: project}} = conn, %{pull_request_number: number} = params) do
    runs = History.pull_request_runs(project.id, number)
    selected = Enum.find(runs, List.first(runs), &(&1.test_run_id == Map.get(params, :test_run_id)))

    with false <- is_nil(selected),
         {:ok, run} <- Tests.get_test(selected.test_run_id) do
      summary = %{
        partial: selected.partial,
        covered_lines: selected.covered_lines,
        executable_lines: selected.executable_lines
      }

      json(conn, %{
        pull_request_number: number,
        runs: Enum.map(runs, &Report.pull_request_run/1),
        comparison: Report.comparison(Comparison.compare(project, run, run_summary: summary))
      })
    else
      _ -> not_found(conn, "No test run of pull request ##{number} gathered coverage")
    end
  end

  defp with_run_coverage(%{assigns: %{selected_project: project}} = conn, test_run_id, fun) do
    with {:ok, %{project_id: project_id} = run} when project_id == project.id <- Tests.get_test(test_run_id),
         summary when not is_nil(summary) <- Coverage.run_summary(project.id, run.id) do
      fun.(run, summary)
    else
      nil -> not_found(conn, "The test run gathered no coverage")
      _ -> not_found(conn, "The test run was not found")
    end
  end

  defp not_found(conn, message) do
    conn |> put_status(:not_found) |> json(%{message: message})
  end
end
