defmodule TuistWeb.API.Schemas.Tests.XcodeCoverage do
  @moduledoc """
  The line coverage an Xcode test run observed, read from the run's result
  bundle. Clients that let the server process the bundle never send it: the
  server reads the same data from the bundle itself.
  """
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.Tests.CoverageFile

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
        items: CoverageFile.schema()
      }
    },
    required: [:partial, :files]
  })
end
