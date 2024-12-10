defmodule Tuist.Accounts.User do
  @moduledoc ~S"""
  A module that represents the user table.
  """
  use Ecto.Schema
  import Ecto.Changeset
  use Gettext, backend: TuistWeb.Gettext
  alias Tuist.Accounts.DeviceCode
  alias Tuist.Accounts.UserRole
  alias Tuist.Accounts.Oauth2Identity
  alias Tuist.Accounts.Account
  alias Tuist.Projects.Project

  @valid_email_regex ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/

  schema "users" do
    field :token, :string
    field :email, :string
    field :encrypted_password, :string, default: ""
    field :confirmed_at, :naive_datetime
    belongs_to :last_visited_project, Project, foreign_key: :last_visited_project_id

    has_one(:account, Account, foreign_key: :user_id, on_delete: :delete_all)
    has_many(:oauth2_identities, Oauth2Identity, foreign_key: :user_id, on_delete: :delete_all)
    has_many(:user_roles, UserRole, foreign_key: :user_id, on_delete: :delete_all)
    has_many(:device_codes, DeviceCode, on_delete: :delete_all)
    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(inserted_at: :created_at)
  end

  def create_user_changeset(user, attrs) do
    password_to_hash =
      "#{attrs |> Map.get(:password, "")}#{Tuist.Environment.secret_key_password()}"

    attrs = Map.put(attrs, :encrypted_password, Bcrypt.hash_pwd_salt(password_to_hash))

    user
    |> cast(attrs, [:token, :email, :encrypted_password, :confirmed_at, :created_at])
    |> update_change(:email, &String.downcase/1)
    |> validate_required([:token, :email])
    |> unique_constraint(:token, name: "index_users_on_token")
    |> unique_constraint(:email, name: "index_users_on_email")
  end

  @doc """
  Verifies the password.

  If there is no user or the user doesn't have a password, we call
  `Bcrypt.no_user_verify/0` to avoid timing attacks.
  """
  def valid_password?(%Tuist.Accounts.User{encrypted_password: encrypted_password}, password)
      when is_binary(encrypted_password) and byte_size(password) > 0 do
    Bcrypt.verify_pass(
      password <> Tuist.Environment.secret_key_password(),
      encrypted_password
    )
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end

  @doc """
  A user changeset for changing the password.
  """
  def password_changeset(user, attrs) do
    password_to_hash =
      "#{attrs |> Map.get("password", "")}#{Tuist.Environment.secret_key_password()}"

    attrs = Map.put(attrs, "encrypted_password", Bcrypt.hash_pwd_salt(password_to_hash))

    user
    |> cast(attrs, [:encrypted_password])
    |> validate_required([:encrypted_password])
    |> validate_confirmation(:password, message: gettext("Passwords don't match"))
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    change(user, confirmed_at: now)
  end

  def gravatar_url(%__MODULE__{email: email}) do
    email = email |> String.trim() |> String.downcase()
    hash = :crypto.hash(:md5, email) |> Base.encode16(case: :lower)
    "https://www.gravatar.com/avatar/" <> hash
  end

  def email_valid?(email) do
    String.match?(email, @valid_email_regex)
  end
end
