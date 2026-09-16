defmodule Atlas.OAuth.ResourceOwners do
  @moduledoc false
  @behaviour Boruta.Oauth.ResourceOwners

  alias Atlas.Repo
  alias Atlas.Users.User
  alias Boruta.Oauth.ResourceOwner
  alias Boruta.Oauth.ResourceOwners

  @impl ResourceOwners
  def get_by(username: username) do
    case Repo.get_by(User, email: username) do
      %User{id: id, email: email} ->
        {:ok, %ResourceOwner{sub: to_string(id), username: email}}

      _ ->
        {:error, "User not found."}
    end
  end

  def get_by(attrs) do
    sub = Keyword.fetch!(attrs, :sub)

    case Repo.get_by(User, id: sub) do
      %User{id: id, email: email} ->
        {:ok, %ResourceOwner{sub: to_string(id), username: email}}

      _ ->
        {:error, "User not found."}
    end
  end

  @impl ResourceOwners
  def check_password(_resource_owner, _password) do
    {:error, "Password authentication is not supported."}
  end

  @impl ResourceOwners
  def authorized_scopes(%ResourceOwner{}), do: []

  @impl ResourceOwners
  def claims(_resource_owner, _scope), do: %{}
end
