defmodule Atlas.Users.User do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Letters.Letter
  alias Atlas.Support.Message, as: SupportMessage
  alias Atlas.Support.Thread, as: SupportThread

  @roles [:executive, :employee]

  schema "users" do
    field :email, :string
    field :name, :string
    field :role, Ecto.Enum, values: @roles, default: :employee

    has_many :owned_support_threads, SupportThread, foreign_key: :owner_id
    has_many :support_messages, SupportMessage, foreign_key: :author_id
    has_many :created_letters, Letter, foreign_key: :created_by_id
    has_many :confirmed_letters, Letter, foreign_key: :confirmed_by_id

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :role])
    |> validate_required([:email, :role])
    |> unique_constraint(:email)
  end

  def role_changeset(user, attrs) do
    user
    |> cast(attrs, [:role])
    |> validate_required([:role])
  end

  def roles, do: @roles

  def role_label(:executive), do: "Executive"
  def role_label("executive"), do: "Executive"
  def role_label(:employee), do: "Employee"
  def role_label("employee"), do: "Employee"
  def role_label(_role), do: "Unknown"

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
