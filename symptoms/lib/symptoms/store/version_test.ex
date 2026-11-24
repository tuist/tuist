defmodule Symptoms.Store.VersionTest do
  @moduledoc """
  The mixture e-process state of one deploy's version-against-version test on one entity (`Symptoms.Deploys`).
  """
  use Ecto.Schema

  schema "version_tests" do
    field :change_id, :integer
    field :entity_id, :integer
    field :test, :string, default: "error_share"
    field :log_weights, {:array, :float}
    field :e, :float, default: 1.0
    field :status, :string, default: "running"
    field :last_window_start, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end
end
