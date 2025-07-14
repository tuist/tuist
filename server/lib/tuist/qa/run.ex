defmodule Tuist.QA.Run do
  @moduledoc """
  A QA run represents a single QA test execution for an app build.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, UUIDv7, autogenerate: true}
  schema "qa_runs" do
    field :state, :string, default: "running"
    field :summary, :string

    belongs_to :app_build, Tuist.AppBuilds.AppBuild, type: UUIDv7

    timestamps(type: :utc_datetime)
  end

  def create_changeset(qa_run, attrs) do
    qa_run
    |> cast(attrs, [:app_build_id])
    |> validate_required([:app_build_id])
    |> validate_inclusion(:state, ["running", "finished"])
  end

  def update_changeset(qa_run, attrs) do
    qa_run
    |> cast(attrs, [:state, :summary])
    |> validate_inclusion(:state, ["running", "finished"])
  end
end
