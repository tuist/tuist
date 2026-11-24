defmodule Tuist.Pulse.SymptomCursor do
  @moduledoc """
  The last symptom log `seq` the mirror processed, one row per source. See
  `Tuist.Pulse.Symptoms.sync/2`.
  """
  use Ecto.Schema

  @primary_key {:source, :string, autogenerate: false}
  schema "pulse_symptom_cursors" do
    field :seq, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end
