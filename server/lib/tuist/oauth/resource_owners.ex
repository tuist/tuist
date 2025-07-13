defmodule Tuist.OAuth.ResourceOwners do
  @moduledoc false
  @behaviour Boruta.Oauth.ResourceOwners

  alias Boruta.Oauth.ResourceOwner
  alias Boruta.Oauth.ResourceOwners
  alias Tuist.Accounts.User
  alias Tuist.Repo

  @impl ResourceOwners
  def get_by(username: username) do
    case Repo.get_by(User, email: username) do
      %User{id: id, email: email, last_sign_in_at: last_sign_in_at} ->
        {:ok, %ResourceOwner{sub: to_string(id), username: email, last_login_at: last_sign_in_at}}

      _ ->
        {:error, "User not found."}
    end
  end

  def get_by(attrs) do
    sub = Keyword.fetch!(attrs, :sub)

    case Repo.get_by(User, id: sub) do
      %User{id: id, email: email, last_sign_in_at: last_sign_in_at} ->
        {:ok, %ResourceOwner{sub: to_string(id), username: email, last_login_at: last_sign_in_at}}

      _ ->
        {:error, "User not found."}
    end
  end

  @impl ResourceOwners
  def check_password(resource_owner, password) do
    user = Repo.get_by(User, id: resource_owner.sub)

    if User.valid_password?(user, password) do
      :ok
    else
      {:error, "Invalid email or password."}
    end
  end

  @impl ResourceOwners
  def authorized_scopes(%ResourceOwner{}), do: []

  @impl ResourceOwners
  def claims(_resource_owner, _scope), do: %{}
end
