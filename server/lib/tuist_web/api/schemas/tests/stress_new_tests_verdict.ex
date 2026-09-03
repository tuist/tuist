defmodule TuistWeb.API.Schemas.Tests.StressNewTestsVerdict do
  @moduledoc """
  The server's answer to a client asking which of the test cases a run just
  executed the stress gate for newly added tests should rerun.
  """
  alias OpenApiSpex.Schema
  alias Tuist.Tests.StressNewTests

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "StressNewTestsVerdict",
    type: :object,
    description:
      "Which of the reported test cases have not run in CI on the project's default branch in the trailing ninety days, how many times each should be rerun, the guard that fired if one did, and the parameters the pass runs under.",
    properties: %{
      enabled: %Schema{
        type: :boolean,
        description: "Whether the account is entitled to the gate. When false the client runs nothing and prints nothing."
      },
      guard: %Schema{
        type: :object,
        nullable: true,
        description: "The guard that kept the gate from producing candidates, if one fired.",
        properties: %{
          kind: %Schema{
            type: :string,
            enum: StressNewTests.guard_kinds(),
            description:
              "`no_default_branch` when the project has no default branch, `no_default_branch_history` when no test case has run in CI on it yet, `bulk_change` when the share of new test cases exceeds the project's bulk-change ratio."
          },
          new_count: %Schema{type: :integer, description: "How many reported test cases had no default-branch history."},
          inventory_count: %Schema{
            type: :integer,
            description: "How many test cases have run in CI on the default branch."
          }
        },
        required: [:kind, :new_count, :inventory_count]
      },
      inventory_count: %Schema{
        type: :integer,
        description: "How many test cases have run in CI on the default branch."
      },
      candidates: %Schema{
        type: :array,
        description:
          "The reported test cases with no default-branch history, sorted by identity. Each carries its repetition count, or 0 and a reason when it is excluded.",
        items: %Schema{
          type: :object,
          properties: %{
            name: %Schema{type: :string, description: "The name of the test case."},
            suite_name: %Schema{type: :string, description: "The suite (class) of the test case, or an empty string."},
            module_name: %Schema{type: :string, description: "The module (target or Gradle project) of the test case."},
            repetitions: %Schema{
              type: :integer,
              description:
                "How many times to rerun the test case, priced from its duration on the project's curve. 0 when excluded."
            },
            excluded_reason: %Schema{
              type: :string,
              enum: StressNewTests.excluded_reasons(),
              nullable: true,
              description:
                "`too_slow` when the test case exceeds the curve's last bucket, `candidate_cap` when the run already has as many candidates as the project allows."
            }
          },
          required: [:name, :suite_name, :module_name, :repetitions]
        }
      },
      parameters: %Schema{
        type: :object,
        description: "The project's stress parameters, so the client can report which bound bit.",
        properties: %{
          repetition_curve: %Schema{
            type: :array,
            description:
              "Buckets sorted by ascending `max_duration_ms`. A test case earns the repetitions of the first bucket its duration fits in; slower than the last bucket is excluded.",
            items: %Schema{
              type: :object,
              properties: %{
                max_duration_ms: %Schema{
                  type: :integer,
                  description: "Upper bound of the bucket in milliseconds, inclusive."
                },
                repetitions: %Schema{type: :integer, description: "Repetitions for test cases in the bucket."}
              },
              required: [:max_duration_ms, :repetitions]
            }
          },
          candidate_cap: %Schema{type: :integer, description: "Maximum number of candidates a run stresses."},
          wall_clock_ceiling_ms: %Schema{
            type: :integer,
            description:
              "Maximum wall-clock time in milliseconds the pass may take before the remaining candidates are reported as not stressed."
          },
          bulk_change_ratio: %Schema{
            type: :number,
            description: "Share of the default-branch inventory above which the bulk-change guard fires."
          },
          bulk_change_floor: %Schema{
            type: :integer,
            description: "Minimum number of new test cases before the bulk-change guard applies."
          }
        },
        required: [:repetition_curve, :candidate_cap, :wall_clock_ceiling_ms, :bulk_change_ratio, :bulk_change_floor]
      }
    },
    required: [:enabled, :candidates, :parameters, :inventory_count]
  })
end
