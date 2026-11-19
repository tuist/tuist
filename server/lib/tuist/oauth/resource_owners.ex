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
        {:ok, %ResourceOwner{sub: to_string(id), username: email, last_login_at: utc(last_sign_in_at)}}

      _ ->
        {:error, "User not found."}
    end
  end

  def get_by(attrs) do
    sub = Keyword.fetch!(attrs, :sub)

    case Repo.get_by(User, id: sub) do
      %User{id: id, email: email, last_sign_in_at: last_sign_in_at} ->
        {:ok, %ResourceOwner{sub: to_string(id), username: email, last_login_at: utc(last_sign_in_at)}}

      _ ->
        {:error, "User not found."}
    end
  end

  # Boruta reads `last_login_at` as an ID token's `auth_time`, a `DateTime`;
  # the users table stores sign-ins as naive UTC timestamps.
  defp utc(%NaiveDateTime{} = naive), do: DateTime.from_naive!(naive, "Etc/UTC")
  defp utc(other), do: other

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

  @doc """
  The standard claims (OpenID Connect Core 5.1) an ID token and the userinfo
  endpoint carry for the granted scope: `email` and `email_verified` for
  `email`, `preferred_username` (the personal account handle, which the
  Tuist API takes as the account name) and `name` for `profile`. `sub` is the
  user's ID, which never changes; handles and emails can.
  """
  @impl ResourceOwners
  def claims(%ResourceOwner{sub: sub}, scope) when is_binary(scope) do
    scopes = String.split(scope, " ", trim: true)

    case "openid" in scopes && Repo.get(User, sub) do
      %User{} = user ->
        user = Repo.preload(user, :account)

        %{}
        |> Map.merge(if "email" in scopes, do: email_claims(user), else: %{})
        |> Map.merge(if "profile" in scopes, do: profile_claims(user), else: %{})

      _ ->
        %{}
    end
  end

  def claims(_resource_owner, _scope), do: %{}

  defp email_claims(%User{} = user) do
    %{"email" => user.email, "email_verified" => not is_nil(user.confirmed_at)}
  end

  defp profile_claims(%User{account: account}) do
    %{"preferred_username" => account.name, "name" => account.name}
  end
end
