defmodule CacheWeb.Plugs.ObservabilityContextPlug do
  @moduledoc """
  Plug to set selected account/project observability context from request parameters.
  """

  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    {account_handle, project_handle} = extract_handles(conn.query_params)
    set_context(account_handle, project_handle)
    conn
  end

  defp extract_handles(%{"account_handle" => account, "project_handle" => project}) do
    {account, project}
  end

  defp extract_handles(_), do: {nil, nil}

  defp set_context(account_handle, project_handle)
       when is_binary(account_handle) and is_binary(project_handle) and account_handle != "" and project_handle != "" do
    Logger.metadata(
      selected_account_handle: account_handle,
      selected_project_handle: project_handle
    )

    OpenTelemetry.Tracer.set_attribute("selected_account_handle", account_handle)
    OpenTelemetry.Tracer.set_attribute("selected_project_handle", project_handle)
  end

  defp set_context(_, _), do: :ok
end
