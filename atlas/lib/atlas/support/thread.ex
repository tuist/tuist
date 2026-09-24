defmodule Atlas.Support.Thread do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Accounts.Account
  alias Atlas.Support.Message
  alias Atlas.Users.User

  @statuses ~w(open waiting resolved)

  @derive {
    Flop.Schema,
    filterable: [:status, :owner_id, :account_id],
    sortable: [:last_message_at, :last_inbound_at, :inserted_at],
    default_limit: 50,
    max_limit: 100
  }

  schema "support_threads" do
    field :customer_name, :string
    field :customer_email, :string
    field :subject, :string
    field :status, :string, default: "open"
    field :last_message_at, :utc_datetime
    field :last_inbound_at, :utc_datetime
    field :resolved_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :account, Account
    belongs_to :owner, User
    has_many :messages, Message

    timestamps()
  end

  def statuses, do: @statuses

  def inbound_changeset(thread, attrs) do
    thread
    |> cast(attrs, [
      :customer_name,
      :customer_email,
      :subject,
      :status,
      :last_message_at,
      :last_inbound_at,
      :resolved_at,
      :metadata
    ])
    |> normalize_strings()
    |> validate_required([:customer_email, :status, :last_message_at])
    |> validate_format(:customer_email, ~r/@/)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:owner_id)
    |> check_constraint(:status, name: :support_threads_status_check)
  end

  def status_changeset(thread, attrs) do
    thread
    |> cast(attrs, [:status, :resolved_at])
    |> validate_required([:status])
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :support_threads_status_check)
  end

  def owner_changeset(thread, attrs) do
    thread
    |> cast(attrs, [:owner_id])
    |> foreign_key_constraint(:owner_id)
  end

  def outbound_changeset(thread, attrs) do
    thread
    |> cast(attrs, [:status, :last_message_at, :resolved_at])
    |> validate_required([:status, :last_message_at])
    |> validate_inclusion(:status, @statuses)
    |> check_constraint(:status, name: :support_threads_status_check)
  end

  defp normalize_strings(changeset) do
    Enum.reduce([:customer_name, :customer_email, :subject], changeset, fn field, changeset ->
      update_change(changeset, field, fn
        nil -> nil
        value -> value |> String.trim() |> normalize_email_or_text(field)
      end)
    end)
  end

  defp normalize_email_or_text("", _field), do: nil
  defp normalize_email_or_text(value, :customer_email), do: String.downcase(value)
  defp normalize_email_or_text(value, _field), do: value
end
