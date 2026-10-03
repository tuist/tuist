defmodule Atlas.GTM.Outreach.BraveSearch do
  @moduledoc false

  @endpoint "https://api.search.brave.com/res/v1/web/search"
  @build_terms ~w(iOS Swift Xcode xcodebuild SwiftPM Package.swift Tuist fastlane Fastfile XcodeGen)
  @scale_terms [
    "monorepo",
    "platform engineering",
    "mobile platform",
    "developer productivity",
    "build infrastructure",
    "CI",
    "CI/CD"
  ]

  def search(query, opts \\ []) when is_binary(query) do
    request = request(opts)

    with {:ok, api_key} <- api_key(opts),
         {:ok, %{status: 200, body: body}} <-
           request.(
             url: @endpoint,
             headers: [{"X-Subscription-Token", api_key}, {"Accept", "application/json"}],
             params: [q: query, count: Keyword.get(opts, :count, 5)]
           ) do
      {:ok, results(body, query)}
    else
      {:ok, %{status: status, body: body}} ->
        {:error, "Brave Search request returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp results(body, query) do
    body
    |> get_in(["web", "results"])
    |> List.wrap()
    |> Enum.map(&result_attrs(&1, query))
    |> Enum.reject(&is_nil/1)
  end

  defp result_attrs(%{"url" => url} = result, query) when is_binary(url) do
    domain = domain_from_url(url)
    title = result["title"] || url
    excerpt = result["description"]
    matched_terms = matched_terms([query, title, excerpt, url])

    %{
      company_name: company_name(domain, result),
      company_key: company_key(domain, url),
      domain: domain,
      source: "brave",
      source_ref: url,
      source_url: url,
      title: title,
      excerpt: excerpt,
      matched_terms: matched_terms,
      signal_kind: signal_kind([query, title, excerpt, url]),
      confidence: confidence(matched_terms),
      observed_at: now(),
      metadata: %{
        "display_url" => result["profile"] && result["profile"]["url"],
        "mention_type" => mention_type(matched_terms),
        "query" => query
      }
    }
  end

  defp result_attrs(_result, _query), do: nil

  defp api_key(opts) do
    case Keyword.get(opts, :api_key) || Application.get_env(:atlas, :brave_search, [])[:api_key] do
      key when is_binary(key) and key != "" -> {:ok, key}
      _missing -> {:error, :brave_search_api_key_not_configured}
    end
  end

  defp request(opts), do: Keyword.get(opts, :request, &Req.get/1)

  defp matched_terms(values) do
    text =
      values
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    (@build_terms ++ @scale_terms)
    |> Enum.filter(&String.contains?(text, String.downcase(&1)))
    |> Enum.uniq()
  end

  defp signal_kind(values) do
    text =
      values
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    cond do
      String.contains?(text, "tuist") -> "tuist_mention"
      String.contains?(text, "hiring") or String.contains?(text, "jobs") -> "hiring"
      String.contains?(text, "developer productivity") -> "developer_productivity"
      String.contains?(text, "platform engineering") -> "platform_engineering"
      String.contains?(text, "ci") -> "ci_scale"
      true -> "engineering_blog"
    end
  end

  defp confidence(matched_terms) do
    cond do
      "Tuist" in matched_terms -> 90
      Enum.any?(matched_terms, &(&1 in @build_terms)) -> 82
      matched_terms != [] -> 68
      true -> 50
    end
  end

  defp mention_type(matched_terms) do
    if "Tuist" in matched_terms, do: "tuist_public_mention"
  end

  defp domain_from_url(url) do
    uri = URI.parse(url)

    case uri.host do
      host when is_binary(host) ->
        host
        |> String.downcase()
        |> String.replace(~r/^www\./, "")

      _host ->
        nil
    end
  end

  defp company_name(nil, result), do: result["title"] || "Unknown company"

  defp company_name(domain, _result) do
    domain
    |> String.split(".")
    |> List.first()
    |> String.replace(~r/[-_]+/, " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp company_key(domain, _url) when is_binary(domain), do: "domain:#{domain}"

  defp company_key(_domain, url) do
    "url:" <> Base.url_encode64(:crypto.hash(:sha256, url), padding: false)
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
