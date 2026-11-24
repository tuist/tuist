defmodule Symptoms.Store.VersionCount do
  @moduledoc """
  Request and error counts of one entity's version in one window, written by a source through `Symptoms.Store.put_version_counts/2`.
  """
  use Ecto.Schema

  schema "version_counts" do
    field :entity_id, :integer
    field :version, :string
    field :window_seconds, :integer
    field :window_start, :utc_datetime_usec
    field :errors, :integer
    field :total, :integer
    field :p95_ms, :float
    field :histogram, :map
  end
end
