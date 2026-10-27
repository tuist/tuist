defmodule Atlas.Tasks.Task do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Users.User

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "open"
    field :due_on, :date
    field :remind_at, :utc_datetime
    field :reminded_at, :utc_datetime
    field :reminder_version, :integer, default: 1
    field :due_notified_at, :utc_datetime
    field :due_version, :integer, default: 1
    field :completed_at, :utc_datetime

    belongs_to :assignee, User
    belongs_to :created_by, User
    belongs_to :account, Account

    timestamps(type: :utc_datetime)
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [:title, :description, :assignee_id, :account_id, :due_on, :remind_at])
    |> update_change(:title, &String.trim/1)
    |> update_change(:description, fn
      nil ->
        nil

      value ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end
    end)
    |> validate_required([:title, :assignee_id])
    |> validate_length(:title, max: 255)
    |> validate_length(:description, max: 2000)
    |> foreign_key_constraint(:assignee_id)
    |> foreign_key_constraint(:account_id)
  end
end
