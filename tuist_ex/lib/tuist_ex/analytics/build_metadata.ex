defmodule TuistEx.Analytics.BuildMetadata do
  @moduledoc false

  alias TuistEx.HTTP

  @legacy_limit 20
  @limit 64

  def observations(options \\ []) do
    environment = Keyword.get(options, :environment, &System.get_env/1)
    {family, os} = :os.type()
    os = if family == :win32, do: "windows", else: to_string(os)
    version_key = if family == :unix, do: "tuist.os.kernel_version", else: "tuist.os.version"
    version = :os.version()
    processors = :erlang.system_info(:logical_processors_available)

    %{
      "tuist.os.type" => os,
      version_key =>
        if(is_tuple(version),
          do: version |> Tuple.to_list() |> Enum.join("."),
          else: to_string(version)
        ),
      "tuist.host.arch" =>
        :system_architecture
        |> :erlang.system_info()
        |> to_string()
        |> String.split("-", parts: 2)
        |> hd(),
      "tuist.cpu.available_processors" =>
        if(is_integer(processors) and processors > 0, do: to_string(processors)),
      "tuist.process.locale" => environment.("LC_ALL") || environment.("LANG"),
      "tuist.ci.job" => environment.("GITHUB_JOB") || environment.("CI_JOB_NAME"),
      "tuist.ci.runner_environment" => environment.("RUNNER_ENVIRONMENT"),
      "tuist.ci.runner_name" =>
        if(environment.("TUIST_BUILD_METADATA_RUNNER_NAME") == "1",
          do:
            environment.("RUNNER_NAME") || environment.("CI_RUNNER_DESCRIPTION") ||
              environment.("BUILDKITE_AGENT_NAME")
        )
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) or value == "" or byte_size(value) > 500 end)
  rescue
    _ -> %{}
  end

  def enrich(payload, server_url, options \\ []) do
    metadata = Map.get(payload, :custom_metadata) || %{tags: [], values: %{}}
    values = Map.get(metadata, :values, %{})

    observed =
      Keyword.get_lazy(options, :build_metadata_observations, fn -> observations(options) end)

    candidate = Map.merge(observed, values)

    request =
      Keyword.get(options, :metadata_limit_request, fn method, url, body, headers ->
        HTTP.request(method, url, body, headers, timeout: 2_000, connect_timeout: 2_000)
      end)

    limit =
      if map_size(candidate) > @legacy_limit,
        do: discover(server_url, request),
        else: @legacy_limit

    Map.put(payload, :custom_metadata, Map.put(metadata, :values, merge(values, observed, limit)))
  end

  def merge(values, observations, limit) do
    observations
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.reduce(values, fn {key, value}, values ->
      if map_size(values) < limit, do: Map.put_new(values, key, value), else: values
    end)
  end

  def discover(server_url, request) do
    uri = URI.parse(server_url)
    path = String.trim_trailing(uri.path || "", "/") <> "/api/metadata/limits"
    url = URI.to_string(%{uri | path: path, userinfo: nil, query: nil, fragment: nil})

    case request.(:get, url, nil, []) do
      {:ok, 200, %{"max_values" => limit}}
      when is_integer(limit) and limit in @legacy_limit..@limit ->
        limit

      _ ->
        @legacy_limit
    end
  rescue
    _ -> @legacy_limit
  catch
    _, _ -> @legacy_limit
  end
end
