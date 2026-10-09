defmodule TuistWeb.API.Schemas.Tests.CoverageFile do
  @moduledoc """
  One covered source file of a run's coverage report, the same shape whatever
  build system measured it. Inlined into each report schema rather than
  referenced, so the clients' generated types keep their names.
  """
  alias OpenApiSpex.Schema

  def schema do
    %Schema{
      type: :object,
      properties: %{
        path: %Schema{
          type: :string,
          description: "The file's path, relative to the repository's root when it lives under it and absolute otherwise."
        },
        git_blob_id: %Schema{
          type: :string,
          nullable: true,
          description: "The Git blob object id of the file's contents, absent for files Git does not track."
        },
        targets: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "The targets whose binaries compiled the file."
        },
        is_test: %Schema{
          type: :boolean,
          description:
            "Whether only test bundles compiled the file. Test code is stored but left out of coverage figures."
        },
        covered_lines: %Schema{type: :integer, description: "Executable lines the tests ran at least once."},
        executable_lines: %Schema{type: :integer, description: "Lines the compiler instrumented."},
        line_numbers: %Schema{
          type: :array,
          items: %Schema{type: :integer},
          description: "The executable lines, ascending."
        },
        execution_counts: %Schema{
          type: :array,
          items: %Schema{type: :integer},
          description: "How many times each of `line_numbers` ran, index by index."
        },
        functions: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              name: %Schema{type: :string},
              line_number: %Schema{type: :integer},
              execution_count: %Schema{type: :integer},
              covered_lines: %Schema{type: :integer},
              executable_lines: %Schema{type: :integer}
            },
            required: [:name, :line_number, :execution_count, :covered_lines, :executable_lines]
          }
        }
      },
      required: [:path, :targets, :covered_lines, :executable_lines, :line_numbers, :execution_counts, :functions]
    }
  end
end
