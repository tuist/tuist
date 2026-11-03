defmodule TuistWeb.API.Schemas.Tests.TestImpact.SkippedTest do
  @moduledoc """
  A test, suite, or whole module that coverage-based test selection decided not
  to run.
  """
  alias OpenApiSpex.Schema

  require OpenApiSpex

  OpenApiSpex.schema(%{
    title: "TestImpactSkippedTest",
    type: :object,
    description:
      "A test not to run, named the same way for every build system; each client turns it into its own filters. An entry with only `module` skips the whole module, which happens only when none of its tests is selected. Entries are never collapsed into a suite.",
    properties: %{
      module: %Schema{type: :string, description: "The test module (target, Gradle module, Mix app, or crate)."},
      suite: %Schema{
        type: :string,
        description: "The suite (class) of the test. Absent when the whole module is skipped."
      },
      name: %Schema{type: :string, description: "The name of the test. Absent when the whole module is skipped."}
    },
    required: [:module]
  })
end
