defmodule Atlas.Conversations.Viewer do
  @moduledoc false
  use Ecto.Schema

  @primary_key false
  schema "conversation_viewers" do
    field :connection_id, Ecto.UUID, primary_key: true
    field :conversation_id, Ecto.UUID
    field :user_id, Ecto.UUID
    field :typing_until, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
  end
end
