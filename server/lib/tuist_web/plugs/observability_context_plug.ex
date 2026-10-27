defmodule TuistWeb.Plugs.ObservabilityContextPlug do
  @moduledoc """
  A plug that sets request observability context in logger metadata and OTel span attributes.
  """

  alias Tuist.Observability
  alias TuistWeb.Authentication

  def init(opts), do: opts

  def call(conn, _opts) do
    set_client_address(conn)
    Observability.set_authenticated_subject(Authentication.authenticated_subject(conn))
    conn
  end

  # The request record is the only place a failed authentication is visible,
  # and a failure carries no account, so without the source address there is
  # nothing to attribute it to and no way to tell one persistent attempt
  # against a single account from an attempt spread across many.
  defp set_client_address(conn) do
    case TuistWeb.RemoteIp.get(conn) do
      address when is_binary(address) ->
        Logger.metadata(client_address: address)
        OpenTelemetry.Tracer.set_attribute("client.address", address)

      _ ->
        :ok
    end
  end

  @doc """
  Sets observability context for the selected project and/or account.
  Call this after assigning :selected_project or :selected_account to the conn.
  """
  def set_selection_context(conn) do
    Observability.set_selection(conn.assigns)
    conn
  end
end
