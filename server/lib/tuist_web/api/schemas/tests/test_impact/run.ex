defmodule TuistWeb.API.Schemas.Tests.TestImpact.Run do
  @moduledoc """
  The decision coverage-based test selection made for one `tuist test`
  invocation.
  """
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.Tests.TestImpact.SkippedTest

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "TestImpactRun",
    type: :object,
    description: "The impact run: whether coverage selected tests or the invocation fell back.",
    properties: %{
      id: %Schema{
        type: :string,
        format: :uuid,
        description:
          "The impact run. Sent as `test_impact_run_id` when planning shards (on `selected`) and when uploading the test run (always)."
      },
      outcome: %Schema{
        type: :string,
        description:
          "`selected` or `fallback`. On `fallback` the client runs default selective testing: the tests in the modules hashing left. A plain string so new outcomes don't break older clients, which treat an unknown outcome as `fallback`."
      },
      reason: %Schema{
        type: :string,
        description:
          "Why coverage evidence wasn't applied: set on a fallback, and on a selection of nothing whose baseline wasn't confirmed. One of `diff_too_large`, `history_unknown`, `no_baseline`, `baseline_too_old`, `no_baseline_evidence`, `history_unavailable`, `diff_unavailable`, or `tracked_file_changed`."
      },
      matched_path: %Schema{
        type: :string,
        description: "The file that caused the fallback, such as the tracked file that changed."
      },
      counts: %Schema{
        type: :object,
        description: "Test counts for the client's output. Present when the outcome is `selected`.",
        properties: %{
          requested: %Schema{
            type: :integer,
            description: "The tests in scope, the ones in modules skipped because their hash matched included."
          },
          skipped: %Schema{
            type: :integer,
            description: "The tests not to run: those coverage skipped plus those in modules skipped by hash."
          },
          selected: %Schema{type: :integer, description: "The tests that will run."}
        }
      },
      skipped_tests: %Schema{
        type: :array,
        items: SkippedTest,
        description:
          "The tests not to run, present when the outcome is `selected`. Sharded runs ignore it and read each shard's list from the shard instead. A test the server doesn't know, such as one added in this change, is never on it and runs."
      }
    },
    required: [:id, :outcome]
  })
end
