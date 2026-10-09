defmodule TuistWeb.API.Schemas.Tests.Coverage do
  @moduledoc """
  The line coverage a test run observed, from whichever build system ran it:
  the files inline, or the `storage_key` of a file the client uploaded first
  when the report is too large to send inline. Xcode clients may send
  `xcode_coverage` instead.
  """
  alias OpenApiSpex.Schema
  alias TuistWeb.API.Schemas.Tests.CoverageFile

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "Coverage",
    type: :object,
    description:
      "Line coverage from a test run that ran with code coverage enabled: every source file the run instrumented, with its per-line execution counts, inline in `files` or uploaded under `storage_key`.",
    properties: %{
      tool: %Schema{
        type: :string,
        description: "The tool that measured the coverage, such as `cover` for Mix or `xccov` for Xcode."
      },
      tool_version: %Schema{
        type: :string,
        description: "The version of the tool, or of the runtime that provides it, so only like figures are compared."
      },
      partial: %Schema{
        type: :boolean,
        description:
          "Whether the run left tests out on purpose (filters, selective testing), so its coverage describes only the tests that ran."
      },
      files: %Schema{type: :array, items: CoverageFile.schema()},
      storage_key: %Schema{
        type: :string,
        description:
          "The storage key `createCoverageUpload` returned for this run's id, once the client PUT the compressed coverage there; sent instead of `files` when the coverage is too large to send inline."
      }
    },
    required: [:tool, :partial]
  })
end
