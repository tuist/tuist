defmodule AtlasWeb.Plugs.FetchCurrentUser do
  import Plug.Conn

  alias Atlas.Users

  def init(opts), do: opts

  def call(conn, _opts) do
    user_id = get_session(conn, :user_id)

    if user_id do
      assign(conn, :current_user, Users.get_user(user_id))
    else
      assign(conn, :current_user, nil)
    end
  end
end
