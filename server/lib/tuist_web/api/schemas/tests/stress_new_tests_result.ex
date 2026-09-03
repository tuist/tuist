defmodule TuistWeb.API.Schemas.Tests.StressNewTestsResult do
  @moduledoc """
  The outcome of the stress gate for newly added tests, as the client reports
  it with the test run it belongs to.
  """
  alias OpenApiSpex.Schema
  alias Tuist.Tests.StressNewTests
  alias Tuist.Tests.TestRunStressCandidate

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "StressNewTestsResult",
    type: :object,
    description:
      "What the stress gate for newly added tests did during this run: the mode it ran in, whether it found a candidate disagreeing with itself or why it ran nothing, and every test case it examined.",
    properties: %{
      mode: %Schema{
        type: :string,
        enum: StressNewTests.modes(),
        description: "The mode the gate ran in. `report` only warns; `enforce` fails the run on a disagreement."
      },
      outcome: %Schema{
        type: :string,
        enum: StressNewTests.run_outcomes(),
        description:
          "`passed` when every stressed candidate agreed with itself, `disagreed` when at least one did not, `skipped` when a guard or the first pass kept the gate from running, `no_candidates` when the run added no tests."
      },
      skip_reason: %Schema{
        type: :string,
        enum: StressNewTests.skip_reasons(),
        nullable: true,
        description: "Why the gate ran nothing, when `outcome` is `skipped`."
      },
      new_count: %Schema{
        type: :integer,
        description:
          "How many of the run's test cases had not run in CI on the default branch in the trailing ninety days."
      },
      stressed_count: %Schema{type: :integer, description: "How many candidates the gate reran."},
      excluded_count: %Schema{
        type: :integer,
        description:
          "How many candidates were not rerun: too slow for the curve, beyond the candidate cap, left over when the wall-clock ceiling was reached, or unrun because the stress pass itself failed to execute."
      },
      inventory_count: %Schema{
        type: :integer,
        description: "How many test cases have run in CI on the default branch, as the verdict measured it."
      },
      test_cases: %Schema{
        type: :array,
        description: "Every candidate the gate examined.",
        items: %Schema{
          type: :object,
          properties: %{
            name: %Schema{type: :string, description: "The name of the test case."},
            suite_name: %Schema{type: :string, nullable: true, description: "The suite (class) of the test case."},
            module_name: %Schema{type: :string, description: "The module (target or Gradle project) of the test case."},
            repetitions: %Schema{type: :integer, description: "How many times the gate ran the test case."},
            failed_repetitions: %Schema{type: :integer, description: "How many of those repetitions failed."},
            outcome: %Schema{
              type: :string,
              enum: TestRunStressCandidate.outcomes(),
              description: "What the gate concluded for this candidate."
            },
            is_quarantined: %Schema{
              type: :boolean,
              description:
                "Whether the test case was muted, in which case a disagreement is recorded but cannot fail the gate."
            },
            repetition_results: %Schema{
              type: :array,
              description:
                "Each repetition the gate ran for this test case, in order, so the dashboard can show which of them failed.",
              items: %Schema{
                type: :object,
                properties: %{
                  repetition_number: %Schema{type: :integer, description: "The 1-based position of this repetition."},
                  status: %Schema{
                    type: :string,
                    enum: ["success", "failure"],
                    description: "The result of this repetition."
                  },
                  duration: %Schema{type: :integer, description: "Duration of this repetition in milliseconds."},
                  failure: %Schema{
                    type: :object,
                    nullable: true,
                    description: "The failure this repetition produced, when it failed.",
                    properties: %{
                      message: %Schema{type: :string, nullable: true, description: "The failure message."},
                      path: %Schema{
                        type: :string,
                        nullable: true,
                        description: "The source file the failure points at."
                      },
                      line_number: %Schema{
                        type: :integer,
                        nullable: true,
                        description: "The line the failure points at."
                      },
                      issue_type: %Schema{
                        type: :string,
                        nullable: true,
                        enum: ["assertion_failure", "error_thrown", "issue_recorded"],
                        description: "The kind of failure."
                      }
                    }
                  }
                },
                required: [:repetition_number, :status]
              }
            }
          },
          required: [:name, :module_name, :repetitions, :failed_repetitions, :outcome]
        }
      }
    },
    required: [:mode, :outcome, :new_count, :stressed_count, :excluded_count, :test_cases]
  })
end
