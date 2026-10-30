defmodule Tuist.Tests.Coverage.Schemas do
  @moduledoc """
  The shapes coverage is read in (`Tuist.Tests.Coverage.Report`), shared by
  the API (`TuistWeb.API.CoverageController`) and the MCP tools: a commit's
  coverage, a branch's, a commit's files and one file. Their titles name the
  API's schema components, which the clients' generated types are named
  after. The MCP tools read them through `Tuist.MCP.Tool.json_schema/1`.
  """
  alias OpenApiSpex.Schema

  def reported do
    %Schema{
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
            "`measured`: the runs skipped nothing. `reported`: every skipped test was carried, so this is what a full run would measure. `partial`: the figure is a lower bound: some skipped tests or files could not be carried, a selective run's skipped tests could not be listed, or a scheme's coverage only came from runs on a dirty checkout, which don't count. `observed`: the runs listed no candidate tests, so what they skipped is unknown."
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
  end

  def target do
    %Schema{
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
  end

  def commit do
    %Schema{
      title: "CommitCoverage",
      type: :object,
      description: "A commit's coverage: the union of every run that measured it and its measured set.",
      properties: commit_properties(),
      required: commit_required()
    }
  end

  def branch do
    %Schema{
      title: "BranchCoverage",
      type: :object,
      description:
        "The coverage of a branch's latest complete commit: the union of every run that measured it and its measured set.",
      properties:
        Map.put(commit_properties(), :branch, %Schema{type: :string, description: "The branch the commit was read from."}),
      required: [:branch | commit_required()]
    }
  end

  def file_row do
    %Schema{
      title: "CoverageFileRow",
      type: :object,
      properties: %{
        path: %Schema{type: :string, description: "The file's path, relative to the repository's root."},
        covered_lines: %Schema{type: :integer, description: "Executable lines the tests ran at least once."},
        executable_lines: %Schema{type: :integer, description: "Lines the compiler instrumented."},
        coverage: %Schema{type: :number, description: "Line coverage, in percent."}
      },
      required: [:path, :covered_lines, :executable_lines, :coverage]
    }
  end

  @doc "A page of a commit's files, with the caller's schema of the pagination metadata."
  def files(pagination_metadata) do
    %Schema{
      title: "CommitCoverageFiles",
      type: :object,
      properties: %{
        git_commit_sha: %Schema{type: :string, description: "The commit the files were read at."},
        files: %Schema{type: :array, items: file_row()},
        pagination_metadata: pagination_metadata
      },
      required: [:git_commit_sha, :files, :pagination_metadata]
    }
  end

  def file do
    %Schema{
      title: "CoverageFileDetail",
      type: :object,
      description: "A product file's coverage at a commit, merged over every run that measured it.",
      properties: %{
        git_commit_sha: %Schema{type: :string, description: "The commit the file was read at."},
        path: %Schema{type: :string, description: "The file's path, relative to the repository's root."},
        git_blob_id: %Schema{
          type: :string,
          nullable: true,
          description: "The Git blob object id of the file's contents the runs measured, null when unknown."
        },
        targets: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "The targets whose binaries compiled the file."
        },
        covered_lines: %Schema{type: :integer, description: "Executable lines the tests ran at least once."},
        executable_lines: %Schema{type: :integer, description: "Lines the compiler instrumented."},
        coverage: %Schema{type: :number, description: "Line coverage, in percent."},
        carried_lines: %Schema{
          type: :array,
          items: %Schema{type: :integer},
          description:
            "Lines that count as covered only through a skipped test whose coverage was carried forward; no run of the commit executed them."
        },
        functions: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              name: %Schema{type: :string},
              line_number: %Schema{type: :integer, description: "The line the function starts at."},
              execution_count: %Schema{type: :integer, description: "How many times the function was called."},
              covered_lines: %Schema{
                type: :integer,
                nullable: true,
                description:
                  "The function's executable lines the tests ran, null when several runs covered it and their lines could not be told apart."
              },
              executable_lines: %Schema{type: :integer}
            },
            required: [:name, :line_number, :execution_count, :covered_lines, :executable_lines]
          }
        },
        lines: %Schema{
          type: :array,
          description: "Every executable line and how many times it ran, by line number. Only with `include_lines`.",
          items: %Schema{
            type: :object,
            properties: %{line: %Schema{type: :integer}, count: %Schema{type: :integer}},
            required: [:line, :count]
          }
        }
      },
      required: [
        :git_commit_sha,
        :path,
        :git_blob_id,
        :targets,
        :covered_lines,
        :executable_lines,
        :coverage,
        :carried_lines,
        :functions
      ]
    }
  end

  defp commit_properties do
    %{
      git_commit_sha: %Schema{type: :string},
      covered_lines: %Schema{type: :integer},
      executable_lines: %Schema{type: :integer},
      coverage: %Schema{type: :number, description: "Line coverage over the measured product files, in percent."},
      measured_files_count: %Schema{type: :integer, description: "Product files some run measured."},
      unmeasured_files_count: %Schema{
        type: :integer,
        description:
          "Source files of the commit's listing (of the kinds the runs measured, minus the excluded paths) that no run measured; 0 when the whole listing is not stored."
      },
      schemes: %Schema{type: :array, items: %Schema{type: :string}, description: "The schemes that measured the commit."},
      partial_schemes: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "The schemes only measured by runs that skipped tests on purpose."
      },
      partial: %Schema{type: :boolean},
      complete: %Schema{
        type: :boolean,
        description: "Whether the commit's coverage pipeline is known to have finished (`completeness` says how)."
      },
      completeness: %Schema{
        type: :string,
        description: "`signal` when the client signalled completion, or empty."
      },
      reported: reported(),
      test_run_ids: %Schema{type: :array, items: %Schema{type: :string, format: :uuid}},
      measured_at: %Schema{type: :string, format: :"date-time"},
      targets: %Schema{type: :array, items: target()}
    }
  end

  defp commit_required do
    [
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
  end
end
