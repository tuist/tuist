defmodule Tuist.MCP.Components.Tools.CoverageSchemas do
  @moduledoc """
  The output schema fragments the coverage tools share, matching what
  `Tuist.Tests.Coverage.Report` returns.
  """

  alias Tuist.MCP.Tool, as: MCPTool

  def reason do
    %{
      "type" => ["object", "null"],
      "description" => "Why a figure is missing: a machine-readable kind and a sentence.",
      "properties" => %{
        "kind" => %{
          "type" => "string",
          "description" =>
            "no_merge_base, no_history, no_full_runs or no_ancestor_run for a missing baseline; partial_run or no_history for an unavailable patch coverage."
        },
        "message" => %{"type" => "string"}
      },
      "required" => ["kind", "message"],
      "additionalProperties" => false
    }
  end

  def baseline do
    %{
      "type" => ["object", "null"],
      "description" =>
        "The newest full run of the same scheme on the base branch, at the run's merge base or the nearest ancestor of it in the project's Git history.",
      "properties" => %{
        "test_run_id" => %{"type" => "string"},
        "commit" => %{"type" => "string"},
        "branch" => %{"type" => "string"},
        "depth" => %{
          "type" => "integer",
          "description" => "Commits between the merge base and the baseline commit (0 at the merge base)."
        },
        "ran_at" => %{"type" => ["string", "null"]},
        "covered_lines" => %{"type" => "integer"},
        "executable_lines" => %{"type" => "integer"},
        "coverage" => %{"type" => "number"}
      },
      "required" => ["test_run_id", "commit", "branch", "depth", "covered_lines", "executable_lines", "coverage"],
      "additionalProperties" => false
    }
  end

  def git_history do
    %{
      "type" => "object",
      "description" => "Where the run sits in the repository's history, as the client or the VCS provider recorded it.",
      "properties" => %{
        "base_branch" => %{"type" => "string"},
        "merge_base_sha" => %{"type" => "string"},
        "is_pull_request" => %{"type" => "boolean"},
        "pull_request_number" => %{"type" => "integer"},
        "git_object_format" => %{"type" => "string"},
        "history_source" => %{"type" => "string", "description" => "client, provider, mixed or none."},
        "history_fallback_reason" => %{"type" => "string"}
      },
      "required" => [
        "base_branch",
        "merge_base_sha",
        "is_pull_request",
        "pull_request_number",
        "git_object_format",
        "history_source",
        "history_fallback_reason"
      ],
      "additionalProperties" => false
    }
  end

  def target do
    %{
      "type" => "object",
      "properties" => %{
        "name" => %{"type" => "string"},
        "files_count" => %{"type" => "integer"},
        "covered_lines" => %{"type" => "integer"},
        "executable_lines" => %{"type" => "integer"},
        "coverage" => %{"type" => "number"}
      },
      "required" => ["name", "files_count", "covered_lines", "executable_lines", "coverage"],
      "additionalProperties" => false
    }
  end

  def file do
    %{
      "type" => "object",
      "properties" => file_properties(),
      "required" => ["path", "git_blob_id", "targets", "covered_lines", "executable_lines", "coverage"],
      "additionalProperties" => false
    }
  end

  def file_detail do
    %{
      "type" => "object",
      "properties" =>
        Map.merge(file_properties(), %{
          "lines" => %{
            "type" => "array",
            "description" => "Every executable line with its execution count, as [line, count] pairs in line order.",
            "items" => %{"type" => "array", "items" => %{"type" => "integer"}}
          },
          "uncovered_ranges" => %{
            "type" => ["array", "null"],
            "description" =>
              "Ranges of executable lines no test ran, as [first, last] pairs; null when the lines are unknown.",
            "items" => %{"type" => "array", "items" => %{"type" => "integer"}}
          },
          "functions" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "name" => %{"type" => "string"},
                "line_number" => %{"type" => "integer"},
                "execution_count" => %{"type" => "integer"},
                "covered_lines" => %{"type" => ["integer", "null"]},
                "executable_lines" => %{"type" => "integer"}
              },
              "required" => ["name", "line_number", "execution_count", "executable_lines"],
              "additionalProperties" => false
            }
          }
        }),
      "required" => [
        "path",
        "git_blob_id",
        "targets",
        "covered_lines",
        "executable_lines",
        "coverage",
        "lines",
        "functions"
      ],
      "additionalProperties" => false
    }
  end

  def comparison do
    delta_entry = fn key ->
      %{
        "type" => "object",
        "properties" => %{
          key => %{"type" => "string"},
          "covered_lines" => %{"type" => ["integer", "null"]},
          "executable_lines" => %{"type" => ["integer", "null"]},
          "coverage" => %{"type" => ["number", "null"]},
          "baseline_coverage" => %{"type" => ["number", "null"]},
          "delta" => %{
            "type" => ["number", "null"],
            "description" => "Percentage points; null when the entry cannot be compared."
          }
        },
        "required" => [key, "coverage", "baseline_coverage", "delta"],
        "additionalProperties" => false
      }
    end

    %{
      "type" => "object",
      "properties" => %{
        "run" => %{
          "type" => "object",
          "properties" => %{
            "id" => %{"type" => "string"},
            "partial" => %{"type" => "boolean"},
            "covered_lines" => %{"type" => "integer"},
            "executable_lines" => %{"type" => "integer"},
            "coverage" => %{"type" => "number"}
          },
          "required" => ["id", "partial", "covered_lines", "executable_lines", "coverage"],
          "additionalProperties" => false
        },
        "baseline" => baseline(),
        "baseline_reason" => reason(),
        "total_delta" => %{
          "type" => ["number", "null"],
          "description" => "Percentage points against the baseline; null on a partial run or without a baseline."
        },
        "targets" => %{"type" => "array", "items" => delta_entry.("name")},
        "files" => %{
          "type" => "array",
          "description" => "Only the files whose coverage moved or that one side lacks.",
          "items" => delta_entry.("path")
        },
        "patch" => %{
          "type" => "object",
          "properties" => %{
            "status" => %{"type" => "string", "enum" => ["available", "unavailable"]},
            "reason" => reason(),
            "covered_lines" => %{"type" => "integer"},
            "executable_lines" => %{"type" => "integer"},
            "coverage" => %{"type" => "number"},
            "files" => %{
              "type" => "array",
              "items" => %{
                "type" => "object",
                "properties" => %{
                  "path" => %{"type" => "string"},
                  "status" => %{"type" => "string"},
                  "covered_lines" => %{"type" => "integer"},
                  "executable_lines" => %{"type" => "integer"},
                  "coverage" => %{"type" => "number"},
                  "uncovered_ranges" => %{
                    "type" => "array",
                    "items" => %{"type" => "array", "items" => %{"type" => "integer"}}
                  }
                },
                "required" => ["path", "status", "covered_lines", "executable_lines", "coverage", "uncovered_ranges"],
                "additionalProperties" => false
              }
            },
            "skipped" => %{
              "type" => "array",
              "description" =>
                "Changed files left out of the patch and why: stale, no_line_data, truncated or not_instrumented.",
              "items" => %{
                "type" => "object",
                "properties" => %{"path" => %{"type" => "string"}, "reason" => %{"type" => "string"}},
                "required" => ["path", "reason"],
                "additionalProperties" => false
              }
            }
          },
          "required" => ["status"],
          "additionalProperties" => false
        },
        "gaps" => %{
          "type" => "array",
          "description" => "Changed files with executable lines in their hunks none of which ran.",
          "items" => %{
            "type" => "object",
            "properties" => %{"path" => %{"type" => "string"}, "executable_lines" => %{"type" => "integer"}},
            "required" => ["path", "executable_lines"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["run", "baseline", "baseline_reason", "total_delta", "targets", "files", "patch", "gaps"],
      "additionalProperties" => false
    }
  end

  def pull_request_run do
    %{
      "type" => "object",
      "properties" => %{
        "test_run_id" => %{"type" => "string"},
        "scheme" => %{"type" => "string"},
        "git_branch" => %{"type" => "string"},
        "base_branch" => %{"type" => "string"},
        "git_commit_sha" => %{"type" => "string"},
        "ran_at" => %{"type" => ["string", "null"]},
        "partial" => %{"type" => "boolean"},
        "covered_lines" => %{"type" => "integer"},
        "executable_lines" => %{"type" => "integer"},
        "coverage" => %{"type" => "number"}
      },
      "required" => [
        "test_run_id",
        "scheme",
        "git_branch",
        "base_branch",
        "git_commit_sha",
        "partial",
        "covered_lines",
        "executable_lines",
        "coverage"
      ],
      "additionalProperties" => false
    }
  end

  def branch do
    %{
      "type" => "object",
      "properties" => %{
        "git_branch" => %{"type" => "string"},
        "test_run_id" => %{"type" => "string"},
        "git_commit_sha" => %{"type" => "string"},
        "ran_at" => %{"type" => ["string", "null"]},
        "covered_lines" => %{"type" => "integer"},
        "executable_lines" => %{"type" => "integer"},
        "coverage" => %{"type" => "number"},
        "delta" => %{"type" => ["number", "null"], "description" => "Against the default branch's newest full run."}
      },
      "required" => [
        "git_branch",
        "test_run_id",
        "git_commit_sha",
        "covered_lines",
        "executable_lines",
        "coverage",
        "delta"
      ],
      "additionalProperties" => false
    }
  end

  @doc "The output of `get_test_run_coverage`."
  def run_output do
    %{
      "type" => "object",
      "properties" => %{
        "test_run_id" => %{"type" => "string"},
        "scheme" => %{"type" => "string"},
        "git_branch" => %{"type" => "string"},
        "git_commit_sha" => %{"type" => "string"},
        "ran_at" => %{"type" => ["string", "null"]},
        "partial" => %{
          "type" => "boolean",
          "description" =>
            "Whether the run left tests out on purpose; its coverage then describes only the tests that ran."
        },
        "covered_lines" => %{"type" => "integer"},
        "executable_lines" => %{"type" => "integer"},
        "coverage" => %{"type" => "number", "description" => "Line coverage over the run's product files, in percent."},
        "targets" => %{"type" => "array", "items" => target()},
        "git_history" => git_history(),
        "baseline" => baseline(),
        "baseline_reason" => reason()
      },
      "required" => [
        "test_run_id",
        "scheme",
        "git_branch",
        "git_commit_sha",
        "partial",
        "covered_lines",
        "executable_lines",
        "coverage",
        "targets",
        "git_history",
        "baseline",
        "baseline_reason"
      ],
      "additionalProperties" => false
    }
  end

  @doc "The output of `list_test_run_coverage_files`."
  def files_output do
    %{
      "type" => "object",
      "properties" => %{
        "files" => %{"type" => "array", "items" => file()},
        "pagination_metadata" => MCPTool.pagination_metadata_schema()
      },
      "required" => ["files", "pagination_metadata"],
      "additionalProperties" => false
    }
  end

  @doc "The output of `list_coverage_branches`."
  def branches_output do
    %{
      "type" => "object",
      "properties" => %{
        "scheme" => %{"type" => ["string", "null"]},
        "branches" => %{"type" => "array", "items" => branch()}
      },
      "required" => ["scheme", "branches"],
      "additionalProperties" => false
    }
  end

  @doc "The output of `get_pull_request_coverage`."
  def pull_request_output do
    %{
      "type" => "object",
      "properties" => %{
        "pull_request_number" => %{"type" => "integer"},
        "runs" => %{"type" => "array", "items" => pull_request_run()},
        "comparison" => comparison()
      },
      "required" => ["pull_request_number", "runs", "comparison"],
      "additionalProperties" => false
    }
  end

  defp file_properties do
    %{
      "path" => %{"type" => "string"},
      "git_blob_id" => %{"type" => "string"},
      "targets" => %{"type" => "array", "items" => %{"type" => "string"}},
      "covered_lines" => %{"type" => "integer"},
      "executable_lines" => %{"type" => "integer"},
      "coverage" => %{"type" => "number"}
    }
  end
end
