defmodule TuistWeb.Plugs.SentryContextPlug do
  @moduledoc """
  Projects allowlisted authenticated and selected-resource attribution to Sentry.
  IDs are searchable tags as well as extras; legacy account handles are retained.
  """

  alias Tuist.Observability
  alias TuistWeb.Authentication

  def init(opts), do: opts

  def call(conn, _opts) do
    Observability.set_authenticated_subject(Authentication.authenticated_subject(conn))
    conn
  end

  @doc "Sets context after assigning authoritative selected resources to the conn."
  def set_selection_context(conn) do
    Observability.set_selection(conn.assigns)
    conn
  end
end
