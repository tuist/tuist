defmodule Atlas.Orbit.Attachment do
  @moduledoc false
  use Atlas.Schema

  alias Atlas.Orbit.Message
  alias Atlas.Orbit.Thread
  alias Atlas.Users.User

  schema "orbit_attachments" do
    field :client_id, Ecto.UUID
    field :payload_digest, :binary, redact: true
    field :filename, :string
    field :content_type, :string
    field :byte_size, :integer
    field :storage_key, :string, redact: true
    field :status, :string, default: "uploading"
    field :expires_at, :utc_datetime_usec
    field :position, :integer

    belongs_to :thread, Thread
    belongs_to :message, Message
    belongs_to :user, User

    timestamps(type: :utc_datetime_usec)
  end
end
