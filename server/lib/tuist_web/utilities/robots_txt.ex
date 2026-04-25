defmodule TuistWeb.Utilities.RobotsTxt do
  @moduledoc """
  Builds the runtime robots.txt payload for Tuist's public site.

  Public Content-Usage entries come from explicit Phoenix route metadata.
  Routes without robots metadata default to Disallow entries derived from the
  router so crawler policy stays aligned with the application.
  """

  alias TuistWeb.Marketing.Localization
  alias TuistWeb.Router

  def render do
    lines =
      [
        "User-agent: *",
        "Content-Signal: ai-train=no, search=no, ai-input=no",
        "",
        "# Keep the coarse site-wide signal restrictive, then opt public docs and",
        "# marketing content back in with path-specific Content-Usage rules.",
        "Content-Usage: train-ai=n, search=n"
      ] ++ Enum.map(content_usage_entries(), &content_usage_line/1)

    lines =
      case disallow_patterns() do
        [] -> lines
        patterns -> lines ++ [""] ++ Enum.map(patterns, &"Disallow: #{&1}")
      end

    Enum.join(lines, "\n") <> "\n"
  end

  def content_usage_entries do
    prefixes = prefixes_by_route(content_usage_routes())
    prefix_keys = Map.keys(prefixes)

    prefix_entries =
      Enum.map(prefixes, fn {prefix, route_group} ->
        %{
          pattern: pattern_for(prefix, route_group.dynamic?, prefix_keys),
          content_usage: route_group.content_usage
        }
      end)

    prefix_pattern_entries = Enum.reject(prefix_entries, &String.ends_with?(&1.pattern, "$"))

    prefix_entries
    |> Enum.reject(fn entry ->
      normalized_pattern = String.trim_trailing(entry.pattern, "$")

      Enum.any?(prefix_pattern_entries, fn prefix_entry ->
        prefix_entry != entry and
          prefix_entry.content_usage == entry.content_usage and
          String.starts_with?(
            normalized_pattern,
            String.trim_trailing(prefix_entry.pattern, "$") <> "/"
          )
      end)
    end)
    |> Enum.sort_by(&sort_key(&1.pattern))
  end

  def disallow_patterns do
    routes = Router.__routes__()
    default_disallow_paths = Enum.map(default_disallow_routes(routes), & &1.path)
    exempt_paths = Enum.map(exempt_routes(routes), & &1.path)

    routes
    |> Enum.flat_map(&route_disallow_patterns(&1, exempt_paths, default_disallow_paths))
    |> Enum.uniq()
    |> remove_covered_patterns()
    |> Enum.sort_by(&disallow_sort_key/1)
  end

  defp content_usage_routes do
    Enum.filter(Router.__routes__(), &content_usage_route?/1)
  end

  defp default_disallow_routes(routes) do
    Enum.filter(routes, &default_disallow_route?/1)
  end

  defp exempt_routes(routes) do
    Enum.filter(routes, &exempt_route?/1)
  end

  defp content_usage_route?(%{verb: :get, metadata: metadata}) when is_map(metadata) do
    not is_nil(content_usage_config(metadata))
  end

  defp content_usage_route?(_), do: false

  defp default_disallow_route?(%{metadata: metadata}) when is_map(metadata) do
    robots_txt_setting(metadata) == :default_disallow
  end

  defp default_disallow_route?(_), do: false

  defp exempt_route?(%{metadata: metadata}) when is_map(metadata) do
    case robots_txt_setting(metadata) do
      :default_disallow -> false
      _ -> true
    end
  end

  defp exempt_route?(_), do: false

  defp route_disallow_patterns(%{path: path, metadata: metadata}, exempt_paths, default_disallow_paths)
       when is_map(metadata) do
    case robots_txt_setting(metadata) do
      :default_disallow ->
        path
        |> default_disallow_candidates()
        |> Enum.find(&safe_disallow_pattern?(&1, exempt_paths))
        |> case do
          nil -> []
          pattern -> [format_disallow_pattern(pattern, default_disallow_paths)]
        end

      _ ->
        []
    end
  end

  defp route_disallow_patterns(_route, _exempt_paths, _default_disallow_paths), do: []

  defp safe_disallow_pattern?(pattern, exempt_paths) do
    not Enum.any?(exempt_paths, &disallow_pattern_matches_path?(pattern, &1))
  end

  defp default_disallow_candidates(path) do
    segments = String.split(path, "/", trim: true)

    case Enum.find_index(segments, &(not dynamic_segment?(&1))) do
      nil ->
        []

      0 ->
        incremental_path_patterns(segments, "")

      index ->
        segments
        |> Enum.drop(index)
        |> incremental_path_patterns("/*")
    end
  end

  defp incremental_path_patterns(segments, prefix) do
    Enum.map(1..length(segments), fn count ->
      pattern_tail =
        segments
        |> Enum.take(count)
        |> Enum.map_join("/", &path_pattern_segment/1)

      case prefix do
        "" -> "/" <> pattern_tail
        _ -> prefix <> "/" <> pattern_tail
      end
    end)
  end

  defp path_pattern_segment(segment) do
    if dynamic_segment?(segment), do: "*", else: segment
  end

  defp format_disallow_pattern(pattern, default_disallow_paths) do
    cond do
      String.contains?(pattern, "*") ->
        pattern

      pattern in default_disallow_paths ->
        pattern

      Enum.any?(default_disallow_paths, &String.starts_with?(&1, pattern <> "/")) ->
        pattern <> "/"

      true ->
        pattern
    end
  end

  defp remove_covered_patterns(patterns) do
    patterns
    |> Enum.sort_by(&{String.length(&1), &1})
    |> Enum.reduce([], fn pattern, acc ->
      if Enum.any?(acc, &disallow_pattern_matches_path?(&1, pattern)) do
        acc
      else
        acc ++ [pattern]
      end
    end)
  end

  defp disallow_pattern_matches_path?(pattern, path) do
    pattern
    |> Regex.escape()
    |> String.replace("\\*", ".*")
    |> then(&Regex.match?(~r/^#{&1}/, path))
  end

  defp prefixes_by_route(routes) do
    Enum.reduce(routes, %{}, fn route, acc ->
      route
      |> route_prefixes()
      |> Enum.reduce(acc, fn {prefix, dynamic?, content_usage}, acc ->
        Map.update(
          acc,
          prefix,
          %{dynamic?: dynamic?, content_usage: content_usage},
          fn existing ->
            if existing.content_usage != content_usage do
              raise ArgumentError,
                    "conflicting robots.txt content usage for #{prefix}: #{inspect(existing.content_usage)} vs #{inspect(content_usage)}"
            end

            %{existing | dynamic?: existing.dynamic? or dynamic?}
          end
        )
      end)
    end)
  end

  defp route_prefixes(%{path: "/:locale/docs-markdown/*path", metadata: metadata}) do
    content_usage = content_usage_config(metadata)

    Enum.map(Localization.all_locales(), &{"/#{&1}/docs-markdown", true, content_usage})
  end

  defp route_prefixes(%{path: path, metadata: metadata}) do
    content_usage = content_usage_config(metadata)

    case path_prefix(path) do
      nil -> []
      prefix -> [{prefix, dynamic_route?(path), content_usage}]
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

  defp robots_txt_setting(metadata) do
    case Map.fetch(metadata, :robots_txt) do
      :error -> :default_disallow
      {:ok, false} -> :no_robots_txt
      {:ok, nil} -> :no_robots_txt
      {:ok, robots_txt} -> normalize_robots_txt_setting(robots_txt)
    end
  end

  defp normalize_robots_txt_setting(robots_txt) do
    case normalize_content_usage_config(robots_txt) do
      nil -> :no_robots_txt
      content_usage -> %{content_usage: content_usage}
    end
  end

  defp content_usage_config(metadata) do
    metadata
    |> robots_txt_setting()
    |> case do
      %{content_usage: content_usage} -> content_usage
      _ -> nil
    end
  end

  defp normalize_content_usage_config(nil), do: nil

  defp normalize_content_usage_config(content_usage) when is_map(content_usage) do
    normalize_content_usage_config(Map.to_list(content_usage))
  end

  defp normalize_content_usage_config(content_usage) when is_list(content_usage) do
    content_usage
    |> Enum.filter(fn {key, _value} -> not is_nil(normalize_robots_txt_key(key)) end)
    |> case do
      [] -> nil
      pairs -> sort_robots_txt_pairs(pairs)
    end
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

  defp content_usage_line(%{pattern: pattern, content_usage: content_usage}) do
    directives =
      Enum.map_join(content_usage, ", ", fn {key, value} ->
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

  defp disallow_sort_key(pattern) do
    {String.starts_with?(pattern, "/*"), pattern}
  end
end
