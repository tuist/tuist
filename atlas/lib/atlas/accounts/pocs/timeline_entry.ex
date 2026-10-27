defmodule Atlas.Accounts.POCs.TimelineEntry do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.POCs.POC
  alias Atlas.Users.User

  @kinds ~w(event decision milestone)

  schema "poc_timeline_entries" do
    field :occurred_on, :date
    field :title, :string
    field :body, :string
    field :kind, :string, default: "event"
    field :author_label, :string

    belongs_to :poc, POC
    belongs_to :created_by_user, User

    timestamps(type: :utc_datetime)
  end

  def kinds, do: @kinds

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:poc_id, :occurred_on, :title, :body, :kind, :author_label])
    |> validate_required([:poc_id, :occurred_on, :title, :kind])
    |> validate_length(:title, min: 2, max: 200)
    |> validate_length(:body, max: 8000)
    |> validate_length(:author_label, max: 120)
    |> validate_inclusion(:kind, @kinds)
    |> foreign_key_constraint(:poc_id)
  end
end
