defmodule Cache.Registry.GitHub do
  @moduledoc """
  GitHub API client for registry ingestion.
  """

  @api_base "https://api.github.com"
  @per_page 100
  @user_agent "tuist-cache-registry"

  def list_tags(repository_full_handle, token) do
    url = "#{@api_base}/repos/#{repository_full_handle}/tags?per_page=#{@per_page}"

    with {:ok, tags} <-
           paginated_get(url, token, fn body ->
             Enum.map(body, &Map.get(&1, "name"))
           end) do
      {:ok, Enum.reject(tags, &is_nil/1)}
    end
  end

  def list_repository_contents(repository_full_handle, token, ref) do
    url = "#{@api_base}/repos/#{repository_full_handle}/contents"

    :get
    |> request(url, token, params: %{ref: ref})
    |> case do
      {:ok, %{status: 200, body: body}} when is_list(body) -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_file_content(repository_full_handle, token, path, ref) do
    url = "#{@api_base}/repos/#{repository_full_handle}/contents/#{path}"

    :get
    |> request(url, token, params: %{ref: ref})
    |> case do
      {:ok, %{status: 200, body: %{"content" => content, "encoding" => "base64"}}} ->
        content
        |> String.replace("\n", "")
        |> Base.decode64()
        |> case do
          {:ok, decoded} -> {:ok, decoded}
          :error -> {:error, :invalid_content}
        end

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def download_zipball(repository_full_handle, token, tag, destination_path) do
    url = "#{@api_base}/repos/#{repository_full_handle}/zipball/refs/tags/#{tag}"

    :get
    |> request(url, token, decode_body: false, into: File.stream!(destination_path, [:write]))
    |> case do
      {:ok, %{status: 200}} -> :ok
      {:ok, %{status: status}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  def fetch_packages_json(token) do
    get_file_content("SwiftPackageIndex/PackageList", token, "packages.json", "main")
  end

  defp paginated_get(url, token, mapper) do
    case request(:get, url, token) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        next_url = next_link(headers)

        results = mapper.(body)

        case next_url do
          nil ->
            {:ok, results}

          _ ->
            with {:ok, next_results} <- paginated_get(next_url, token, mapper) do
              {:ok, results ++ next_results}
            end
        end

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp next_link(headers) do
    Enum.find_value(headers, fn
      {"link", [link_header | _]} -> parse_link_header(link_header)
      {"link", link_header} when is_binary(link_header) -> parse_link_header(link_header)
      _ -> nil
    end)
  end

  defp parse_link_header(link_header) do
    case Regex.run(~r/<([^>]+)>;\s*rel="next"/, link_header) do
      [_, next_url] -> next_url
      _ -> nil
    end
  end

  defp request(method, url, token, opts \\ []) do
    headers =
      [{"user-agent", @user_agent}, {"accept", "application/vnd.github+json"}] ++ auth_header(token)

    req_opts = Keyword.merge([method: method, url: url, headers: headers, finch: Cache.Finch, retry: false], opts)

    Req.request(req_opts)
  end

  defp auth_header(nil), do: []
  defp auth_header(""), do: []
  defp auth_header(token), do: [{"authorization", "Bearer #{token}"}]
end
