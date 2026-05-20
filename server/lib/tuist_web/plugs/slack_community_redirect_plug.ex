defmodule TuistWeb.Plugs.SlackCommunityRedirectPlug do
  @moduledoc """
  Redirects the dedicated Slack community hostname to the current invite URL.
  """
  import Phoenix.Controller
  import Plug.Conn

  @slack_host Application.compile_env!(:tuist, [:urls, :slack]) |> URI.parse() |> Map.fetch!(:host)
  @slack_invite_url Application.compile_env!(:tuist, [:urls, :slack_invite])

  def init(opts), do: opts

  def call(%Plug.Conn{host: @slack_host} = conn, _opts) do
    conn
    |> put_status(:found)
    |> redirect(external: @slack_invite_url)
    |> halt()
  end

  def call(conn, _opts), do: conn
end
