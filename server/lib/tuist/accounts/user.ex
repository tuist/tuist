defmodule Tuist.Accounts.User do
  @moduledoc ~S"""
  A module that represents the user table.
  """
  use Ecto.Schema
  use Gettext, backend: TuistWeb.Gettext

  import Ecto.Changeset

  alias Tuist.Accounts.Account
  alias Tuist.Accounts.DeviceCode
  alias Tuist.Accounts.Oauth2Identity
  alias Tuist.Accounts.UserRole
  alias Tuist.Projects.Project

  @valid_email_regex ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/

  schema "users" do
    field :token, :string
    field :email, :string
    field :password, :string, virtual: true
    field :encrypted_password, :string, default: ""
    field :confirmed_at, :naive_datetime
    field :last_sign_in_at, :naive_datetime
    belongs_to :last_visited_project, Project, foreign_key: :last_visited_project_id

    has_one(:account, Account, foreign_key: :user_id, on_delete: :delete_all)
    has_many(:oauth2_identities, Oauth2Identity, foreign_key: :user_id, on_delete: :delete_all)
    has_many(:user_roles, UserRole, foreign_key: :user_id, on_delete: :delete_all)
    has_many(:device_codes, DeviceCode, on_delete: :delete_all)
    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(inserted_at: :created_at)
  end

  def create_user_changeset(user, attrs) do
    user
    |> cast(attrs, [:token, :email, :password, :encrypted_password, :confirmed_at, :created_at])
    |> update_change(:email, &String.downcase/1)
    |> validate_required([:token, :email])
    |> validate_password_strength()
    |> encrypt_password()
    |> unique_constraint(:token, name: "index_users_on_token")
    |> unique_constraint(:email, name: "index_users_on_email")
  end

  defp encrypt_password(changeset) do
    case changeset do
      %Ecto.Changeset{valid?: true, changes: _changes} ->
        password_to_hash =
          "#{get_change(changeset, :password)}#{Tuist.Environment.secret_key_password()}"

        changeset
        |> put_change(:encrypted_password, Bcrypt.hash_pwd_salt(password_to_hash))
        |> delete_change(:password)

      _ ->
        changeset
    end
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
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_password_strength()
    |> validate_confirmation(:password, message: dgettext("dashboard_account", "Passwords don't match"))
    |> encrypt_password()
  end

  def validate_password_strength(changeset) do
    changeset
    |> validate_length(:password, min: 6)
    |> validate_change(:password, fn _field, value ->
      case ZXCVBN.zxcvbn(value) do
        %{score: score} = value when score < 3 ->
          value |> password_strength_to_messages() |> Enum.map(&{:password, &1})

        _ ->
          []
      end
    end)
  end

  defp password_strength_to_messages(%{feedback: feedback}) do
    messages = []

    messages =
      if feedback.warning == "" do
        messages
      else
        messages ++ [feedback.warning]
      end

    messages ++ feedback.suggestions
  end

  @doc """
  Confirms the account by setting `confirmed_at`.
  """
  def confirm_changeset(user) do
    now = NaiveDateTime.truncate(NaiveDateTime.utc_now(), :second)
    change(user, confirmed_at: now)
  end

  def gravatar_url(%__MODULE__{email: email}) do
    email = email |> String.trim() |> String.downcase()
    hash = :md5 |> :crypto.hash(email) |> Base.encode16(case: :lower)
    gravatar_url = "https://www.gravatar.com/avatar/" <> hash

    gravatar_url <> "?d=404"
  end

  def email_valid?(email) do
    String.match?(email, @valid_email_regex)
  end
end
