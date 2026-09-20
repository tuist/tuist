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
            "no_history, no_merge_base, no_measured_commits, no_ancestor_commit or measured_set_mismatch for a missing baseline; no_history for an unavailable patch coverage."
        },
        "message" => %{"type" => "string"}
      },
      "required" => ["kind", "message"],
      "additionalProperties" => false
    }
  end

  def measured_set_properties do
    %{
      "schemes" => %{
        "type" => "array",
        "items" => %{"type" => "string"},
        "description" => "The schemes that measured the commit."
      },
      "partial_schemes" => %{
        "type" => "array",
        "items" => %{"type" => "string"},
        "description" => "The schemes only measured by runs that skipped tests on purpose."
      },
      "complete" => %{
        "type" => "boolean",
        "description" => "Whether the commit's coverage pipeline is known to have finished."
      },
      "completeness" => %{"type" => "string", "description" => "signal, inferred or empty."},
      "test_run_ids" => %{"type" => "array", "items" => %{"type" => "string"}}
    }
  end

  def baseline do
    %{
      "type" => ["object", "null"],
      "description" =>
        "The nearest measured ancestor of the commit's merge base with its base branch (its first parent for a commit on the base branch), walked first-parent through the repository's Git history, that measured the same schemes.",
      "properties" =>
        Map.merge(measured_set_properties(), %{
          "commit" => %{"type" => "string"},
          "branch" => %{"type" => "string"},
          "depth" => %{
            "type" => "integer",
            "description" => "Commits between the start of the walk and the baseline commit (0 at the merge base)."
          },
          "measured_at" => %{"type" => ["string", "null"]},
          "covered_lines" => %{"type" => "integer"},
          "executable_lines" => %{"type" => "integer"},
          "coverage" => %{"type" => "number"}
        }),
      "required" => [
        "commit",
        "branch",
        "depth",
        "covered_lines",
        "executable_lines",
        "coverage",
        "schemes",
        "partial_schemes",
        "complete"
      ],
      "additionalProperties" => false
    }
  end

  def git_history do
    %{
      "type" => "object",
      "description" => "Where the run sits in the repository's history, as the client or the VCS provider recorded it.",
      "properties" => %{
        "git_dirty" => %{
          "type" => "boolean",
          "description" =>
            "Whether the checkout had uncommitted changes: the run then measured code that is not the commit's and never joins the commit's coverage."
        },
        "base_branch" => %{"type" => "string"},
        "merge_base_sha" => %{"type" => "string"},
        "is_pull_request" => %{"type" => "boolean"},
        "pull_request_number" => %{"type" => "integer"},
        "git_object_format" => %{"type" => "string"},
        "history_source" => %{"type" => "string", "description" => "client, provider, mixed or none."},
        "history_fallback_reason" => %{"type" => "string"},
        "tracked_files_count" => %{
          "type" => "integer",
          "description" =>
            "How many files of the commit's listing the project's tracked-file globs match (dependency manifests, generator configuration, fixtures, snapshots)."
        },
        "commit_files_listed" => %{
          "type" => "boolean",
          "description" => "Whether the commit's file listing (every tracked file with its blob) is stored."
        }
      },
      "required" => [
        "git_dirty",
        "base_branch",
        "merge_base_sha",
        "is_pull_request",
        "pull_request_number",
        "git_object_format",
        "history_source",
        "history_fallback_reason",
        "tracked_files_count",
        "commit_files_listed"
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
        "commit" => %{
          "type" => "object",
          "description" => "The commit's coverage: the union of every run that measured it.",
          "properties" => %{
            "sha" => %{"type" => "string", "description" => "Empty for a run without a commit, described alone."},
            "partial" => %{
              "type" => "boolean",
              "description" =>
                "Whether any scheme was only measured by runs that skipped tests; there is then no total delta."
            },
            "covered_lines" => %{"type" => "integer"},
            "executable_lines" => %{"type" => "integer"},
            "coverage" => %{"type" => "number"},
            "schemes" => %{"type" => "array", "items" => %{"type" => "string"}},
            "partial_schemes" => %{"type" => "array", "items" => %{"type" => "string"}},
            "complete" => %{"type" => "boolean"},
            "completeness" => %{"type" => "string"}
          },
          "required" => ["sha", "partial", "covered_lines", "executable_lines", "coverage", "schemes", "partial_schemes"],
          "additionalProperties" => false
        },
        "baseline" => baseline(),
        "baseline_reason" => reason(),
        "total_delta" => %{
          "type" => ["number", "null"],
          "description" =>
            "Percentage points against the baseline; null when the commit measured a scheme partially, the baseline measured a different set of schemes, or there is no baseline."
        },
        "schemes" => %{
          "type" => "array",
          "description" =>
            "Each scheme's own total at the commit and at the baseline: two schemes measure different slices, so only matching sets compare as a whole.",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "scheme" => %{"type" => "string"},
              "partial" => %{"type" => ["boolean", "null"]},
              "covered_lines" => %{"type" => ["integer", "null"]},
              "executable_lines" => %{"type" => ["integer", "null"]},
              "coverage" => %{"type" => ["number", "null"]},
              "baseline_coverage" => %{"type" => ["number", "null"]},
              "delta" => %{"type" => ["number", "null"]}
            },
            "required" => ["scheme", "coverage", "baseline_coverage", "delta"],
            "additionalProperties" => false
          }
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
                "Changed files left out of the patch and why: stale, no_line_data, truncated, not_instrumented or excluded (matched by the project's excluded paths).",
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
      "required" => [
        "commit",
        "baseline",
        "baseline_reason",
        "total_delta",
        "schemes",
        "targets",
        "files",
        "patch",
        "gaps"
      ],
      "additionalProperties" => false
    }
  end

  defp measurement_properties do
    Map.merge(measured_set_properties(), %{
      "git_commit_sha" => %{"type" => "string"},
      "covered_lines" => %{"type" => "integer"},
      "executable_lines" => %{"type" => "integer"},
      "coverage" => %{"type" => "number"},
      "partial" => %{"type" => "boolean"},
      "measured_at" => %{"type" => ["string", "null"]}
    })
  end

  def pull_request_commit do
    %{
      "type" => "object",
      "properties" =>
        Map.merge(measurement_properties(), %{
          "git_branch" => %{"type" => "string"},
          "base_branch" => %{"type" => "string"},
          "ran_at" => %{"type" => ["string", "null"]}
        }),
      "required" => [
        "git_commit_sha",
        "git_branch",
        "base_branch",
        "covered_lines",
        "executable_lines",
        "coverage",
        "complete"
      ],
      "additionalProperties" => false
    }
  end

  def branch do
    %{
      "type" => "object",
      "properties" =>
        Map.merge(measurement_properties(), %{
          "git_branch" => %{"type" => "string"},
          "chained" => %{"type" => "boolean"},
          "ordered_by" => %{
            "type" => "string",
            "description" =>
              "graph when the branch's commits come from the Git graph, time when only the runs' order is known."
          },
          "delta" => %{
            "type" => ["number", "null"],
            "description" =>
              "Against the default branch's head, in percentage points; null when either side is unchained."
          }
        }),
      "required" => [
        "git_branch",
        "git_commit_sha",
        "covered_lines",
        "executable_lines",
        "coverage",
        "chained",
        "ordered_by",
        "delta"
      ],
      "additionalProperties" => false
    }
  end

  def history_commit do
    %{
      "type" => "object",
      "properties" =>
        Map.merge(measurement_properties(), %{
          "depth" => %{"type" => "integer", "description" => "Commits from the branch's head (0 at the head)."},
          "committed_at" => %{"type" => ["string", "null"]},
          "measured" => %{"type" => "boolean"},
          "chained" => %{"type" => "boolean", "description" => "Whether the commit is a point of the branch's trend."}
        }),
      "required" => ["git_commit_sha", "depth", "measured", "chained"],
      "additionalProperties" => false
    }
  end

  @doc "The output of `get_commit_coverage`."
  def commit_output do
    %{
      "type" => "object",
      "properties" =>
        Map.merge(measurement_properties(), %{
          "measured_files_count" => %{"type" => "integer", "description" => "Product files some run measured."},
          "unmeasured_files_count" => %{
            "type" => "integer",
            "description" =>
              "Source files of the commit's listing (of the kinds the runs measured, minus excluded paths) no run measured, shown in the dashboard as \"Files without coverage data\"; 0 when the listing is not stored."
          },
          "targets" => %{"type" => "array", "items" => target()},
          "baseline" => baseline(),
          "baseline_reason" => reason()
        }),
      "required" => [
        "git_commit_sha",
        "covered_lines",
        "executable_lines",
        "coverage",
        "measured_files_count",
        "unmeasured_files_count",
        "schemes",
        "partial_schemes",
        "partial",
        "complete",
        "completeness",
        "test_run_ids",
        "targets",
        "baseline",
        "baseline_reason"
      ],
      "additionalProperties" => false
    }
  end

  @doc "The output of `list_coverage_history`."
  def history_output do
    %{
      "type" => "object",
      "properties" => %{
        "branch" => %{"type" => "string"},
        "ordered_by" => %{"type" => "string"},
        "commits" => %{"type" => "array", "items" => history_commit()}
      },
      "required" => ["branch", "ordered_by", "commits"],
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
        "execution_mode" => %{
          "type" => "string",
          "description" => "parallel, serial, or empty when unknown."
        },
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
      "properties" => %{"branches" => %{"type" => "array", "items" => branch()}},
      "required" => ["branches"],
      "additionalProperties" => false
    }
  end

  @doc "The output of `get_pull_request_coverage`."
  def pull_request_output do
    %{
      "type" => "object",
      "properties" => %{
        "pull_request_number" => %{"type" => "integer"},
        "commits" => %{"type" => "array", "items" => pull_request_commit()},
        "comparison" => comparison()
      },
      "required" => ["pull_request_number", "commits", "comparison"],
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
