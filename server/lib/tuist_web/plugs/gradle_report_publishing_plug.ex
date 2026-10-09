defmodule TuistWeb.Plugs.GradleReportPublishingPlug do
  @moduledoc """
  Authorizes only Gradle build-report creation. Network-trusted publishers do
  not become authenticated subjects and receive no other build permissions.
  """
  use TuistWeb, :controller

  alias Tuist.Environment
  alias TuistWeb.API.Authorization.AuthorizationPlug
  alias TuistWeb.Authentication
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Plugs.LoaderPlug
  alias TuistWeb.RateLimit

  @limits [tasks: 20_000, machine_metrics: 5_000, configuration_operations: 5_000, artifact_transforms: 5_000]

  def init(opts), do: opts

  def call(conn, :preflight) do
    if Authentication.authenticated?(conn) do
      conn
    else
      conn = call(conn, [])
      if conn.halted, do: conn, else: put_private(conn, :network_publication_authorized, true)
    end
  end

  def call(%{private: %{network_publication_authorized: true}} = conn, _opts), do: conn

  def call(conn, _opts) do
    loaded_conn =
      if Authentication.authenticated?(conn) do
        LoaderPlug.call(conn, [])
      else
        # Publishing policy must observe revocation immediately on every node.
        conn |> assign(:caching, false) |> LoaderPlug.call([])
      end

    authorize_publication(loaded_conn)
  rescue
    error in NotFoundError ->
      if Authentication.authenticated?(conn), do: reraise(error, __STACKTRACE__), else: deny_publication(conn)
  end

  defp authorize_publication(%{assigns: %{selected_project: project}} = conn) do
    cond do
      Authentication.authenticated?(conn) ->
        AuthorizationPlug.authorize_project(conn, :build, action: :create)

      not Environment.network_trusted_build_publishing_enabled?() or not project.network_trusted_builds ->
        deny_publication(conn)

      project.build_system != :gradle ->
        deny_publication(conn)

      not json_report?(conn) ->
        reject(conn, :unsupported_media_type, "Network-trusted reports require application/json.")

      not bounded_report?(conn.body_params) ->
        reject(conn, 413, "The report exceeds network-trusted publishing limits.")

      true ->
        limit(conn, project.id)
    end
  end

  defp json_report?(conn) do
    case get_req_header(conn, "content-type") do
      [value] -> match?({:ok, "application", "json", _}, Plug.Conn.Utils.media_type(value))
      _ -> false
    end
  end

  defp bounded_report?(body) do
    Enum.all?(@limits, fn {key, maximum} ->
      value = Map.get(body, key) || Map.get(body, Atom.to_string(key)) || []
      is_list(value) and length(value) <= maximum
    end)
  end

  defp limit(conn, project_id) do
    with :ok <- quota("network-builds:minute:#{project_id}", 60, to_timeout(minute: 1)),
         :ok <- quota("network-builds:day:#{project_id}", 10_000, to_timeout(day: 1)) do
      conn
    else
      {:deny, retry_after} ->
        conn
        |> put_resp_header("retry-after", Integer.to_string(retry_after))
        |> reject(:too_many_requests, "Network-trusted publishing quota exceeded.")

      {:error, :unavailable} ->
        reject(conn, :service_unavailable, "Publishing quota service is unavailable.")
    end
  end

  defp quota(key, limit, window) do
    case RateLimit.hit(key, limit: limit, window: window, fallback: false) do
      {:allow, _} -> :ok
      {:deny, remaining_ms} -> {:deny, max(1, div(remaining_ms + 999, 1000))}
      {:error, :unavailable} = error -> error
    end
  end

  defp deny_publication(conn), do: reject(conn, :forbidden, "This project does not accept network-trusted publishing.")

  defp reject(conn, status, message) do
    conn |> put_status(status) |> json(%{message: message}) |> halt()
  end
end
