defmodule TuistRegistryWeb.Router do
  use TuistRegistryWeb, :router

  pipeline :swift_api do
    plug :accepts, ["swift-v1-json", "swift-v1-zip", "swift-v1-api"]
    plug :assign_registry_base_path, "/swift"
  end

  pipeline :swift_api_deprecated do
    plug :accepts, ["swift-v1-json", "swift-v1-zip", "swift-v1-api"]
    plug :assign_registry_base_path, "/api/registry/swift"
    plug TuistRegistryWeb.Plugs.DeprecatedSwiftPath
  end

  # Generated URLs (release `url` fields, alternate-manifest `Link` headers,
  # internal redirects) must match the prefix the client used. Otherwise a
  # SwiftPM client that resolves `tuist.dev/api/registry/swift/...` would
  # resolve a relative `/swift/...` as `https://tuist.dev/swift/...` and 404.
  def assign_registry_base_path(conn, base_path) do
    Plug.Conn.assign(conn, :registry_base_path, base_path)
  end

  scope "/", TuistRegistryWeb do
    get "/up", UpController, :index
  end

  # The canonical Swift Package Registry surface lives at `/swift/*` on
  # `registry.tuist.dev`. The legacy `/api/registry/swift/*` prefix below
  # mirrors the same routes for clients that still resolve registry URLs
  # against the path cache served before this service was extracted.
  # Legacy responses carry RFC 8594 `Deprecation` and `Sunset` headers via
  # the `:swift_api_deprecated` pipeline.
  for {prefix, pipeline} <- [{"/swift", :swift_api}, {"/api/registry/swift", :swift_api_deprecated}] do
    scope prefix, TuistRegistryWeb.Swift do
      pipe_through [pipeline]

      get "/", RegistryController, :availability
      head "/", RegistryController, :availability
      get "/availability", RegistryController, :availability
      head "/availability", RegistryController, :availability
      get "/identifiers", RegistryController, :identifiers
      head "/identifiers", RegistryController, :identifiers
      post "/login", RegistryController, :login
      get "/:scope/:name", RegistryController, :list_releases
      head "/:scope/:name", RegistryController, :list_releases
      get "/:scope/:name/:version", RegistryController, :show_release
      head "/:scope/:name/:version", RegistryController, :show_release
      get "/:scope/:name/:version/Package.swift", RegistryController, :show_manifest
      head "/:scope/:name/:version/Package.swift", RegistryController, :show_manifest
    end
  end
end
