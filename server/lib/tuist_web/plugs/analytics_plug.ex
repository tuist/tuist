defmodule TuistWeb.AnalyticsPlug do
  @moduledoc ~S"""
  This plug is responsible for sending analytics events
  """
  use TuistWeb, :controller

  import Plug.Conn

  alias Tuist.Analytics
  alias TuistWeb.Authentication

  def init(:track_page_view), do: :track_page_view

  def call(%{request_path: request_path} = conn, :track_page_view) do
    current_user = Authentication.current_user(conn)

    if not is_nil(current_user) do
      Analytics.page_view(request_path, current_user)
    end

    conn
  end
end
