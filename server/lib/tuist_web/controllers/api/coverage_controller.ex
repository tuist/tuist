defmodule TuistWeb.API.CoverageController do
  @moduledoc """
  Code coverage over the API: what a client needs to send a run's coverage
  when it processed the bundle itself (the inline threshold and a signed
  upload URL), and the signal that a commit's coverage pipeline finished.
  """
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Environment
  alias Tuist.Storage
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
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

  @commit_coverage %Schema{
    title: "CommitCoverage",
    type: :object,
    description: "A commit's coverage: the union of every run that measured it and its measured set.",
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
        targets: %Schema{type: :array, items: @target}
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
      :targets
    ]
  }

  @sha_parameter [
    git_commit_sha: [in: :path, type: :string, required: true, description: "The commit SHA."]
  ]

  @not_found_responses %{
    unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
    forbidden: {"The authenticated subject is not authorized to perform this action", "application/json", Error},
    not_found: {"The run or commit was not found, or gathered no coverage", "application/json", Error}
  }

  operation(:complete_commit,
    summary: "Signal that a commit's coverage pipeline finished.",
    description:
      "Tells the server that every run of the commit that gathers coverage has reported, which the data alone cannot show. The commit's coverage is republished as complete and it chains into its branch's trend. Runs landing afterwards still join the commit's coverage. Meant for a final CI job that depends on every test job (`tuist coverage complete`).",
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
      summary -> json(conn, Report.commit(summary, Commits.targets(project.id, sha)))
    end
  end

  defp not_found(conn, message) do
    conn |> put_status(:not_found) |> json(%{message: message})
  end
end
