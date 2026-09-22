defmodule Atlas.Search.Federated do
  @moduledoc """
  Federates semantic search across Atlas search domains.

  Callers pass the domains available in the current interface. This module
  validates requested domains and source types before touching any backing
  search implementation, so adapters can keep access policy at their boundary.
  """

  alias Atlas.Documents
  alias Atlas.Search, as: SharedSearch

  @atlas_domain "atlas"
  @documents_domain "documents"
  @document_source_type "document_page"

  @default_limit 10

  def domains, do: [@atlas_domain, @documents_domain]
  def atlas_domain, do: @atlas_domain
  def documents_domain, do: @documents_domain
  def document_source_type, do: @document_source_type

  def source_types, do: SharedSearch.source_types() ++ [@document_source_type]

  def search(query, opts \\ [])

  def search(query, opts) when is_binary(query) do
    limit = Keyword.get(opts, :limit, @default_limit)
    allowed_domains = opts |> Keyword.get(:allowed_domains, [@atlas_domain]) |> normalize_domains()

    with {:ok, source_types} <- normalize_source_types(Keyword.get(opts, :source_types)),
         :ok <- validate_source_types_available(source_types, allowed_domains),
         {:ok, requested_domains} <- requested_domains(Keyword.get(opts, :domains), allowed_domains, source_types),
         {:ok, results} <- search_requested_domains(query, opts, requested_domains, source_types, limit) do
      {:ok,
       %{
         results: results,
         count: length(results),
         domains: requested_domains,
         available_domains: allowed_domains
       }}
    end
  end

  def search(_query, _opts), do: {:error, "query is required."}

  defp search_requested_domains(query, opts, requested_domains, source_types, limit) do
    with {:ok, atlas_results} <- maybe_search_atlas(query, opts, requested_domains, source_types, limit),
         {:ok, document_results} <- maybe_search_documents(query, opts, requested_domains, source_types, limit) do
      results =
        (atlas_results ++ document_results)
        |> Enum.sort_by(&(-score(&1)))
        |> Enum.take(limit)

      {:ok, results}
    end
  end

  defp maybe_search_atlas(query, opts, requested_domains, source_types, limit) do
    if @atlas_domain in requested_domains and atlas_source_types_allowed?(source_types) do
      search_opts =
        [limit: limit]
        |> maybe_put(:source_types, atlas_source_types(source_types))
        |> maybe_put(:account_id, Keyword.get(opts, :account_id))

      with {:ok, results} <- SharedSearch.search(query, search_opts) do
        {:ok, Enum.map(results, &Map.put(&1, :domain, @atlas_domain))}
      end
    else
      {:ok, []}
    end
  end

  defp maybe_search_documents(query, opts, requested_domains, source_types, limit) do
    if @documents_domain in requested_domains and document_source_type_allowed?(source_types) do
      search_opts =
        [limit: limit]
        |> maybe_put(:account_id, Keyword.get(opts, :account_id))

      with {:ok, results} <- Documents.semantic_search(query, search_opts) do
        {:ok, Enum.map(results, &serialize_document_hit/1)}
      end
    else
      {:ok, []}
    end
  end

  defp serialize_document_hit(hit) do
    %{
      id: "#{@document_source_type}:#{hit.id}",
      domain: @documents_domain,
      source_type: @document_source_type,
      source_id: hit.id,
      document_id: hit.document_id,
      page_number: hit.page_number,
      account_id: hit.account_id,
      account_name: hit.account_name,
      title: hit.title,
      excerpt: hit.excerpt,
      path: "/library/documents/#{hit.document_id}",
      metadata:
        compact_map(%{
          "document_id" => hit.document_id,
          "page_number" => hit.page_number,
          "document_type" => hit.document_type,
          "correspondent" => hit.correspondent,
          "summary" => hit.summary
        }),
      score: hit.score,
      inserted_at: nil,
      updated_at: nil
    }
  end

  defp requested_domains(nil, allowed_domains, source_types) do
    {:ok, default_domains_for_source_types(allowed_domains, source_types)}
  end

  defp requested_domains([], allowed_domains, source_types) do
    requested_domains(nil, allowed_domains, source_types)
  end

  defp requested_domains(domains, allowed_domains, _source_types) when is_list(domains) do
    requested = normalize_domains(domains)

    cond do
      requested == [] ->
        {:ok, allowed_domains}

      invalid = Enum.find(requested, &(&1 not in domains())) ->
        {:error, "Unsupported search domain: #{invalid}."}

      unavailable = Enum.find(requested, &(&1 not in allowed_domains)) ->
        {:error, "Search domain #{unavailable} is not available."}

      true ->
        {:ok, requested}
    end
  end

  defp requested_domains(domain, allowed_domains, source_types) when is_binary(domain) do
    requested_domains([domain], allowed_domains, source_types)
  end

  defp requested_domains(_domains, _allowed_domains, _source_types), do: {:error, "Search domains must be strings."}

  defp default_domains_for_source_types(allowed_domains, nil), do: allowed_domains
  defp default_domains_for_source_types(allowed_domains, []), do: allowed_domains

  defp default_domains_for_source_types(allowed_domains, source_types) do
    domains =
      []
      |> append_if(Enum.any?(source_types, &(&1 in SharedSearch.source_types())), @atlas_domain)
      |> append_if(@document_source_type in source_types, @documents_domain)

    Enum.filter(domains, &(&1 in allowed_domains))
  end

  defp validate_source_types_available(nil, _allowed_domains), do: :ok
  defp validate_source_types_available([], _allowed_domains), do: :ok

  defp validate_source_types_available(source_types, allowed_domains) do
    cond do
      invalid = Enum.find(source_types, &(&1 not in source_types())) ->
        {:error, "Unsupported source type: #{invalid}."}

      @document_source_type in source_types and @documents_domain not in allowed_domains ->
        {:error, "Search domain #{@documents_domain} is not available."}

      true ->
        :ok
    end
  end

  defp normalize_source_types(nil), do: {:ok, nil}
  defp normalize_source_types([]), do: {:ok, []}

  defp normalize_source_types(source_types) when is_list(source_types) do
    {:ok, source_types |> Enum.map(&normalize_string/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()}
  end

  defp normalize_source_types(source_type) when is_binary(source_type) do
    normalize_source_types([source_type])
  end

  defp normalize_source_types(_source_types), do: {:error, "Source types must be strings."}

  defp normalize_domains(domains) when is_list(domains) do
    domains
    |> Enum.map(&normalize_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_domains(domain) when is_binary(domain), do: normalize_domains([domain])
  defp normalize_domains(_domains), do: []

  defp normalize_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_string()
  defp normalize_string(_value), do: nil

  defp atlas_source_types_allowed?(nil), do: true
  defp atlas_source_types_allowed?([]), do: true
  defp atlas_source_types_allowed?(source_types), do: Enum.any?(source_types, &(&1 in SharedSearch.source_types()))

  defp document_source_type_allowed?(nil), do: true
  defp document_source_type_allowed?([]), do: true
  defp document_source_type_allowed?(source_types), do: @document_source_type in source_types

  defp atlas_source_types(nil), do: nil
  defp atlas_source_types([]), do: nil

  defp atlas_source_types(source_types) do
    Enum.filter(source_types, &(&1 in SharedSearch.source_types()))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, _key, ""), do: opts
  defp maybe_put(opts, _key, []), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp append_if(list, true, value), do: list ++ [value]
  defp append_if(list, _condition, _value), do: list

  defp compact_map(map) do
    map
    |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
    |> Map.new()
  end

  defp score(result), do: Map.get(result, :score) || 0.0
end
