defmodule Atlas.GTM.Outreach.GitHubSearch do
  @moduledoc false

  alias Atlas.Integrations.GitHubAPI
  alias Atlas.Integrations.GitHubApp

  @build_terms ~w(iOS Swift Xcode xcodebuild SwiftPM Package.swift Project.swift Tuist Fastfile fastlane XcodeGen)

  def search(query, opts \\ []) when is_binary(query) do
    count = Keyword.get(opts, :count, 5)
    get = Keyword.get(opts, :get, &Req.get/2)

    with {:ok, req} <- req(opts),
         {:ok, %{status: 200, body: body}} <- get.(req, url: "/search/code", params: [q: query, per_page: count]) do
      {:ok, results(body, query, req, get)}
    else
      {:ok, %{status: status, body: body}} ->
        {:error, "GitHub code search request returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp req(opts) do
    case Keyword.get(opts, :req) do
      nil -> app_req(opts)
      req -> {:ok, req}
    end
  end

  defp app_req(opts) do
    with {:ok, app} <- app(opts),
         {:ok, installation_id} <- installation_id(app, opts) do
      GitHubAPI.req(%{app | installation_id: installation_id})
    end
  end

  defp app(opts) do
    config = Keyword.get(opts, :github_app_config, Application.get_env(:atlas, :github_app, []))

    with app_id when is_binary(app_id) and app_id != "" <- Keyword.get(config, :app_id),
         private_key when is_binary(private_key) and private_key != "" <- Keyword.get(config, :private_key) do
      {:ok,
       %GitHubApp{app_id: app_id, private_key: private_key, installation_id: Keyword.get(config, :installation_id)}}
    else
      _missing -> {:error, :github_app_not_configured}
    end
  end

  defp installation_id(%GitHubApp{installation_id: installation_id}, _opts)
       when is_binary(installation_id) and installation_id != "" do
    {:ok, installation_id}
  end

  defp installation_id(app, opts) do
    owner =
      opts
      |> Keyword.get(:github_app_config, Application.get_env(:atlas, :github_app, []))
      |> Keyword.get(:owner, "tuist")

    GitHubAPI.find_installation_id(app, owner)
  end

  defp results(body, query, req, get) do
    items = Map.get(body, "items", [])
    profiles = owner_profiles(items, req, get)

    items
    |> Enum.map(&result_attrs(&1, query, Map.get(profiles, owner_login(&1))))
    |> Enum.reject(&is_nil/1)
  end

  defp result_attrs(
         %{"repository" => %{"owner" => %{"login" => owner} = owner_attrs} = repository} = item,
         query,
         profile
       )
       when is_binary(owner) do
    path = item["path"] || item["name"] || "repository match"
    source_url = item["html_url"] || repository["html_url"]
    matched_terms = matched_terms([query, path, repository["full_name"]])
    company_name = company_name(owner, owner_attrs, profile)

    %{
      company_name: company_name,
      company_key: company_key(owner, owner_attrs, profile),
      domain: nil,
      source: "github",
      source_ref: source_ref(repository, item),
      source_url: source_url,
      title: "#{repository["full_name"]}: #{path}",
      excerpt: "Public GitHub code search result for #{query}",
      matched_terms: matched_terms,
      signal_kind: signal_kind(matched_terms),
      confidence: confidence(matched_terms),
      observed_at: now(),
      metadata: %{
        "mention_type" => mention_type(matched_terms),
        "repository" => repository["full_name"],
        "repository_url" => repository["html_url"],
        "owner" => owner,
        "owner_type" => owner_attrs["type"],
        "owner_name" => profile["name"],
        "owner_company" => profile_company(profile),
        "owner_url" => profile["html_url"] || owner_attrs["html_url"],
        "person" => person_metadata(owner, owner_attrs, profile, matched_terms),
        "path" => path,
        "query" => query
      }
    }
  end

  defp result_attrs(_item, _query, _profile), do: nil

  defp owner_profiles(items, req, get) do
    items
    |> Enum.map(&owner_login/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Map.new(fn owner -> {owner, owner_profile(owner, req, get)} end)
  end

  defp owner_login(%{"repository" => %{"owner" => %{"login" => owner}}}) when is_binary(owner), do: owner
  defp owner_login(_item), do: nil

  defp owner_profile(owner, req, get) do
    case get.(req, url: "/users/#{owner}") do
      {:ok, %{status: 200, body: body}} when is_map(body) -> body
      _other -> %{}
    end
  end

  defp source_ref(repository, item) do
    item["html_url"] || "#{repository["full_name"]}:#{item["path"] || item["name"]}"
  end

  defp matched_terms(values) do
    text =
      values
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" ")
      |> String.downcase()

    @build_terms
    |> Enum.filter(&String.contains?(text, String.downcase(&1)))
    |> Enum.uniq()
  end

  defp signal_kind(matched_terms) do
    if "Tuist" in matched_terms do
      "tuist_mention"
    else
      "github_repository"
    end
  end

  defp confidence(matched_terms) do
    cond do
      "Tuist" in matched_terms -> 95
      matched_terms == [] -> 72
      true -> 90
    end
  end

  defp mention_type(matched_terms) do
    if "Tuist" in matched_terms, do: "tuist_public_mention"
  end

  defp person_metadata(owner, %{"type" => "User"} = owner_attrs, profile, matched_terms) do
    if "Tuist" in matched_terms do
      %{
        "login" => owner,
        "name" => profile["name"] || owner,
        "company" => profile_company(profile),
        "github_url" => profile["html_url"] || owner_attrs["html_url"],
        "blog" => profile["blog"],
        "title" => "Public Tuist advocate",
        "confidence" => 86
      }
    end
  end

  defp person_metadata(_owner, _owner_attrs, _profile, _matched_terms), do: nil

  defp company_name(owner, %{"type" => "User"}, profile) do
    case profile_company(profile) do
      company when is_binary(company) and company != "" -> company
      _missing -> humanize(owner)
    end
  end

  defp company_name(owner, _owner_attrs, profile) do
    case profile["name"] do
      name when is_binary(name) and name != "" -> name
      _missing -> humanize(owner)
    end
  end

  defp company_key(owner, %{"type" => "User"}, profile) do
    case profile_company(profile) do
      company when is_binary(company) and company != "" -> "github-company:" <> slug(company)
      _missing -> "github:" <> String.downcase(owner)
    end
  end

  defp company_key(owner, _owner_attrs, _profile), do: "github:" <> String.downcase(owner)

  defp profile_company(profile) when is_map(profile) do
    profile
    |> Map.get("company")
    |> normalize_company()
  end

  defp normalize_company(nil), do: nil

  defp normalize_company(company) when is_binary(company) do
    company
    |> String.trim()
    |> String.trim_leading("@")
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp humanize(value) do
    value
    |> String.replace(~r/[-_]+/, " ")
    |> String.split()
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
end
