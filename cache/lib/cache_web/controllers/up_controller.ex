defmodule CacheWeb.UpController do
  use CacheWeb, :controller

  def index(conn, _params) do
    send_resp(conn, :ok, "UP! " <> System.get_env("KAMAL_VERSION"))
  end
end
