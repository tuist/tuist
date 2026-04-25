defmodule TuistWeb.Utilities.RobotsTxt do
  @moduledoc """
  Builds the runtime robots.txt payload for Tuist's public site.

  The Content-Usage allowlist is derived from the Phoenix router so public
  marketing and docs routes do not drift from the declared policy.
  """

  alias TuistWeb.Marketing.Localization
  alias TuistWeb.Router

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
       Enum.map(content_usage_entries(), &content_usage_line/1) ++
       [""] ++
       disallow_lines())
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  def content_usage_entries do
    prefixes = prefixes_by_route(content_usage_routes())
    prefix_keys = Map.keys(prefixes)

    prefix_entries =
      Enum.map(prefixes, fn {prefix, route_group} ->
        %{
          pattern: pattern_for(prefix, route_group.dynamic?, prefix_keys),
          robots_txt: route_group.robots_txt
        }
      end)

    prefix_pattern_entries = Enum.reject(prefix_entries, &String.ends_with?(&1.pattern, "$"))

    prefix_entries
    |> Enum.reject(fn entry ->
      normalized_pattern = String.trim_trailing(entry.pattern, "$")

      Enum.any?(prefix_pattern_entries, fn prefix_entry ->
        prefix_entry != entry and
          prefix_entry.robots_txt == entry.robots_txt and
          String.starts_with?(normalized_pattern, String.trim_trailing(prefix_entry.pattern, "$") <> "/")
      end)
    end)
    |> Enum.sort_by(&sort_key(&1.pattern))
  end

  defp content_usage_routes do
    Enum.filter(Router.__routes__(), &content_usage_route?/1)
  end

  defp content_usage_route?(%{verb: :get, metadata: metadata}) when is_map(metadata) do
    not is_nil(robots_txt_config(metadata))
  end

  defp content_usage_route?(_), do: false

  defp prefixes_by_route(routes) do
    Enum.reduce(routes, %{}, fn route, acc ->
      route
      |> route_prefixes()
      |> Enum.reduce(acc, fn {prefix, dynamic?, robots_txt}, acc ->
        Map.update(acc, prefix, %{dynamic?: dynamic?, robots_txt: robots_txt}, fn existing ->
          if existing.robots_txt != robots_txt do
            raise ArgumentError,
                  "conflicting robots.txt config for #{prefix}: #{inspect(existing.robots_txt)} vs #{inspect(robots_txt)}"
          end

          %{existing | dynamic?: existing.dynamic? or dynamic?}
        end)
      end)
    end)
  end

  defp route_prefixes(%{path: "/:locale/docs-markdown/*path", metadata: metadata}) do
    robots_txt = robots_txt_config(metadata)

    Enum.map(Localization.all_locales(), &{"/#{&1}/docs-markdown", true, robots_txt})
  end

  defp route_prefixes(%{path: path, metadata: metadata}) do
    robots_txt = robots_txt_config(metadata)

    case path_prefix(path) do
      nil -> []
      prefix -> [{prefix, dynamic_route?(path), robots_txt}]
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

  defp robots_txt_config(metadata) do
    metadata
    |> Map.get(:robots_txt)
    |> normalize_robots_txt_config()
  end

  defp normalize_robots_txt_config(nil), do: nil

  defp normalize_robots_txt_config(robots_txt) when is_map(robots_txt) do
    robots_txt
    |> Map.to_list()
    |> sort_robots_txt_pairs()
  end

  defp normalize_robots_txt_config(robots_txt) when is_list(robots_txt) do
    robots_txt
    |> Keyword.new()
    |> sort_robots_txt_pairs()
  end

  defp sort_robots_txt_pairs(robots_txt_pairs) do
    Enum.sort_by(robots_txt_pairs, fn {key, _value} ->
      {robots_txt_key_order(key), robots_txt_key_name(key)}
    end)
  end

  defp robots_txt_key_order(key) do
    case normalize_robots_txt_key(key) do
      :train_ai -> 0
      :search -> 1
      :ai_input -> 2
      _ -> 3
    end
  end

  defp normalize_robots_txt_key(:train_ai), do: :train_ai
  defp normalize_robots_txt_key(:search), do: :search
  defp normalize_robots_txt_key(:ai_input), do: :ai_input
  defp normalize_robots_txt_key("train_ai"), do: :train_ai
  defp normalize_robots_txt_key("train-ai"), do: :train_ai
  defp normalize_robots_txt_key("search"), do: :search
  defp normalize_robots_txt_key("ai_input"), do: :ai_input
  defp normalize_robots_txt_key("ai-input"), do: :ai_input
  defp normalize_robots_txt_key(_), do: nil

  defp content_usage_line(%{pattern: pattern, robots_txt: robots_txt}) do
    directives =
      Enum.map_join(robots_txt, ", ", fn {key, value} ->
        "#{robots_txt_key_name(key)}=#{robots_txt_value(value)}"
      end)

    "Content-Usage: #{pattern} #{directives}"
  end

  defp robots_txt_key_name(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", "-")
  end

  defp robots_txt_key_name(key) when is_binary(key) do
    String.replace(key, "_", "-")
  end

  defp robots_txt_value(true), do: "y"
  defp robots_txt_value(false), do: "n"
  defp robots_txt_value(:yes), do: "y"
  defp robots_txt_value(:no), do: "n"
  defp robots_txt_value(:y), do: "y"
  defp robots_txt_value(:n), do: "n"
  defp robots_txt_value("yes"), do: "y"
  defp robots_txt_value("no"), do: "n"
  defp robots_txt_value("y"), do: "y"
  defp robots_txt_value("n"), do: "n"
  defp robots_txt_value(value) when is_atom(value), do: Atom.to_string(value)
  defp robots_txt_value(value) when is_binary(value), do: value

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
