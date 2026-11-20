defmodule LuftServer.Threads.Participant do
  @moduledoc "Someone mentioned into a conversation; identity remains upstream."
  use Ecto.Schema

  @primary_key false
  schema "thread_participants" do
    field :thread_id, :binary_id, primary_key: true
    field :user_id, :integer, primary_key: true
    field :added_by_id, :integer
    timestamps(type: :utc_datetime)
  end
end
