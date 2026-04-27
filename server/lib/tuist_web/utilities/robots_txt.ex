defmodule TuistWeb.Utilities.RobotsTxt do
  @moduledoc """
  Builds the runtime robots.txt payload for Tuist's public site.

  Public Content-Usage entries come from explicit Phoenix route metadata.
  Routes without robots metadata default to Disallow entries derived from the
  router so crawler policy stays aligned with the application.
  """

  alias TuistWeb.Marketing.Localization
  alias TuistWeb.Router

  @robots_txt_header [
    "User-agent: *",
    "Content-Signal: ai-train=no, search=no, ai-input=no",
    "",
    "# Keep the coarse site-wide signal restrictive, then opt public docs and",
    "# marketing content back in with path-specific Content-Usage rules.",
    "Content-Usage: train-ai=n, search=n"
  ]
  @wildcard_segment "*"

  def render do
    route_infos = route_infos()

    [
      @robots_txt_header,
      Enum.map(content_usage_entries(route_infos), &content_usage_line/1),
      disallow_lines(disallow_patterns(route_infos))
    ]
    |> List.flatten()
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  def content_usage_entries do
    content_usage_entries(route_infos())
  end

  def disallow_patterns do
    disallow_patterns(route_infos())
  end

  defp content_usage_entries(route_infos) do
    prefixes =
      route_infos
      |> content_usage_routes()
      |> content_usage_prefixes()
      |> Map.values()

    entries = Enum.map(prefixes, &content_usage_entry(&1, prefixes))

    entries
    |> Enum.reject(&redundant_content_usage_entry?(&1, entries))
    |> Enum.sort_by(&sort_key(&1.pattern))
    |> Enum.map(&Map.take(&1, [:pattern, :content_usage]))
  end

  defp disallow_patterns(route_infos) do
    exempt_paths = route_infos |> exempt_routes() |> Enum.map(& &1.path)
    default_disallow_paths = route_infos |> default_disallow_routes() |> Enum.map(& &1.path)

    default_disallow_paths
    |> Enum.map(&best_disallow_pattern(&1, exempt_paths, default_disallow_paths))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.rendered)
    |> remove_covered_patterns()
    |> Enum.map(& &1.rendered)
    |> Enum.sort_by(&disallow_sort_key/1)
  end

  defp route_infos do
    Enum.map(Router.__routes__(), &route_info/1)
  end

  defp route_info(%{path: path, verb: verb} = route) do
    metadata = route_metadata(route)
    robots_txt = robots_txt_setting(metadata)

    %{
      verb: verb,
      path: path_info(path),
      robots_txt: robots_txt,
      content_usage: content_usage_from_setting(robots_txt)
    }
  end

  defp route_metadata(%{metadata: metadata}) when is_map(metadata), do: metadata
  defp route_metadata(_), do: %{}

  defp content_usage_routes(route_infos) do
    Enum.filter(route_infos, fn route ->
      route.verb == :get and not is_nil(route.content_usage)
    end)
  end

  defp default_disallow_routes(route_infos) do
    Enum.filter(route_infos, &default_disallow_route?/1)
  end

  defp exempt_routes(route_infos) do
    Enum.reject(route_infos, &default_disallow_route?/1)
  end

  defp default_disallow_route?(%{robots_txt: :default_disallow}), do: true
  defp default_disallow_route?(_), do: false

  defp content_usage_prefixes(route_infos) do
    Enum.reduce(route_infos, %{}, fn route, prefixes ->
      Enum.reduce(route_prefixes(route), prefixes, &put_content_usage_prefix/2)
    end)
  end

  defp route_prefixes(%{path: %{raw: "/:locale/docs-markdown/*path"}, content_usage: content_usage}) do
    Enum.map(Localization.all_locales(), fn locale ->
      %{
        path: path_info_from_segments([locale, "docs-markdown"]),
        dynamic?: true,
        content_usage: content_usage
      }
    end)
  end

  defp route_prefixes(%{path: path, content_usage: content_usage}) do
    case static_prefix(path) do
      nil -> []
      prefix -> [%{path: prefix, dynamic?: path.dynamic?, content_usage: content_usage}]
    end
  end

  defp put_content_usage_prefix(prefix, prefixes) do
    Map.update(prefixes, prefix.path.raw, prefix, fn existing ->
      merge_content_usage_prefix(existing, prefix)
    end)
  end

  defp merge_content_usage_prefix(existing, prefix) do
    if existing.content_usage != prefix.content_usage do
      raise ArgumentError,
            "conflicting robots.txt content usage for #{prefix.path.raw}: #{inspect(existing.content_usage)} vs #{inspect(prefix.content_usage)}"
    end

    %{existing | dynamic?: existing.dynamic? or prefix.dynamic?}
  end

  defp content_usage_entry(prefix, prefixes) do
    prefix_pattern? = content_usage_prefix_pattern?(prefix, prefixes)

    %{
      path: prefix.path,
      pattern: content_usage_pattern(prefix.path, prefix_pattern?),
      prefix_pattern?: prefix_pattern?,
      content_usage: prefix.content_usage
    }
  end

  defp content_usage_pattern(%{segments: []}, _prefix_pattern?), do: "/$"
  defp content_usage_pattern(path, true), do: path.raw
  defp content_usage_pattern(path, false), do: path.raw <> "$"

  defp content_usage_prefix_pattern?(%{path: %{segments: []}}, _prefixes), do: false

  defp content_usage_prefix_pattern?(prefix, prefixes) do
    prefix.dynamic? or locale_root?(prefix.path) or descendant_content_prefix?(prefix, prefixes)
  end

  defp descendant_content_prefix?(prefix, prefixes) do
    Enum.any?(prefixes, fn other ->
      other != prefix and path_prefix?(prefix.path.segments, other.path.segments)
    end)
  end

  defp redundant_content_usage_entry?(entry, entries) do
    Enum.any?(entries, fn other ->
      other != entry and
        other.prefix_pattern? and
        other.content_usage == entry.content_usage and
        path_prefix?(other.path.segments, entry.path.segments)
    end)
  end

  defp best_disallow_pattern(path, exempt_paths, default_disallow_paths) do
    path
    |> disallow_candidates()
    |> Enum.find(&safe_disallow_pattern?(&1, exempt_paths))
    |> case do
      nil -> nil
      candidate -> finalize_disallow_pattern(candidate, default_disallow_paths)
    end
  end

  defp disallow_candidates(path) do
    case first_static_segment_index(path.segments) do
      nil ->
        []

      index ->
        wildcard_prefix = if index == 0, do: [], else: [@wildcard_segment]
        suffix_segments = Enum.drop(path.segments, index)

        Enum.map(1..length(suffix_segments), fn count ->
          suffix_segments
          |> Enum.take(count)
          |> Enum.map(&disallow_candidate_segment/1)
          |> then(&(wildcard_prefix ++ &1))
          |> path_info_from_segments()
        end)
    end
  end

  defp safe_disallow_pattern?(pattern, exempt_paths) do
    not Enum.any?(exempt_paths, &disallow_pattern_matches?(pattern, &1))
  end

  defp finalize_disallow_pattern(candidate, default_disallow_paths) do
    trailing_slash? = needs_trailing_slash?(candidate, default_disallow_paths)

    %{
      segments: candidate.segments,
      trailing_slash?: trailing_slash?,
      rendered: render_disallow_pattern(candidate.segments, trailing_slash?)
    }
  end

  defp needs_trailing_slash?(candidate, default_disallow_paths) do
    cond do
      wildcard_path?(candidate) ->
        false

      Enum.any?(default_disallow_paths, &same_path?(&1, candidate)) ->
        false

      Enum.any?(default_disallow_paths, &strict_path_prefix?(candidate, &1)) ->
        true

      true ->
        false
    end
  end

  defp remove_covered_patterns(patterns) do
    patterns
    |> Enum.sort_by(&{length(&1.segments), &1.rendered})
    |> Enum.reduce([], fn pattern, acc ->
      if Enum.any?(acc, &disallow_pattern_matches?(&1, pattern)) do
        acc
      else
        [pattern | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp disallow_pattern_matches?(pattern, path) do
    wildcard_prefix?(pattern.segments, path.segments) and
      not (Map.get(pattern, :trailing_slash?, false) and same_length_path?(pattern, path))
  end

  defp wildcard_prefix?(pattern_segments, path_segments) do
    length(pattern_segments) <= length(path_segments) and
      pattern_segments
      |> Enum.zip(path_segments)
      |> Enum.all?(fn
        {@wildcard_segment, _segment} -> true
        {segment, segment} -> true
        _ -> false
      end)
  end

  defp path_info(path) do
    uri = URI.parse(path)
    raw_path = uri.path || "/"
    segments = path_segments(raw_path)

    %{
      raw: raw_path,
      segments: segments,
      dynamic?: Enum.any?(segments, &dynamic_segment?/1)
    }
  end

  defp path_info_from_segments(segments) do
    %{
      raw: build_path(segments),
      segments: segments,
      dynamic?: Enum.any?(segments, &dynamic_segment?/1)
    }
  end

  defp static_prefix(%{raw: "/", segments: []} = path), do: path

  defp static_prefix(path) do
    path.segments
    |> Enum.take_while(&(not dynamic_segment?(&1)))
    |> case do
      [] -> nil
      segments -> path_info_from_segments(segments)
    end
  end

  defp path_segments(path) do
    path
    |> Path.split()
    |> Enum.reject(&(&1 == "/"))
  end

  defp build_path([]), do: "/"

  defp build_path(segments) do
    URI.to_string(%URI{path: "/" <> Path.join(segments)})
  end

  defp first_static_segment_index(segments) do
    Enum.find_index(segments, &(not dynamic_segment?(&1)))
  end

  defp disallow_candidate_segment(segment) do
    if dynamic_segment?(segment), do: @wildcard_segment, else: segment
  end

  defp dynamic_segment?(segment) do
    String.starts_with?(segment, ":") or String.starts_with?(segment, @wildcard_segment)
  end

  defp wildcard_path?(path) do
    Enum.any?(path.segments, &(&1 == @wildcard_segment))
  end

  defp same_path?(left, right), do: left.segments == right.segments
  defp same_length_path?(left, right), do: length(left.segments) == length(right.segments)

  defp strict_path_prefix?(prefix, path) do
    path_prefix?(prefix.segments, path.segments) and not same_path?(prefix, path)
  end

  defp path_prefix?(prefix_segments, path_segments) do
    Enum.take(path_segments, length(prefix_segments)) == prefix_segments
  end

  defp render_disallow_pattern(segments, false), do: build_path(segments)
  defp render_disallow_pattern(segments, true), do: build_path(segments) <> "/"

  defp disallow_lines([]), do: []

  defp disallow_lines(patterns) do
    [""] ++ Enum.map(patterns, &"Disallow: #{&1}")
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

  defp content_usage_from_setting(%{content_usage: content_usage}), do: content_usage
  defp content_usage_from_setting(_), do: nil

  defp normalize_content_usage_config(nil), do: nil

  defp normalize_content_usage_config(content_usage) when is_map(content_usage) do
    content_usage
    |> Map.to_list()
    |> normalize_content_usage_config()
  end

  defp normalize_content_usage_config(content_usage) when is_list(content_usage) do
    content_usage
    |> Enum.reduce([], fn {key, value}, pairs ->
      case normalize_robots_txt_key(key) do
        nil -> pairs
        normalized_key -> [{normalized_key, value} | pairs]
      end
    end)
    |> case do
      [] -> nil
      pairs -> pairs |> Enum.reverse() |> sort_robots_txt_pairs()
    end
  end

  defp normalize_content_usage_config(_), do: nil

  defp sort_robots_txt_pairs(robots_txt_pairs) do
    Enum.sort_by(robots_txt_pairs, fn {key, _value} ->
      {robots_txt_key_order(key), robots_txt_key_name(key)}
    end)
  end

  defp robots_txt_key_order(:train_ai), do: 0
  defp robots_txt_key_order(:search), do: 1
  defp robots_txt_key_order(:ai_input), do: 2
  defp robots_txt_key_order(_), do: 3

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

  defp locale_root?(%{segments: [locale]}) do
    locale in Localization.additional_locales()
  end

  defp locale_root?(_), do: false

  defp sort_key("/$"), do: {0, "/"}

  defp sort_key(pattern) do
    {1, String.trim_trailing(pattern, "$"), String.ends_with?(pattern, "$")}
  end

  defp disallow_sort_key(pattern) do
    {String.starts_with?(pattern, "/*"), pattern}
  end
end
