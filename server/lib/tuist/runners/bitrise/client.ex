defmodule Tuist.Runners.Bitrise.Client do
  @moduledoc """
  Bitrise REST API (`api.bitrise.io/v0.1`) client.

  Bitrise exposes no queue for self-hosted runner pools, so demand is read
  from the workspace's unfinished builds: a build with no
  `started_on_worker_at` on a pool's stack is waiting for an agent. The
  same build endpoint later reports how it finished.
  """

  alias Tuist.Runners.Bitrise.Connection

  @base_url "https://api.bitrise.io/v0.1"
  @request_timeout to_timeout(second: 15)
  @page_limit 50
  @max_pages 10

  @doc """
  Every unfinished build in the connection's workspace, newest first.

  Bounded at #{@max_pages} pages of #{@page_limit}; a workspace with more
  unfinished builds than that is read again on the next pass.
  """
  def list_unfinished_builds(%Connection{} = connection) do
    list_pages(connection, nil, @max_pages, [])
  end

  defp list_pages(_connection, _next, 0, acc), do: {:ok, Enum.reverse(acc)}

  defp list_pages(connection, next, pages_left, acc) do
    params =
      Enum.reject([owner_slug: connection.workspace_slug, status: 0, limit: @page_limit, next: next], fn {_key, value} ->
        is_nil(value)
      end)

    case request(connection, "/builds", params: params) do
      {:ok, %{"data" => builds} = body} when is_list(builds) ->
        acc = Enum.reduce(builds, acc, &[normalize_build(&1) | &2])

        case get_in(body, ["paging", "next"]) do
          next when is_binary(next) and next != "" -> list_pages(connection, next, pages_left - 1, acc)
          _ -> {:ok, Enum.reverse(acc)}
        end

      {:ok, body} ->
        {:error, {:unexpected_body, truncate(body)}}

      {:error, _reason} = error ->
        error
    end
  end

  @doc """
  One build of `app_slug`.
  """
  def get_build(%Connection{} = connection, app_slug, build_slug) do
    case request(connection, "/apps/#{URI.encode(app_slug)}/builds/#{URI.encode(build_slug)}") do
      {:ok, %{"data" => build}} when is_map(build) -> {:ok, normalize_build(Map.put_new(build, "app_slug", app_slug))}
      {:ok, body} -> {:error, {:unexpected_body, truncate(body)}}
      {:error, _reason} = error -> error
    end
  end

  defp normalize_build(build) do
    %{
      build_slug: Map.get(build, "slug"),
      app_slug: get_in(build, ["repository", "slug"]) || Map.get(build, "app_slug"),
      app_title: get_in(build, ["repository", "title"]) || "",
      stack_identifier: Map.get(build, "stack_identifier") || "",
      build_number: Map.get(build, "build_number") || 0,
      status: Map.get(build, "status"),
      abort_reason: Map.get(build, "abort_reason"),
      branch: Map.get(build, "branch") || "",
      commit_hash: Map.get(build, "commit_hash") || "",
      triggered_workflow: Map.get(build, "triggered_workflow") || "",
      triggered_at: parse_datetime(Map.get(build, "triggered_at")),
      started_on_worker_at: parse_datetime(Map.get(build, "started_on_worker_at")),
      finished_at: parse_datetime(Map.get(build, "finished_at"))
    }
  end

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, %DateTime{microsecond: {usec, _precision}} = datetime, _offset} -> %{datetime | microsecond: {usec, 6}}
      {:error, _reason} -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp request(%Connection{api_token: token}, path, opts \\ []) do
    options =
      [
        method: :get,
        url: @base_url <> path,
        headers: [
          {"authorization", token},
          {"accept", "application/json"},
          {"user-agent", "tuist-runners"}
        ],
        receive_timeout: @request_timeout,
        retry: false,
        finch: Tuist.Finch
      ] ++ opts

    case Req.request(options) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: 401}} -> {:error, :unauthorized}
      {:ok, %{status: 403}} -> {:error, :forbidden}
      {:ok, %{status: 404}} -> {:error, :not_found}
      {:ok, %{status: 429}} -> {:error, :rate_limited}
      {:ok, %{status: status, body: body}} -> {:error, {:unexpected_status, status, truncate(body)}}
      {:error, reason} -> {:error, {:transport, reason}}
    end
  end

  defp truncate(body) when is_binary(body), do: String.slice(body, 0, 500)
  defp truncate(body), do: body |> inspect() |> String.slice(0, 500)
end
