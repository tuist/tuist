defmodule LuftServer.OAuth.ResourceOwners do
  @moduledoc "A Boruta grant acts within one live Luft session, not a copy of the Tuist user."
  @behaviour Boruta.Oauth.ResourceOwners

  alias Boruta.Oauth.ResourceOwner
  alias LuftServer.Sessions

  @impl true
  def get_by(sub: id, scope: _scope) do
    case Sessions.get_by_id(id) do
      nil -> {:error, "Session expired."}
      session -> {:ok, %ResourceOwner{sub: session.id, username: session.handle}}
    end
  end

  def get_by(_params), do: {:error, "Sign in through Tuist."}

  @impl true
  def check_password(_owner, _password), do: {:error, "Sign in through Tuist."}

  @impl true
  def authorized_scopes(_owner), do: []
end
