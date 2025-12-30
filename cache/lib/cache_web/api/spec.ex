defmodule CacheWeb.API.Spec do
  @moduledoc false
  @behaviour OpenApiSpex.OpenApi

  alias CacheWeb.Endpoint
  alias CacheWeb.Router
  alias OpenApiSpex.Components
  alias OpenApiSpex.Info
  alias OpenApiSpex.OpenApi
  alias OpenApiSpex.Paths
  alias OpenApiSpex.SecurityScheme
  alias OpenApiSpex.Server

  @impl OpenApi
  def spec do
    OpenApiSpex.resolve_schema_modules(%OpenApi{
      servers: [Server.from_endpoint(Endpoint)],
      info: %Info{
        title: "Tuist Cache",
        version: "0.1.0"
      },
      components: %Components{
        securitySchemes: %{
          "authorization" => %SecurityScheme{
            type: "http",
            scheme: "bearer"
          }
        }
      },
      security: [%{"authorization" => []}],
      paths: Paths.from_router(Router)
    })
  end
end
