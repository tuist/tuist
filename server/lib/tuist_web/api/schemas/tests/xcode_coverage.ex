defmodule TuistWeb.API.Schemas.Tests.XcodeCoverage do
  @moduledoc """
  The line coverage an Xcode test run observed, read from the run's result
  bundle. Clients that let the server process the bundle never send it: the
  server reads the same data from the bundle itself.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "XcodeCoverage",
    type: :object,
    description:
      "Line coverage from a test run that ran with code coverage enabled: every source file the run's instrumented binaries compiled, with its per-line execution counts and functions.",
    properties: %{
      partial: %Schema{
        type: :boolean,
        description:
          "Whether the run left tests out on purpose (selective testing, -only-testing, -skip-testing), so its coverage describes only the tests that ran."
      },
      files: %Schema{
        type: :array,
        items: %Schema{
          type: :object,
          properties: %{
            path: %Schema{
              type: :string,
              description:
                "The file's path, relative to the repository's root when it lives under it and absolute otherwise."
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
      }
    },
    required: [:partial, :files]
  })
end
