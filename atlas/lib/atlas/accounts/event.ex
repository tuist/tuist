defmodule Atlas.Accounts.Event do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Accounts.Contact
  alias Atlas.Users.User

  schema "account_events" do
    field :external_id, :string
    field :source, :string
    field :kind, :string
    field :title, :string
    field :body, :string
    field :occurred_at, :utc_datetime
    field :url, :string
    field :metadata, :map, default: %{}

    belongs_to :account, Account
    belongs_to :contact, Contact
    belongs_to :author, User

    timestamps(updated_at: false)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :external_id,
      :source,
      :kind,
      :title,
      :body,
      :occurred_at,
      :url,
      :metadata,
      :account_id,
      :contact_id,
      :author_id
    ])
    |> validate_required([:external_id, :source, :kind, :title, :occurred_at, :account_id])
    |> unique_constraint(:external_id, name: :account_events_source_external_id_index)
  end
end
