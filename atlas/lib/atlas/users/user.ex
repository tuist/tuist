defmodule Atlas.Users.User do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Authorization.Role
  alias Atlas.Authorization.UserRole
  alias Atlas.Letters.Letter
  alias Atlas.Support.Message, as: SupportMessage
  alias Atlas.Support.Thread, as: SupportThread

  schema "users" do
    field :email, :string
    field :name, :string

    many_to_many :roles, Role, join_through: UserRole, unique: true

    has_many :owned_support_threads, SupportThread, foreign_key: :owner_id
    has_many :support_messages, SupportMessage, foreign_key: :author_id
    has_many :created_letters, Letter, foreign_key: :created_by_id
    has_many :confirmed_letters, Letter, foreign_key: :confirmed_by_id

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name])
    |> validate_required([:email])
    |> unique_constraint(:email)
  end

  def avatar_url(%__MODULE__{email: email}) do
    hash =
      email
      |> String.downcase()
      |> String.trim()
      |> then(&:crypto.hash(:md5, &1))
      |> Base.encode16(case: :lower)

    "https://gravatar.com/avatar/#{hash}?d=retro"
  end
end
