defmodule TuistCloudWeb.AnalyticsPlug do
  @moduledoc ~S"""
  This plug is responsible for sending analytics events
  """
  import Plug.Conn
  use TuistCloudWeb, :controller
  alias TuistCloud.Analytics
  alias TuistCloudWeb.Authentication

  def init(:track_page_view), do: :track_page_view

  def call(%{request_path: request_path} = conn, :track_page_view) do
    current_user = Authentication.current_user(conn)

    if current_user != nil do
      Analytics.page_view(request_path, current_user)
    end

    conn
  end
end
