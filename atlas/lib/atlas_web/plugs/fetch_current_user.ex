defmodule AtlasWeb.Plugs.FetchCurrentUser do
  import Plug.Conn

  alias Atlas.Demo
  alias Atlas.Users

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)

    cond do
      Demo.enabled?() -> assign(conn, :current_user, Demo.user())
      user_id -> assign(conn, :current_user, Users.get_user(user_id))
      true -> assign(conn, :current_user, nil)
    end
  end
end
