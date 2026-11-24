defmodule Symptoms.Store.SourceStatus do
  @moduledoc """
  The last successful collect and the last error of a source, for input freshness.
  """
  use Ecto.Schema

  @primary_key {:source, :string, autogenerate: false}
  schema "source_statuses" do
    field :last_success_at, :utc_datetime_usec
    field :last_window_end, :utc_datetime_usec
    field :last_error, :string
    field :last_error_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end
end
