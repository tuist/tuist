defmodule Tuist.Tests.Selections.Schemas do
  @moduledoc """
  The shapes selective testing is read in (`Tuist.Tests.Selections.Query`),
  shared by the API and the MCP tools. Their titles name the API's schema
  components, which the clients' generated types are named after. The MCP
  tools read them through `Tuist.MCP.Tool.json_schema/1`.
  """
  alias OpenApiSpex.Schema

  @strategy %Schema{
    type: :string,
    description:
      "`coverage`: coverage-based test selection, a fallback included (its tests' reason says why coverage couldn't decide). `module_hash`: the default, which skips the test modules whose hash already passed. More values can be added."
  }

  def test_run do
    %Schema{
      title: "TestRunSelectiveTesting",
      type: :object,
      nullable: true,
      description:
        "The run's selective testing, null when it had none. Its counts are the run's own (a shard's, for a sharded run) and the ones the test selection effectiveness figures are computed from. For a few seconds after the run arrives, before they're recorded, a coverage selection's counts are its whole invocation's, which its shards share.",
      properties: %{
        strategy: @strategy,
        baseline_sha: %Schema{
          type: :string,
          nullable: true,
          description: "The commit coverage compared against, null when there was none."
        },
        requested: %Schema{
          type: :integer,
          description: "The tests in scope: those the run executed and those the selection skipped."
        },
        selected: %Schema{type: :integer, description: "The tests in scope the run executed."},
        skipped: %Schema{type: :integer, description: "The tests the selection skipped."},
        estimated: %Schema{
          type: :integer,
          description:
            "How many of the skipped tests are estimated: tests of a module skipped by hash, counted from an earlier run of the module (such as coverage's baseline) rather than from the run that stored the module's hash."
        }
      },
      required: [:strategy, :baseline_sha, :requested, :selected, :skipped, :estimated]
    }
  end

  def strategy, do: %{@strategy | nullable: true}

  def test_row do
    %Schema{
      title: "SelectiveTestingTest",
      type: :object,
      properties: %{
        test_case_id: %Schema{type: :string, format: :uuid},
        module_name: %Schema{type: :string},
        suite_name: %Schema{type: :string},
        name: %Schema{type: :string},
        decision: %Schema{type: :string, enum: ["selected", "skipped"]},
        reason: %Schema{
          type: :string,
          description:
            "Why: for a selected test, the rule that kept it (such as `impacted` or `test_file_changed`) or a fallback's reason (such as `tracked_file_changed`); for a skipped one, `unaffected` (no changed file in its coverage) or `module_skipped` (its module's hash already passed). More values can be added."
        },
        matched_path: %Schema{
          type: :string,
          nullable: true,
          description: "The changed file that selected the test, when one did."
        },
        shard_index: %Schema{
          type: :integer,
          nullable: true,
          description: "The shard a selected test was planned on, for a sharded run."
        },
        estimated_duration: %Schema{
          type: :integer,
          description: "The test's duration in the baseline, in milliseconds; 0 when unknown."
        },
        outcome: %Schema{
          type: :string,
          nullable: true,
          description: "The test's outcome in this run (`success`, `failure` or `skipped`), null when it didn't run here."
        },
        test_case_run_id: %Schema{
          type: :string,
          format: :uuid,
          nullable: true,
          description: "The test case run in this run, null when it didn't run here."
        }
      },
      required: [
        :test_case_id,
        :module_name,
        :suite_name,
        :name,
        :decision,
        :reason,
        :matched_path,
        :shard_index,
        :estimated_duration,
        :outcome,
        :test_case_run_id
      ]
    }
  end

  @doc "A page of a run's selection tests, with the caller's schema of the pagination metadata."
  def tests(pagination_metadata) do
    %Schema{
      title: "SelectiveTestingTests",
      type: :object,
      properties: %{tests: %Schema{type: :array, items: test_row()}, pagination_metadata: pagination_metadata},
      required: [:tests, :pagination_metadata]
    }
  end

  def changed_file_row do
    %Schema{
      title: "SelectiveTestingChangedFile",
      type: :object,
      properties: %{
        path: %Schema{type: :string, description: "The file's path, relative to the repository's root."},
        status: %Schema{type: :string, description: "The change, as `git diff --raw` reports it."},
        tracked: %Schema{
          type: :boolean,
          description:
            "Whether it's a tracked file, such as a dependency pin or build setting, whose change makes selection fall back."
        },
        selected_tests_count: %Schema{type: :integer, description: "How many tests the file selected."}
      },
      required: [:path, :status, :tracked, :selected_tests_count]
    }
  end

  @doc "A page of a run's changed files, with the caller's schema of the pagination metadata."
  def changed_files(pagination_metadata) do
    %Schema{
      title: "SelectiveTestingChangedFiles",
      type: :object,
      properties: %{
        changed_files: %Schema{type: :array, items: changed_file_row()},
        pagination_metadata: pagination_metadata
      },
      required: [:changed_files, :pagination_metadata]
    }
  end

  def test_case_run do
    %Schema{
      title: "TestCaseRunSelectiveTesting",
      type: :object,
      nullable: true,
      description: "Why the run's coverage-based selection kept the test, null when the run had no such selection.",
      properties: %{
        decision: %Schema{type: :string, enum: ["selected", "skipped"]},
        reason: test_row().properties.reason,
        matched_path: test_row().properties.matched_path,
        shard_index: test_row().properties.shard_index
      },
      required: [:decision, :reason, :matched_path, :shard_index]
    }
  end
end
