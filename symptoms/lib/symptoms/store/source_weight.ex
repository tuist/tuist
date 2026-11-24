defmodule Symptoms.Store.SourceWeight do
  @moduledoc """
  The daily raw weight of a source within a phenomenon, between 0.5 and 2 (`Symptoms.Evidence.Combine.source_weights/2` normalizes and bounds it again).
  """
  use Ecto.Schema

  schema "source_weights" do
    field :phenomenon, :string
    field :source, :string
    field :weight, :float
    field :samples, :float, default: 0.0
    field :updated_at, :utc_datetime_usec
  end
end
