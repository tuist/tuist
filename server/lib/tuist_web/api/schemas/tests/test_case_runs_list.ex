defmodule TuistWeb.API.Schemas.Tests.TestCaseRunsList do
  @moduledoc false

  alias TuistWeb.API.Schemas.PaginationMetadata
  alias TuistWeb.API.Schemas.Tests.TestCaseRun

  require OpenApiSpex

  OpenApiSpex.schema(%{
    type: :object,
    description: "A paginated list of test case runs.",
    properties: %{
      test_case_runs: %OpenApiSpex.Schema{type: :array, items: TestCaseRun},
      pagination_metadata: PaginationMetadata
    },
    required: [:test_case_runs, :pagination_metadata]
  })
end
