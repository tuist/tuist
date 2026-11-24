defmodule Symptoms.Store.SourceEntity do
  @moduledoc """
  The last time a source reported an entity (evidence or discovery); the
  entities a source is expected to report.
  """
  use Ecto.Schema

  @primary_key false
  schema "source_entities" do
    field :source, :string, primary_key: true
    field :entity_id, :integer, primary_key: true
    field :last_seen_at, :utc_datetime_usec
  end
end
