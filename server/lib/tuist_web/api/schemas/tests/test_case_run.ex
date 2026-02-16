defmodule TuistWeb.API.Schemas.Tests.TestCaseRun do
  @moduledoc false

  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    description: "A single test case run.",
    properties: %{
      id: %Schema{type: :string, format: :uuid, description: "The test case run ID."},
      name: %Schema{type: :string, description: "Name of the test case."},
      module_name: %Schema{type: :string, description: "Module name."},
      suite_name: %Schema{type: :string, nullable: true, description: "Suite name."},
      status: %Schema{
        type: :string,
        enum: ["success", "failure", "skipped"],
        description: "Run status."
      },
      duration: %Schema{type: :integer, description: "Duration in milliseconds."},
      is_ci: %Schema{type: :boolean, description: "Whether the run was on CI."},
      is_flaky: %Schema{type: :boolean, description: "Whether the run was flaky."},
      is_new: %Schema{type: :boolean, description: "Whether this was a new test case."},
      scheme: %Schema{type: :string, nullable: true, description: "Build scheme."},
      git_branch: %Schema{type: :string, nullable: true, description: "Git branch."},
      git_commit_sha: %Schema{type: :string, nullable: true, description: "Git commit SHA."},
      ran_at: %Schema{
        type: :string,
        format: :"date-time",
        nullable: true,
        description: "ISO 8601 timestamp when the run executed."
      }
    },
    required: [:id, :name, :module_name, :status, :duration, :is_ci, :is_flaky, :is_new]
  })
end
