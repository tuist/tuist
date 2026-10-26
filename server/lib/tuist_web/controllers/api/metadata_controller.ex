defmodule TuistWeb.API.MetadataController do
  use TuistWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Schema
  alias Tuist.Builds.Metadata

  operation(:limits,
    summary: "Discover the supported custom metadata budget without sending credentials or build data.",
    operation_id: "getCustomMetadataLimits",
    responses: %{
      ok:
        {"Metadata limits", "application/json",
         %Schema{
           type: :object,
           properties: %{max_values: %Schema{type: :integer}},
           required: [:max_values]
         }}
    }
  )

  def limits(conn, _params) do
    limit = Metadata.advertised_limit()

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("x-tuist-custom-metadata-max-values", Integer.to_string(limit))
    |> json(%{max_values: limit})
  end
end
