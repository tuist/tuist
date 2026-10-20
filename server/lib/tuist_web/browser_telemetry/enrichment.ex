defmodule TuistWeb.BrowserTelemetry.Enrichment do
  @moduledoc """
  Adds collector-observed context without treating browser reports as proof of
  identity or humanity. Authentication describes the collector request, not
  necessarily the earlier navigation that produced a buffered measurement.
  """

  alias TuistWeb.Router

  @max_items 500
  @collections ~w(measurements events logs exceptions)

  def enrich(%{"meta" => meta} = payload, authentication, ray_id, origin, environment) when is_map(meta) do
    if valid_collections?(payload) do
      surface = surface(meta, origin)
      surface = if surface == "dashboard", do: "dashboard_#{authentication}", else: surface

      context = %{
        "rum_schema" => "1",
        "rum_surface" => surface,
        "rum_authentication" => authentication,
        "rum_ray_id" => ray_id,
        "rum_automation" => "unknown"
      }

      measurements =
        Enum.map(Map.get(payload, "measurements", []), fn measurement ->
          original_context = map(measurement["context"])

          context =
            Map.put(context, "rum_quality", quality(measurement, meta, original_context, surface))

          Map.put(measurement, "context", Map.merge(original_context, context))
        end)

      # A browser cannot choose the service/environment queried by the rules or
      # introduce user identity through Faro's optional user metadata.
      app = Map.merge(map(meta["app"]), %{"name" => "tuist-web", "environment" => environment})
      meta = meta |> Map.delete("user") |> Map.put("app", app)

      {:ok, payload |> Map.put("meta", meta) |> Map.put("measurements", measurements)}
    else
      {:error, :invalid_payload}
    end
  end

  def enrich(_, _, _, _, _), do: {:error, :invalid_payload}

  defp valid_collections?(payload) do
    Enum.all?(@collections, fn key ->
      items = Map.get(payload, key, [])
      is_list(items) and length(items) <= @max_items and Enum.all?(items, &is_map/1)
    end)
  end

  defp surface(meta, origin) do
    with url when is_binary(url) <- map(meta["page"])["url"],
         {:ok, uri} <- URI.new(url),
         %{host: host, scheme: scheme, port: port} <- URI.parse(origin),
         true <- uri.host == host and uri.scheme == scheme and uri.port == port and is_nil(uri.userinfo) do
      surface_for_path(uri.path || "/", host)
    else
      _ -> "unknown"
    end
  end

  defp surface_for_path("/turnstile-challenge" <> _, _host), do: "challenge"
  defp surface_for_path("/users/" <> _, _host), do: "auth"
  defp surface_for_path("/auth/" <> _, _host), do: "auth"
  defp surface_for_path("/docs/login", _host), do: "auth"

  defp surface_for_path(path, host) do
    case Phoenix.Router.route_info(Router, "GET", path, host) do
      %{plug: TuistWeb.APIController} ->
        "api_docs"

      %{type: :marketing} ->
        "marketing"

      %{type: :docs} ->
        "docs"

      %{pipe_through: pipelines} ->
        if :browser_app in pipelines, do: "dashboard", else: "other"

      _ ->
        "unknown"
    end
  end

  defp quality(measurement, meta, context, surface) do
    lcp = map(measurement["values"])["lcp"]

    cond do
      measurement["type"] != "web-vitals" or is_nil(lcp) -> "not_lcp"
      not is_number(lcp) or lcp < 0 -> "invalid_lcp"
      not present?(map(meta["session"])["id"]) -> "missing_session"
      not present?(context["navigation_entry_id"]) -> "missing_navigation"
      surface == "unknown" -> "unknown_surface"
      true -> "eligible"
    end
  end

  defp present?(value), do: is_binary(value) and byte_size(value) in 1..256
  defp map(value) when is_map(value), do: value
  defp map(_), do: %{}
end
