defmodule TuistCloudWeb.API.Spec do
  @moduledoc ~S"""
  A module that contains the spec of the Tuist Cloud API.
  """
  alias OpenApiSpex.{Components, Info, OpenApi, Paths, Server, SecurityScheme}
  alias TuistCloudWeb.{Endpoint, Router}
  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      servers: [
        Server.from_endpoint(Endpoint)
      ],
      info: %Info{
        title: "Tuist Cloud",
        version: TuistCloud.Environment.version()
      },
      components: %Components{
        securitySchemes: %{"authorization" => %SecurityScheme{type: "http", scheme: "bearer"}}
      },
      security: [%{"authorization" => []}],
      paths: Paths.from_router(Router)
    }
    # Discover request/response schemas from path specs
    |> OpenApiSpex.resolve_schema_modules()
  end
end
