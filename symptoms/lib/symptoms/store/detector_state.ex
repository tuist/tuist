defmodule Symptoms.Store.DetectorState do
  @moduledoc """
  The CUSUM of one root key, its consecutive quiet windows and the open symptom it drives.
  """
  use Ecto.Schema

  @primary_key {:root_key, :string, autogenerate: false}
  schema "detector_states" do
    field :cusum, :float, default: 0.0
    field :window_seconds, :integer
    field :last_window_start, :utc_datetime_usec
    field :quiet_windows, :integer, default: 0
    field :symptom_id, Ecto.UUID
    field :updated_at, :utc_datetime_usec
  end
end
