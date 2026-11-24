defmodule Symptoms.Store.DegradedRun do
  @moduledoc """
  The start of an entity's current degraded run in one pipeline
  (`window_seconds`), for `Symptoms.Evidence.Roots` and the null history. The
  1- and 5-minute pipelines keep their own runs.
  """
  use Ecto.Schema

  @primary_key false
  schema "degraded_runs" do
    field :entity_id, :integer, primary_key: true
    field :window_seconds, :integer, primary_key: true
    field :since, :utc_datetime_usec
  end
end
