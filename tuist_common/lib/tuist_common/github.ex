defmodule TuistCommon.GitHub do
  @moduledoc """
  GitHub API client for common operations shared between cache and server.
  """

  @api_base "https://api.github.com"
  @per_page 100
  @user_agent "tuist"
  @rate_limit_event [:tuist_common, :github, :rate_limit]

  @doc """
  Telemetry event emitted with the rate-limit budget GitHub reports on API
  responses. Measurements are `:limit` and `:used`, with the `:resource`
  metadata naming the budget the request was accounted against.
  """
  @spec rate_limit_event_name() :: [atom()]
  def rate_limit_event_name, do: @rate_limit_event

  @doc """
  Lists all tags for a repository.

  ## Options
    * `:finch` - The Finch instance to use for requests (required)
  """
  @spec list_tags(String.t(), String.t() | nil, keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def list_tags(repository_full_handle, token, opts \\ []) do
    url = "#{@api_base}/repos/#{repository_full_handle}/tags?per_page=#{@per_page}"

    with {:ok, tags} <-
           paginated_get(url, token, opts, fn body ->
             Enum.map(body, &Map.get(&1, "name"))
           end) do
      {:ok, Enum.reject(tags, &is_nil/1)}
    end
  end

  @doc """
  Gets repository content at a path using a single request.

  Returns `{:ok, {:file, decoded_content}}` for files and
  `{:ok, {:directory, entries}}` for directories, distinguishing
  by the shape of the GitHub API response.

  ## Options
    * `:finch` - The Finch instance to use for requests (required)
  """
  @spec get_repository_content(String.t(), String.t() | nil, String.t(), String.t(), keyword()) ::
          {:ok, {:file, binary()}} | {:ok, {:directory, list()}} | {:error, term()}
  def get_repository_content(repository_full_handle, token, path, ref, opts \\ []) do
    url = "#{@api_base}/repos/#{repository_full_handle}/contents/#{path}"

    :get
    |> request(url, token, Keyword.put(opts, :params, %{ref: ref}))
    |> case do
      {:ok, %{status: 200, body: %{"content" => content, "encoding" => "base64"}}} ->
        content
        |> String.replace("\n", "")
        |> Base.decode64()
        |> case do
          {:ok, decoded} -> {:ok, {:file, decoded}}
          :error -> {:error, :invalid_content}
        end

      {:ok, %{status: 200, body: body}} when is_list(body) ->
        {:ok, {:directory, body}}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, response} ->
        http_error(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Lists the contents of a repository directory.

  ## Options
    * `:finch` - The Finch instance to use for requests (required)
  """
  @spec list_repository_contents(String.t(), String.t() | nil, String.t(), keyword()) ::
          {:ok, list()} | {:error, term()}
  def list_repository_contents(repository_full_handle, token, ref, opts \\ []) do
    url = "#{@api_base}/repos/#{repository_full_handle}/contents"

    :get
    |> request(url, token, Keyword.put(opts, :params, %{ref: ref}))
    |> case do
      {:ok, %{status: 200, body: body}} when is_list(body) -> {:ok, body}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, response} -> http_error(response)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets the content of a file from a repository.

  ## Options
    * `:finch` - The Finch instance to use for requests (required)
  """
  @spec get_file_content(String.t(), String.t() | nil, String.t(), String.t(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def get_file_content(repository_full_handle, token, path, ref, opts \\ []) do
    url = "#{@api_base}/repos/#{repository_full_handle}/contents/#{path}"

    :get
    |> request(url, token, Keyword.put(opts, :params, %{ref: ref}))
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

      {:ok, response} ->
        http_error(response)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Downloads a zipball of a repository at a specific tag.

  ## Options
    * `:finch` - The Finch instance to use for requests (required)
  """
  @spec download_zipball(String.t(), String.t() | nil, String.t(), String.t(), keyword()) ::
          :ok | {:error, term()}
  def download_zipball(repository_full_handle, token, tag, destination_path, opts \\ []) do
    url = "#{@api_base}/repos/#{repository_full_handle}/zipball/refs/tags/#{tag}"

    request_opts =
      opts
      |> Keyword.put(:decode_body, false)
      |> Keyword.put(:into, File.stream!(destination_path, [:write]))

    :get
    |> request(url, token, request_opts)
    |> case do
      {:ok, %{status: 200}} -> :ok
      {:ok, response} -> http_error(response)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Fetches the packages.json file from the Swift Package Index.

  ## Options
    * `:finch` - The Finch instance to use for requests (required)
  """
  @spec fetch_packages_json(String.t() | nil, keyword()) :: {:ok, binary()} | {:error, term()}
  def fetch_packages_json(token, opts \\ []) do
    get_file_content("SwiftPackageIndex/PackageList", token, "packages.json", "main", opts)
  end

  defp paginated_get(url, token, opts, mapper) do
    case request(:get, url, token, opts) do
      {:ok, %{status: 200, body: body, headers: headers}} ->
        next_url = next_link(headers)

        results = mapper.(body)

        case next_url do
          nil ->
            {:ok, results}

          _ ->
            with {:ok, next_results} <- paginated_get(next_url, token, opts, mapper) do
              {:ok, results ++ next_results}
            end
        end

      {:ok, %{status: status}} when status in [403, 429] ->
        {:error, {:rate_limited, status}}

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

  defp http_error(%{status: 429}), do: {:error, {:rate_limited, 429}}

  defp http_error(%{status: 403, headers: headers}) do
    if rate_limited?(headers) do
      {:error, {:rate_limited, 403}}
    else
      {:error, {:http_error, 403}}
    end
  end

  defp http_error(%{status: status}), do: {:error, {:http_error, status}}

  defp rate_limited?(headers) do
    Enum.any?(headers, fn
      {"retry-after", _value} -> true
      {"x-ratelimit-remaining", value} when value in ["0", ["0"]] -> true
      _header -> false
    end)
  end

  defp request(method, url, token, opts) do
    headers =
      [{"user-agent", @user_agent}, {"accept", "application/vnd.github+json"}] ++
        auth_header(token)

    finch = Keyword.get(opts, :finch)
    retry = Keyword.get(opts, :retry, false)
    params = Keyword.get(opts, :params)
    decode_body = Keyword.get(opts, :decode_body, true)
    into = Keyword.get(opts, :into)

    req_opts =
      [method: method, url: url, headers: headers, retry: retry]
      |> maybe_add_opt(:finch, finch)
      |> maybe_add_opt(:params, params)
      |> maybe_add_opt(:decode_body, decode_body)
      |> maybe_add_opt(:into, into)

    req_opts
    |> Req.request()
    |> tap(&emit_rate_limit_telemetry/1)
  end

  # GitHub reports the budget on every API response, including the 403 that
  # denies the request. Reading it here covers every call site and every
  # resource bucket, which `/rate_limit` polling does not: a 403 can be raised
  # against a bucket other than the one a poller looks at.
  defp emit_rate_limit_telemetry({:ok, response}) when is_map(response) do
    headers = Map.get(response, :headers)

    with limit when is_integer(limit) <- header_integer(headers, "x-ratelimit-limit"),
         used when is_integer(used) <- header_integer(headers, "x-ratelimit-used") do
      :telemetry.execute(@rate_limit_event, %{limit: limit, used: used}, %{
        resource: header_value(headers, "x-ratelimit-resource") || "unknown"
      })
    end

    :ok
  end

  defp emit_rate_limit_telemetry(_result), do: :ok

  defp header_integer(headers, name) do
    case header_value(headers, name) do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {integer, _rest} -> integer
          :error -> nil
        end
    end
  end

  defp header_value(headers, name) when is_map(headers) do
    headers |> Map.get(name) |> first_header_value()
  end

  defp header_value(headers, name) when is_list(headers) do
    Enum.find_value(headers, fn
      {^name, value} -> first_header_value(value)
      _header -> nil
    end)
  end

  defp header_value(_headers, _name), do: nil

  defp first_header_value([value | _rest]), do: first_header_value(value)
  defp first_header_value(value) when is_binary(value), do: value
  defp first_header_value(_value), do: nil

  defp maybe_add_opt(opts, _key, nil), do: opts
  defp maybe_add_opt(opts, :decode_body, true), do: opts
  defp maybe_add_opt(opts, key, value), do: Keyword.put(opts, key, value)

  defp auth_header(nil), do: []
  defp auth_header(""), do: []
  defp auth_header(token), do: [{"authorization", "Bearer #{token}"}]
end
