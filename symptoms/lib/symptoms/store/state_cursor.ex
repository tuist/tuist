defmodule Symptoms.Store.StateCursor do
  @moduledoc """
  The state read-back's integer `cursor` (`name` is `state`).
  """
  use Ecto.Schema

  @primary_key {:name, :string, autogenerate: false}
  schema "state_cursors" do
    field :cursor, :integer
    field :updated_at, :utc_datetime_usec
  end
end
