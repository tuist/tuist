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
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.Tests.Coverage.Evidence
  alias Tuist.Tests.Coverage.History
  alias Tuist.Tests.Coverage.Report
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
          "`no_history`, `no_merge_base`, `no_measured_commits`, `no_ancestor_commit`, `measured_set_mismatch` or `dirty_checkout` for a missing baseline; `no_history` or `dirty_checkout` for an unavailable patch coverage."
      },
      message: %Schema{type: :string}
    },
    required: [:kind, :message]
  }

  @reported %Schema{
    title: "CoverageReported",
    type: :object,
    nullable: true,
    description:
      "What the commit is covered by once the tests its runs skipped are carried forward from the ancestor they last ran at. A test is carried only when it passed there and every file it executed, and every tracked file, is unchanged. Null for a commit published before reported coverage existed.",
    properties: %{
      kind: %Schema{
        type: :string,
        enum: ["measured", "reported", "partial", "observed"],
        description:
          "`measured`: the runs skipped nothing. `reported`: every skipped test was carried, so this is what a full run would measure. `partial`: some skipped tests or files could not be carried, and the figure is a lower bound. `observed`: the runs listed no candidate tests, so what they skipped is unknown."
      },
      coverage: %Schema{type: :number},
      covered_lines: %Schema{type: :integer},
      executable_lines: %Schema{type: :integer},
      skipped_tests_count: %Schema{type: :integer, description: "The candidate tests no run of the commit executed."},
      carried_tests_count: %Schema{type: :integer, description: "Those of them whose coverage was carried forward."},
      gap_files_count: %Schema{
        type: :integer,
        description:
          "Files an ancestor measured that the commit's runs did not compile and whose coverage could not be carried."
      },
      carried_from: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "The commits the carried coverage was observed at."
      }
    },
    required: [
      :kind,
      :coverage,
      :covered_lines,
      :executable_lines,
      :skipped_tests_count,
      :carried_tests_count,
      :gap_files_count,
      :carried_from
    ]
  }

  @measured_set_properties %{
    schemes: %Schema{type: :array, items: %Schema{type: :string}, description: "The schemes that measured the commit."},
    partial_schemes: %Schema{
      type: :array,
      items: %Schema{type: :string},
      description: "The schemes only measured by runs that skipped tests on purpose."
    },
    complete: %Schema{
      type: :boolean,
      description: "Whether the commit's coverage pipeline is known to have finished (`completeness` says how)."
    },
    test_run_ids: %Schema{type: :array, items: %Schema{type: :string, format: :uuid}}
  }

  @baseline %Schema{
    title: "CoverageBaseline",
    type: :object,
    nullable: true,
    description:
      "The nearest measured ancestor of the commit's merge base with its base branch (for a commit on the base branch, of its first parent), walked first-parent through the repository's Git history, that measured the same schemes.",
    properties:
      Map.merge(@measured_set_properties, %{
        commit: %Schema{type: :string, description: "The baseline commit."},
        branch: %Schema{type: :string, description: "The base branch the baseline was taken from."},
        depth: %Schema{
          type: :integer,
          description: "How many commits before the start of the walk the baseline commit is (0 at the merge base)."
        },
        measured_at: %Schema{type: :string, format: :"date-time"},
        covered_lines: %Schema{type: :integer},
        executable_lines: %Schema{type: :integer},
        coverage: %Schema{type: :number, description: "Line coverage, in percent."}
      }),
    required: [
      :commit,
      :branch,
      :depth,
      :covered_lines,
      :executable_lines,
      :coverage,
      :schemes,
      :partial_schemes,
      :complete
    ]
  }

  @git_history %Schema{
    title: "TestRunGitHistory",
    type: :object,
    description: "Where the run sits in the repository's history, as the client or the VCS provider recorded it.",
    properties: %{
      git_dirty: %Schema{
        type: :boolean,
        description:
          "Whether the checkout had uncommitted changes: the run then measured code that is not the commit's and stays at run level, never joining the commit's coverage."
      },
      base_branch: %Schema{type: :string, description: "The branch the run's commit will merge into; empty when unknown."},
      merge_base_sha: %Schema{type: :string, description: "The merge base with the base branch; empty when unknown."},
      is_pull_request: %Schema{type: :boolean},
      pull_request_number: %Schema{type: :integer, description: "0 when the run is not a pull request's."},
      git_object_format: %Schema{type: :string, description: "`sha1` or `sha256`; empty when unknown."},
      history_source: %Schema{type: :string, description: "`client`, `provider`, `mixed` or `none`."},
      history_fallback_reason: %Schema{
        type: :string,
        description: "What could not be collected, and why; empty when everything was."
      },
      tracked_files_count: %Schema{
        type: :integer,
        description:
          "How many files of the commit's listing the project's tracked-file globs match (dependency manifests, generator configuration, fixtures, snapshots)."
      },
      commit_files_listed: %Schema{
        type: :boolean,
        description: "Whether the commit's file listing (every tracked file with its blob) is stored."
      }
    },
    required: [
      :git_dirty,
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
          "Changed files left out of the patch and why: `stale` (measured on another version of the file), `no_line_data`, `truncated` (diff too large to record), `not_instrumented` or `excluded` (matched by the project's excluded paths).",
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
      commit: %Schema{
        type: :object,
        description: "The commit's coverage: the union of every run that measured it.",
        properties: %{
          sha: %Schema{type: :string, description: "Empty for a run without a commit, described alone."},
          partial: %Schema{
            type: :boolean,
            description:
              "Whether any scheme was only measured by runs that skipped tests; there is then a total delta only when `reported` carried everything they skipped."
          },
          covered_lines: %Schema{type: :integer},
          executable_lines: %Schema{type: :integer},
          coverage: %Schema{type: :number},
          schemes: %Schema{type: :array, items: %Schema{type: :string}},
          partial_schemes: %Schema{type: :array, items: %Schema{type: :string}},
          complete: %Schema{type: :boolean},
          completeness: %Schema{type: :string, description: "`signal`, `inferred` or empty."},
          reported: @reported
        },
        required: [:sha, :partial, :covered_lines, :executable_lines, :coverage, :schemes, :partial_schemes]
      },
      baseline: @baseline,
      baseline_reason: @reason,
      total_delta: %Schema{
        type: :number,
        nullable: true,
        description:
          "Percentage points against the baseline; null when the commit measured a scheme partially, the baseline measured a different set of schemes, or there is no baseline."
      },
      schemes: %Schema{
        type: :array,
        description:
          "Each scheme's own total at the commit and at the baseline: two schemes measure different slices, so only matching sets compare as a whole.",
        items: %Schema{
          type: :object,
          properties: %{
            scheme: %Schema{type: :string},
            partial: %Schema{type: :boolean, nullable: true},
            covered_lines: %Schema{type: :integer, nullable: true},
            executable_lines: %Schema{type: :integer, nullable: true},
            coverage: %Schema{
              type: :number,
              nullable: true,
              description: "Null when only the baseline measured the scheme."
            },
            baseline_coverage: %Schema{type: :number, nullable: true},
            delta: %Schema{type: :number, nullable: true, description: "Null when either side is partial or missing."}
          },
          required: [:scheme, :coverage, :baseline_coverage, :delta]
        }
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
    required: [:commit, :baseline, :baseline_reason, :total_delta, :schemes, :targets, :files, :patch, :gaps]
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

  @commit_coverage %Schema{
    title: "CommitCoverage",
    type: :object,
    description: "A commit's coverage: the union of every run that measured it, its measured set and its baseline.",
    properties:
      Map.merge(@measured_set_properties, %{
        git_commit_sha: %Schema{type: :string},
        covered_lines: %Schema{type: :integer},
        executable_lines: %Schema{type: :integer},
        coverage: %Schema{type: :number, description: "Line coverage over the measured product files, in percent."},
        measured_files_count: %Schema{type: :integer, description: "Product files some run measured."},
        unmeasured_files_count: %Schema{
          type: :integer,
          description:
            "Source files of the commit's listing (of the kinds the runs measured, minus the excluded paths) that no run measured, shown in the dashboard as \"Files without coverage data\"; 0 when the listing is not stored."
        },
        partial: %Schema{type: :boolean},
        completeness: %Schema{type: :string, description: "`signal`, `inferred` or empty."},
        reported: @reported,
        measured_at: %Schema{type: :string, format: :"date-time"},
        targets: %Schema{type: :array, items: @target},
        baseline: @baseline,
        baseline_reason: @reason
      }),
    required: [
      :git_commit_sha,
      :covered_lines,
      :executable_lines,
      :coverage,
      :measured_files_count,
      :unmeasured_files_count,
      :schemes,
      :partial_schemes,
      :partial,
      :complete,
      :completeness,
      :test_run_ids,
      :targets,
      :baseline,
      :baseline_reason
    ]
  }

  @measurement_properties Map.merge(@measured_set_properties, %{
                            git_commit_sha: %Schema{type: :string},
                            covered_lines: %Schema{type: :integer},
                            executable_lines: %Schema{type: :integer},
                            coverage: %Schema{type: :number},
                            partial: %Schema{type: :boolean},
                            completeness: %Schema{type: :string},
                            measured_at: %Schema{type: :string, format: :"date-time", nullable: true}
                          })

  @history_commit %Schema{
    title: "CoverageHistoryCommit",
    type: :object,
    description:
      "A commit of a branch's history, newest first, measured or not. A measured commit chains into the trend when it is complete or measured the same schemes as the previous chained one.",
    properties:
      Map.merge(@measurement_properties, %{
        depth: %Schema{type: :integer, description: "Commits from the branch's head (0 at the head)."},
        committed_at: %Schema{type: :string, format: :"date-time", nullable: true},
        measured: %Schema{type: :boolean},
        chained: %Schema{type: :boolean}
      }),
    required: [:git_commit_sha, :depth, :measured, :chained]
  }

  @branch %Schema{
    title: "CoverageBranch",
    type: :object,
    description: "A branch's head commit measurement and its difference from the default branch.",
    properties:
      Map.merge(@measurement_properties, %{
        git_branch: %Schema{type: :string},
        chained: %Schema{type: :boolean},
        ordered_by: %Schema{
          type: :string,
          enum: ["graph", "time"],
          description:
            "Whether the branch's commits come from the Git graph or, without a recorded head, from the runs' time order."
        },
        delta: %Schema{
          type: :number,
          nullable: true,
          description: "Percentage points against the default branch's head; null when either side is unchained."
        }
      }),
    required: [:git_branch, :git_commit_sha, :covered_lines, :executable_lines, :coverage, :chained, :ordered_by, :delta]
  }

  @pull_request_commit %Schema{
    title: "PullRequestCoverageCommit",
    type: :object,
    properties:
      Map.merge(@measurement_properties, %{
        git_branch: %Schema{type: :string},
        base_branch: %Schema{type: :string},
        ran_at: %Schema{type: :string, format: :"date-time", nullable: true}
      }),
    required: [:git_commit_sha, :git_branch, :base_branch, :covered_lines, :executable_lines, :coverage, :complete]
  }

  @sha_parameter [
    git_commit_sha: [in: :path, type: :string, required: true, description: "The commit SHA."]
  ]

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
    not_found: {"The run or commit was not found, or gathered no coverage", "application/json", Error}
  }

  operation(:show_run,
    summary: "Get a test run's code coverage.",
    description:
      "The run's line coverage over its product files (test code is excluded), its targets least covered first, where the run sits in Git history, and its commit's baseline or why there is none. A run is one measurement of its commit; `getCommitCoverage` has the commit's union.",
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
    summary: "Compare a test run's commit with its baseline.",
    description:
      "The comparison of the run's commit (the union of every run that measured it) with its baseline: the total delta when both measured the same schemes fully, each scheme's own totals, the per-target and per-file deltas, the patch coverage of the changed lines with the files not counted and why, and the gaps: changed files no test executed. When no baseline can be resolved the comparison says why instead of comparing with another commit. A run without a commit is described alone.",
    operation_id: "getTestRunCoverageComparison",
    parameters: @path_parameters ++ @run_id_parameter,
    responses: Map.put(@not_found_responses, :ok, {"The comparison", "application/json", @comparison})
  )

  def show_run_comparison(%{assigns: %{selected_project: project}} = conn, %{test_run_id: test_run_id}) do
    with_run_coverage(conn, test_run_id, fn run, summary ->
      json(conn, Report.comparison(Comparison.compare(project, run, run_summary: summary)))
    end)
  end

  @evidence_summary %Schema{
    title: "TestRunCoverageEvidenceSummary",
    type: :object,
    description: "How much of the run has per-test coverage evidence.",
    properties: %{
      tests: %Schema{type: :integer, description: "Tests with evidence of their own."},
      tests_without_evidence: %Schema{
        type: :integer,
        description:
          "Tests that ran without evidence of their own (Swift Testing without the trait, or overlapping another test): their target's evidence is all they have."
      },
      suites: %Schema{type: :integer, description: "Suites with activity around their tests that belongs to none."},
      targets: %Schema{type: :integer, description: "Test targets with evidence: the floor for each of their tests."},
      files: %Schema{type: :integer, description: "Files some scope covers."},
      median_files_per_test: %Schema{type: :integer},
      max_files_per_test: %Schema{type: :integer}
    },
    required: [:tests, :tests_without_evidence, :suites, :targets, :files, :median_files_per_test, :max_files_per_test]
  }

  operation(:show_run_evidence,
    summary: "Get a test run's per-test coverage evidence.",
    description:
      "Which files each test of the run executed, as the client's coverage observer recorded it: what test selection plans over. Returns how much of the run has evidence and a page of its scopes of one kind, those covering most files first.",
    operation_id: "getTestRunCoverageEvidence",
    parameters:
      @path_parameters ++
        @run_id_parameter ++
        [
          kind: [
            in: :query,
            schema: %Schema{type: :string, enum: ["test", "suite", "target"], default: "test"},
            required: false,
            description: "The scopes to list."
          ],
          page: [in: :query, type: :integer, required: false, description: "The page number, starting at 1."],
          page_size: [
            in: :query,
            type: :integer,
            required: false,
            description: "Scopes per page (default 50, at most 500)."
          ]
        ],
    responses:
      Map.put(
        @not_found_responses,
        :ok,
        {"The evidence", "application/json",
         %Schema{
           title: "TestRunCoverageEvidence",
           type: :object,
           properties: %{
             summary: @evidence_summary,
             scopes: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   kind: %Schema{type: :string, enum: ["test", "suite", "target"]},
                   scope_id: %Schema{
                     type: :string,
                     description: "`Module/Suite/name` for a test, `Module/Suite` for a suite, `Module` for a target."
                   },
                   files_count: %Schema{type: :integer}
                 },
                 required: [:kind, :scope_id, :files_count]
               }
             },
             pagination_metadata: @pagination
           },
           required: [:summary, :scopes, :pagination_metadata]
         }}
      )
  )

  def show_run_evidence(conn, %{test_run_id: test_run_id} = params) do
    page = max(Map.get(params, :page) || 1, 1)
    page_size = params |> Map.get(:page_size) |> Kernel.||(50) |> max(1) |> min(500)
    kind = Map.get(params, :kind) || "test"

    with_run_evidence(conn, test_run_id, fn run, summary ->
      {scopes, count} = Evidence.list_scopes(run, kind: kind, page: page, page_size: page_size)

      json(conn, %{
        summary: summary,
        scopes: Enum.map(scopes, &%{kind: &1.scope_kind, scope_id: &1.scope_id, files_count: &1.files_count}),
        pagination_metadata: %{
          current_page: page,
          page_size: page_size,
          total_count: count,
          total_pages: max(1, ceil(count / page_size))
        }
      })
    end)
  end

  operation(:list_run_evidence_files,
    summary: "List the files a test's coverage evidence holds.",
    description:
      "The files the test executed, then those its suite ran around its tests, then the rest of its target's: each file by the narrowest scope that holds it. A test without evidence of its own still gets its suite's and its target's.",
    operation_id: "listTestRunCoverageEvidenceFiles",
    parameters:
      @path_parameters ++
        @run_id_parameter ++
        [
          module: [in: :query, type: :string, required: true, description: "The test target."],
          suite: [in: :query, type: :string, required: false, description: "The test's suite; empty outside any."],
          name: [in: :query, type: :string, required: true, description: "The test's name, `testExample()`."]
        ],
    responses:
      Map.put(
        @not_found_responses,
        :ok,
        {"The files", "application/json",
         %Schema{
           title: "TestRunCoverageEvidenceFiles",
           type: :object,
           properties: %{
             files: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   path: %Schema{type: :string},
                   scope: %Schema{type: :string, enum: ["test", "suite", "target"]},
                   git_blob_id: %Schema{
                     type: :string,
                     description: "The file's Git blob in the run's own coverage; empty when the run has none for it."
                   }
                 },
                 required: [:path, :scope, :git_blob_id]
               }
             }
           },
           required: [:files]
         }}
      )
  )

  def list_run_evidence_files(conn, %{test_run_id: test_run_id, module: module_name, name: name} = params) do
    with_run_evidence(conn, test_run_id, fn run, _summary ->
      files = Evidence.files(run, module_name, Map.get(params, :suite) || "", name)
      json(conn, %{files: Enum.map(files, &Map.update!(&1, :git_blob_id, fn blob -> blob || "" end))})
    end)
  end

  operation(:list_run_evidence_tests,
    summary: "List the tests of a run whose coverage evidence holds a file.",
    description:
      "The tests that executed the file, by their own evidence. `suites` and `targets` name the wider scopes that hold it: every test of those may depend on the file too.",
    operation_id: "listTestRunCoverageEvidenceTests",
    parameters:
      @path_parameters ++
        @run_id_parameter ++
        [path: [in: :query, type: :string, required: true, description: "The file's repository-relative path."]],
    responses:
      Map.put(
        @not_found_responses,
        :ok,
        {"The tests", "application/json",
         %Schema{
           title: "TestRunCoverageEvidenceTests",
           type: :object,
           properties: %{
             tests: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   test_case_id: %Schema{type: :string, format: :uuid},
                   module_name: %Schema{type: :string},
                   suite_name: %Schema{type: :string},
                   name: %Schema{type: :string}
                 },
                 required: [:test_case_id, :module_name, :suite_name, :name]
               }
             },
             suites: %Schema{type: :array, items: %Schema{type: :string}},
             targets: %Schema{type: :array, items: %Schema{type: :string}}
           },
           required: [:tests, :suites, :targets]
         }}
      )
  )

  def list_run_evidence_tests(conn, %{test_run_id: test_run_id, path: path}) do
    with_run_evidence(conn, test_run_id, fn run, _summary -> json(conn, Evidence.covering(run, path)) end)
  end

  operation(:show_commit,
    summary: "Get a commit's code coverage.",
    description:
      "The commit's line coverage as the union of every run that measured it (a line is covered when any run covered it; a file counts once however many schemes compiled it), which schemes measured it and which only partially, whether its coverage pipeline signalled completion, its targets least covered first, and its baseline or why there is none.",
    operation_id: "getCommitCoverage",
    parameters: @path_parameters ++ @sha_parameter,
    responses: Map.put(@not_found_responses, :ok, {"The commit's coverage", "application/json", @commit_coverage})
  )

  def show_commit(%{assigns: %{selected_project: project}} = conn, %{git_commit_sha: sha}) do
    with_commit_coverage(conn, sha, fn summary ->
      json(conn, Report.commit(project, summary, Commits.targets(project.id, sha)))
    end)
  end

  operation(:list_commit_files,
    summary: "List a commit's files with their coverage, least covered first.",
    operation_id: "listCommitCoverageFiles",
    parameters:
      @path_parameters ++
        @sha_parameter ++
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
           title: "CommitCoverageFiles",
           type: :object,
           properties: %{files: %Schema{type: :array, items: @coverage_file}, pagination_metadata: @pagination},
           required: [:files, :pagination_metadata]
         }}
      )
  )

  def list_commit_files(%{assigns: %{selected_project: project}} = conn, %{git_commit_sha: sha} = params) do
    page = max(Map.get(params, :page) || 1, 1)
    page_size = params |> Map.get(:page_size) |> Kernel.||(20) |> max(1) |> min(100)

    with_commit_coverage(conn, sha, fn _summary ->
      {files, count} = Commits.list_files(project.id, sha, page, page_size)

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

  operation(:show_commit_file,
    summary: "Get one file's coverage at a commit, line by line, merged across the runs that measured it.",
    operation_id: "getCommitCoverageFile",
    parameters:
      @path_parameters ++
        @sha_parameter ++
        [path: [in: :query, type: :string, required: true, description: "The file's repository-relative path."]],
    responses: Map.put(@not_found_responses, :ok, {"The file's coverage", "application/json", @file_detail})
  )

  def show_commit_file(%{assigns: %{selected_project: project}} = conn, %{git_commit_sha: sha, path: path}) do
    with_commit_coverage(conn, sha, fn _summary ->
      case Commits.file_detail(project.id, sha, path) do
        nil -> not_found(conn, "The commit has no coverage for #{path}")
        detail -> json(conn, Report.file_detail(detail))
      end
    end)
  end

  operation(:show_commit_comparison,
    summary: "Compare a commit's coverage with its baseline.",
    description:
      "The commit against the nearest measured ancestor of its merge base with the base branch (its first parent for a commit on the base branch): the total delta when both measured the same schemes fully, each scheme's own totals, the per-target and per-file deltas, the patch coverage of the changed lines with the files not counted and why, and the gaps. When no baseline can be resolved the comparison says why instead of comparing with another commit.",
    operation_id: "getCommitCoverageComparison",
    parameters: @path_parameters ++ @sha_parameter,
    responses: Map.put(@not_found_responses, :ok, {"The comparison", "application/json", @comparison})
  )

  def show_commit_comparison(%{assigns: %{selected_project: project}} = conn, %{git_commit_sha: sha}) do
    with_commit_coverage(conn, sha, fn _summary ->
      json(conn, Report.comparison(Comparison.compare(project, Comparison.from_commit(project, sha))))
    end)
  end

  operation(:complete_commit,
    summary: "Signal that a commit's coverage pipeline finished.",
    description:
      "Tells the server that every run of the commit that gathers coverage has reported, which the data alone cannot show. The commit's coverage is republished as complete, it chains into its branch's trend, and the pull request's `tuist/coverage` check run, pending until now, gets its verdict. Runs landing afterwards join the commit's coverage but leave the check as it was. Meant for a final CI job that depends on every test job (`tuist coverage complete`).",
    operation_id: "completeCommitCoverage",
    parameters: @path_parameters ++ @sha_parameter,
    responses:
      Map.put(
        @not_found_responses,
        :ok,
        {"The commit's coverage, complete", "application/json", @commit_coverage}
      )
  )

  def complete_commit(%{assigns: %{selected_project: project}} = conn, %{git_commit_sha: sha}) do
    case Commits.signal_complete(project, sha) do
      nil -> not_found(conn, "No run of commit #{sha} gathered coverage")
      summary -> json(conn, Report.commit(project, summary, Commits.targets(project.id, sha)))
    end
  end

  operation(:list_history,
    summary: "List a branch's commits with their coverage, newest first.",
    description:
      "The commits of the branch from the repository's Git graph (first-parent from the recorded head; without a head, the measured commits labelled with the branch in time order), measured or not, so a drop between two measured commits is attributed to the unmeasured ones between them rather than to the later one. A measured commit chains into the trend when its pipeline signalled completion or it measured the same schemes as the previous chained commit.",
    operation_id: "listCoverageHistory",
    parameters:
      @path_parameters ++
        [
          branch: [in: :query, type: :string, required: false, description: "The branch; the default branch by default."],
          days: [in: :query, type: :integer, required: false, description: "How many days back to look (default 30)."],
          limit: [
            in: :query,
            type: :integer,
            required: false,
            description: "How many commits, from the head (default 100, at most 500)."
          ]
        ],
    responses:
      Map.put(
        @not_found_responses,
        :ok,
        {"The commits", "application/json",
         %Schema{
           title: "CoverageHistory",
           type: :object,
           properties: %{
             branch: %Schema{type: :string},
             ordered_by: %Schema{type: :string, enum: ["graph", "time"]},
             commits: %Schema{type: :array, items: @history_commit}
           },
           required: [:branch, :ordered_by, :commits]
         }}
      )
  )

  def list_history(%{assigns: %{selected_project: project}} = conn, params) do
    branch = Map.get(params, :branch) || project.default_branch
    days = params |> Map.get(:days) |> Kernel.||(30) |> max(1)
    limit = params |> Map.get(:limit) |> Kernel.||(100) |> max(1) |> min(500)

    history =
      History.branch_history(project, branch,
        since: NaiveDateTime.add(NaiveDateTime.utc_now(), -days, :day),
        limit: limit
      )

    json(conn, %{
      branch: branch,
      ordered_by: Atom.to_string(history.ordered_by),
      commits: Enum.map(history.commits, &Report.history_commit/1)
    })
  end

  operation(:list_branches,
    summary: "List every branch's head coverage.",
    description:
      "Every branch with a measured commit in the period, newest first, with its head commit's coverage (the union of the runs that measured it), the schemes that measured it, and its difference from the default branch's head in percentage points when both chain into their trends.",
    operation_id: "listCoverageBranches",
    parameters:
      @path_parameters ++
        [days: [in: :query, type: :integer, required: false, description: "How many days back to look (default 30)."]],
    responses:
      Map.put(
        @not_found_responses,
        :ok,
        {"The branches", "application/json",
         %Schema{
           title: "CoverageBranches",
           type: :object,
           properties: %{branches: %Schema{type: :array, items: @branch}},
           required: [:branches]
         }}
      )
  )

  def list_branches(%{assigns: %{selected_project: project}} = conn, params) do
    days = params |> Map.get(:days) |> Kernel.||(30) |> max(1)
    branches = History.branches(project, since: NaiveDateTime.add(NaiveDateTime.utc_now(), -days, :day))
    json(conn, %{branches: Enum.map(branches, &Report.branch/1)})
  end

  operation(:show_pull_request,
    summary: "Get a pull request's code coverage against its baseline.",
    description:
      "Every commit of the pull request that gathered coverage, newest first, and the comparison of one of them (the newest, or `git_commit_sha`) with its baseline: deltas, patch coverage and gaps.",
    operation_id: "getPullRequestCoverage",
    parameters:
      @path_parameters ++
        [
          pull_request_number: [in: :path, type: :integer, required: true, description: "The pull request number."],
          git_commit_sha: [
            in: :query,
            type: :string,
            required: false,
            description: "The commit to compare; the newest by default."
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
             commits: %Schema{type: :array, items: @pull_request_commit},
             comparison: @comparison
           },
           required: [:pull_request_number, :commits, :comparison]
         }}
      )
  )

  def show_pull_request(%{assigns: %{selected_project: project}} = conn, %{pull_request_number: number} = params) do
    commits = History.pull_request_commits(project.id, number)
    selected = Enum.find(commits, List.first(commits), &(&1.git_commit_sha == Map.get(params, :git_commit_sha)))

    case selected do
      nil ->
        not_found(conn, "No test run of pull request ##{number} gathered coverage")

      selected ->
        json(conn, %{
          pull_request_number: number,
          commits: Enum.map(commits, &Report.pull_request_commit/1),
          comparison:
            Report.comparison(Comparison.compare(project, Comparison.from_commit(project, selected.git_commit_sha)))
        })
    end
  end

  defp with_commit_coverage(%{assigns: %{selected_project: project}} = conn, sha, fun) do
    case Commits.summary(project.id, sha) do
      nil -> not_found(conn, "No run of commit #{sha} gathered coverage")
      summary -> fun.(summary)
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

  defp with_run_evidence(%{assigns: %{selected_project: project}} = conn, test_run_id, fun) do
    with {:ok, %{project_id: project_id} = run} when project_id == project.id <- Tests.get_test(test_run_id),
         summary when not is_nil(summary) <- Evidence.summary(run) do
      fun.(run, summary)
    else
      nil -> not_found(conn, "The test run gathered no coverage evidence")
      _ -> not_found(conn, "The test run was not found")
    end
  end

  defp not_found(conn, message) do
    conn |> put_status(:not_found) |> json(%{message: message})
  end
end
