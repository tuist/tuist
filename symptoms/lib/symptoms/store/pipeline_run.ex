defmodule Symptoms.Store.PipelineRun do
  @moduledoc """
  A window the pipeline finished, per window length.
  """
  use Ecto.Schema

  @primary_key false
  schema "pipeline_runs" do
    field :window_seconds, :integer, primary_key: true
    field :window_start, :utc_datetime_usec, primary_key: true
    field :records, :integer
    field :entities, :integer
    field :finished_at, :utc_datetime_usec
  end
end
