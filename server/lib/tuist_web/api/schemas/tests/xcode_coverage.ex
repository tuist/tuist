defmodule TuistWeb.API.Schemas.Tests.XcodeCoverage do
  @moduledoc """
  The line coverage an Xcode test run observed, read from the run's result
  bundle. Clients that let the server process the bundle never send it: the
  server reads the same data from the bundle itself.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  @source_file %Schema{
    type: :object,
    properties: %{
      path: %Schema{type: :string, description: "The file's path, relative to the repository's root."},
      git_blob_id: %Schema{type: :string, description: "The Git blob object id of the file's contents."}
    },
    required: [:path, :git_blob_id]
  }

  OpenApiSpex.schema(%{
    title: "XcodeCoverage",
    type: :object,
    description:
      "Line coverage from a test run that ran with code coverage enabled: every source file the run's instrumented binaries compiled, with its per-line execution counts and functions.",
    properties: %{
      partial: %Schema{
        type: :boolean,
        description:
          "Whether the run left tests out on purpose (selective testing, -only-testing, -skip-testing), so files it did not observe may carry earlier coverage forward."
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
      },
      unobserved_files: %Schema{
        type: :array,
        items: @source_file,
        description: "For a partial run, the repository's source files the run did not observe."
      }
    },
    required: [:partial, :files, :unobserved_files]
  })
end
