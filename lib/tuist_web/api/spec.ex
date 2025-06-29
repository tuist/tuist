defmodule TuistWeb.API.Spec do
  @moduledoc ~S"""
  A module that contains the spec of the Tuist API.
  """
  @behaviour OpenApiSpex.OpenApi

  alias OpenApiSpex.Components
  alias OpenApiSpex.Info
  alias OpenApiSpex.OpenApi
  alias OpenApiSpex.Paths
  alias OpenApiSpex.SecurityScheme
  alias OpenApiSpex.Server
  alias TuistWeb.Endpoint
  alias TuistWeb.Router

  @impl OpenApi
  def spec do
    OpenApiSpex.resolve_schema_modules(%OpenApi{
      servers: [Server.from_endpoint(Endpoint)],
      info: %Info{
        title: "Tuist",
        version: "0.1.0",
        extensions: %{
          "x-logo" => %{
            "url" => Tuist.Environment.app_url(path: "/images/open-graph/squared.png"),
            "altText" => "Tuist logo"
          }
        }
      },
      components: %Components{
        securitySchemes: %{
          "authorization" => %SecurityScheme{type: "http", scheme: "bearer"},
          "cookie" => %SecurityScheme{type: "apiKey", in: "cookie", name: "_tuist_cloud_key"},
          "oauth2" => %SecurityScheme{
            type: "oauth2",
            flows: %{
              authorizationCode: %{
                authorizationUrl: "/oauth2/authorize",
                tokenUrl: "/oauth2/token",
                scopes: %{
                  "read" => "Read access to resources",
                  "write" => "Write access to resources"
                }
              }
            }
          }
        }
      },
      security: [%{"authorization" => []}, %{"cookie" => []}],
      paths: Paths.from_router(Router)
    })

    # Discover request/response schemas from path specs
  end
end
