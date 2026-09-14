defmodule TuistWeb.API.Schemas.Tests.XcodeCoverage do
  @moduledoc """
  The line coverage an Xcode test run gathered, as `xccov` reports it from the
  run's result bundle.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "XcodeCoverage",
    type: :object,
    description:
      "Line coverage from a test run that ran with code coverage enabled: every target the scheme gathered coverage for, and each source file in it with its covered and executable line counts. A file linked into several targets appears under each of them, as `xccov` reports it.",
    properties: %{
      targets: %Schema{
        type: :array,
        description: "The targets coverage was gathered for.",
        items: %Schema{
          type: :object,
          properties: %{
            name: %Schema{type: :string, description: "The target's name."},
            covered_lines: %Schema{type: :integer, description: "Executable lines the tests ran at least once."},
            executable_lines: %Schema{type: :integer, description: "Lines the compiler instrumented."},
            files: %Schema{
              type: :array,
              description: "The source files compiled into the target.",
              items: %Schema{
                type: :object,
                properties: %{
                  path: %Schema{
                    type: :string,
                    description:
                      "The file's path, relative to the project's root directory when it lives under it and absolute otherwise."
                  },
                  covered_lines: %Schema{type: :integer, description: "Executable lines the tests ran at least once."},
                  executable_lines: %Schema{type: :integer, description: "Lines the compiler instrumented."}
                },
                required: [:path, :covered_lines, :executable_lines]
              }
            }
          },
          required: [:name, :covered_lines, :executable_lines, :files]
        }
      }
    },
    required: [:targets]
  })
end
