defmodule Atlas.Support.Message do
  use Atlas.Schema

  import Ecto.Changeset

  alias Atlas.Inbox.InboxEmail
  alias Atlas.Support.Thread
  alias Atlas.Users.User

  @delivery_statuses ~w(queued sending delivered failed)

  schema "support_messages" do
    field :kind, :string
    field :message_id, :string
    field :in_reply_to, :string
    field :references, {:array, :string}, default: []
    field :sender_name, :string
    field :sender_email, :string
    field :to_emails, {:array, :string}, default: []
    field :cc_emails, {:array, :string}, default: []
    field :body, :string
    field :delivery_status, :string
    field :provider_message_id, :string
    field :delivery_error, :string
    field :delivered_at, :utc_datetime
    field :occurred_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :thread, Thread
    belongs_to :inbox_email, InboxEmail
    belongs_to :author, User

    timestamps()
  end

  def inbound_changeset(message, attrs) do
    message
    |> cast(attrs, [
      :inbox_email_id,
      :kind,
      :message_id,
      :in_reply_to,
      :references,
      :sender_name,
      :sender_email,
      :to_emails,
      :cc_emails,
      :body,
      :occurred_at,
      :metadata
    ])
    |> normalize_strings()
    |> validate_required([:thread_id, :inbox_email_id, :kind, :sender_email, :body, :occurred_at])
    |> validate_inclusion(:kind, ["inbound"])
    |> foreign_key_constraint(:thread_id)
    |> foreign_key_constraint(:inbox_email_id)
    |> unique_constraint(:inbox_email_id)
    |> unique_constraint(:message_id)
    |> check_constraint(:kind, name: :support_messages_kind_check)
  end

  def chat_changeset(message, attrs) do
    message
    |> cast(attrs, [
      :kind,
      :sender_name,
      :sender_email,
      :to_emails,
      :cc_emails,
      :body,
      :occurred_at,
      :metadata
    ])
    |> normalize_strings()
    |> validate_required([:thread_id, :kind, :sender_email, :body, :occurred_at])
    |> validate_inclusion(:kind, ["chat"])
    |> validate_length(:body, max: 10_000)
    |> foreign_key_constraint(:thread_id)
    |> check_constraint(:kind, name: :support_messages_kind_check)
  end

  def outbound_changeset(message, attrs) do
    message
    |> cast(attrs, [
      :author_id,
      :kind,
      :message_id,
      :in_reply_to,
      :references,
      :sender_name,
      :sender_email,
      :to_emails,
      :cc_emails,
      :body,
      :delivery_status,
      :occurred_at,
      :metadata
    ])
    |> normalize_strings()
    |> validate_required([
      :thread_id,
      :author_id,
      :kind,
      :message_id,
      :sender_email,
      :to_emails,
      :body,
      :delivery_status,
      :occurred_at
    ])
    |> validate_inclusion(:kind, ["outbound"])
    |> validate_inclusion(:delivery_status, ["queued"])
    |> validate_length(:body, max: 20_000)
    |> foreign_key_constraint(:thread_id)
    |> foreign_key_constraint(:author_id)
    |> unique_constraint(:message_id)
    |> check_constraint(:kind, name: :support_messages_kind_check)
    |> check_constraint(:delivery_status, name: :support_messages_delivery_status_check)
  end

  def note_changeset(message, attrs) do
    message
    |> cast(attrs, [:author_id, :kind, :body, :occurred_at])
    |> normalize_strings()
    |> validate_required([:thread_id, :author_id, :kind, :body, :occurred_at])
    |> validate_inclusion(:kind, ["note"])
    |> validate_length(:body, max: 20_000)
    |> foreign_key_constraint(:thread_id)
    |> foreign_key_constraint(:author_id)
    |> check_constraint(:kind, name: :support_messages_kind_check)
  end

  def delivery_changeset(message, attrs) do
    changeset =
      message
      |> cast(attrs, [:delivery_status, :provider_message_id, :delivery_error, :delivered_at])
      |> validate_required([:delivery_status])
      |> validate_inclusion(:delivery_status, @delivery_statuses)
      |> check_constraint(:delivery_status, name: :support_messages_delivery_status_check)

    if Map.has_key?(attrs, :delivery_error) or Map.has_key?(attrs, "delivery_error") do
      Ecto.Changeset.put_change(
        changeset,
        :delivery_error,
        Map.get(attrs, :delivery_error) || Map.get(attrs, "delivery_error")
      )
    else
      changeset
    end
  end

  defp normalize_strings(changeset) do
    Enum.reduce([:message_id, :in_reply_to, :sender_name, :sender_email, :body], changeset, fn field, changeset ->
      update_change(changeset, field, fn
        nil -> nil
        value -> value |> String.trim() |> normalize_string(field)
      end)
    end)
  end

  defp normalize_string("", _field), do: nil
  defp normalize_string(value, :sender_email), do: String.downcase(value)
  defp normalize_string(value, _field), do: value
end
