defmodule Tuist.Threads.Participant do
  @moduledoc """
  Someone looped into a thread they don't own, by being mentioned in it. They
  read the thread and prompt it; its runs still use the owner's subscription.
  """
  use Ecto.Schema

  @primary_key false
  schema "thread_participants" do
    field :thread_id, :binary_id, primary_key: true
    field :user_id, :integer, primary_key: true
    field :added_by_id, :integer
    timestamps(type: :utc_datetime)
  end
end
