defmodule TuistWeb.Utilities.RobotsTxt do
  @moduledoc """
  Builds the runtime robots.txt payload for Tuist's public site.

  The Content-Usage allowlist is derived from the Phoenix router so public
  marketing and docs routes do not drift from the declared policy.
  """

  alias TuistWeb.Marketing.Localization
  alias TuistWeb.Router

  @excluded_route_paths MapSet.new([
                          "/docs",
                          "/docs/login",
                          "/docs/:locale",
                          "/docs/:locale/*path"
                        ])

  @disallow_sections [
    {"# Block authentication and user pages",
     [
       "/dashboard",
       "/users/",
       "/auth/",
       "/oauth2/",
       "/organizations/",
       "/projects/"
     ]},
    {"# Block admin/ops pages", ["/ops/", "/live/"]},
    {"# Block API endpoints", ["/api/"]},
    {"# Block download endpoints", ["/download"]},
    {"# Block all account/project specific pages",
     [
       "/*/projects",
       "/*/members",
       "/*/billing",
       "/*/settings",
       "/*/previews",
       "/*/tests",
       "/*/binary-cache",
       "/*/connect",
       "/*/analytics",
       "/*/bundles",
       "/*/builds",
       "/*/runs",
       "/*/test-runs",
       "/*/cache-runs",
       "/*/generate-runs",
       "/*/build-runs"
     ]}
  ]

  def render do
    ([
       "User-agent: *",
       "Content-Signal: ai-train=no, search=no, ai-input=no",
       "",
       "# Keep the coarse site-wide signal restrictive, then opt public docs and",
       "# marketing content back in with path-specific Content-Usage rules.",
       "Content-Usage: train-ai=n, search=n"
     ] ++
       Enum.map(content_usage_patterns(), &"Content-Usage: #{&1} train-ai=y, search=y") ++
       [""] ++
       disallow_lines())
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  def content_usage_patterns do
    prefixes = prefixes_by_route(content_usage_routes())

    patterns =
      Enum.map(prefixes, fn {prefix, dynamic?} ->
        pattern_for(prefix, dynamic?, Map.keys(prefixes))
      end)

    prefix_patterns =
      patterns
      |> Enum.reject(&String.ends_with?(&1, "$"))
      |> MapSet.new()

    patterns
    |> Enum.reject(fn pattern ->
      normalized_pattern = String.trim_trailing(pattern, "$")

      Enum.any?(prefix_patterns, fn prefix_pattern ->
        prefix_pattern != normalized_pattern and
          String.starts_with?(normalized_pattern, prefix_pattern <> "/")
      end)
    end)
    |> Enum.sort_by(&sort_key/1)
  end

  defp content_usage_routes do
    Router.__routes__()
    |> Enum.filter(&content_usage_route?/1)
    |> Enum.reject(&MapSet.member?(@excluded_route_paths, &1.path))
  end

  defp content_usage_route?(%{verb: :get, path: path, metadata: metadata}) when is_binary(path) and is_map(metadata) do
    Map.get(metadata, :type) in [:marketing, :docs]
  end

  defp content_usage_route?(_), do: false

  defp prefixes_by_route(routes) do
    Enum.reduce(routes, %{}, fn route, acc ->
      route
      |> route_prefixes()
      |> Enum.reduce(acc, fn {prefix, dynamic?}, acc ->
        Map.update(acc, prefix, dynamic?, &(&1 or dynamic?))
      end)
    end)
  end

  defp route_prefixes(%{path: "/:locale/docs-markdown/*path"}) do
    Enum.map(Localization.all_locales(), &{"/#{&1}/docs-markdown", true})
  end

  defp route_prefixes(%{path: path}) do
    case path_prefix(path) do
      nil -> []
      prefix -> [{prefix, dynamic_route?(path)}]
    end
  end

  defp path_prefix("/"), do: "/"

  defp path_prefix(path) do
    path
    |> String.split("/", trim: true)
    |> Enum.take_while(&(not dynamic_segment?(&1)))
    |> case do
      [] -> nil
      segments -> "/" <> Enum.join(segments, "/")
    end
  end

  defp dynamic_route?(path) do
    String.contains?(path, "/:") or String.contains?(path, "/*")
  end

  defp dynamic_segment?(segment) do
    String.starts_with?(segment, ":") or String.starts_with?(segment, "*")
  end

  defp pattern_for("/", _dynamic?, _prefixes), do: "/$"

  defp pattern_for(prefix, dynamic?, prefixes) do
    if locale_root?(prefix) do
      prefix <> "$"
    else
      if dynamic? or descendant_prefix?(prefix, prefixes) do
        prefix
      else
        prefix <> "$"
      end
    end
  end

  defp locale_root?(prefix) do
    prefix in Enum.map(Localization.additional_locales(), &"/#{&1}")
  end

  defp descendant_prefix?(prefix, prefixes) do
    Enum.any?(prefixes, fn other_prefix ->
      other_prefix != prefix and String.starts_with?(other_prefix, prefix <> "/")
    end)
  end

  defp sort_key("/$"), do: {0, "/"}

  defp sort_key(pattern) do
    {1, String.trim_trailing(pattern, "$"), String.ends_with?(pattern, "$")}
  end

  defp disallow_lines do
    @disallow_sections
    |> Enum.with_index()
    |> Enum.flat_map(fn {{comment, paths}, index} ->
      lines = [comment] ++ Enum.map(paths, &"Disallow: #{&1}")

      if index == length(@disallow_sections) - 1 do
        lines
      else
        lines ++ [""]
      end
    end)
  end
end
