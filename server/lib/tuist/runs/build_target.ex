defmodule Tuist.Runs.BuildTarget do
  @moduledoc false
  use Ecto.Schema

  @derive {
    Flop.Schema,
    filterable: [
      :build_run_id,
      :name,
      :project,
      :build_duration,
      :compilation_duration,
      :status
    ],
    sortable: [:name, :compilation_duration, :build_duration]
  }

  @primary_key false
  schema "build_targets" do
    field :name, :string
    field :project, :string
    field :build_duration, Ch, type: "UInt64"
    field :compilation_duration, Ch, type: "UInt64"
    field :status, Ch, type: "Enum8('success' = 0, 'failure' = 1)"

    belongs_to :build_run, Tuist.Runs.Build, type: Ecto.UUID

    # credo:disable-for-next-line Credo.Checks.TimestampsType
    timestamps(updated_at: false)
  end

  def changeset(build_run_id, target_attrs) do
    changeset = %{
      build_run_id: build_run_id,
      name: target_attrs.name,
      project: target_attrs.project,
      build_duration: target_attrs.build_duration,
      compilation_duration: target_attrs.compilation_duration,
      inserted_at: :second |> DateTime.utc_now() |> DateTime.to_naive()
    }

    changeset =
      if Map.has_key?(target_attrs, :status) do
        Map.put(changeset, :status, normalize_status_value(target_attrs.status))
      else
        changeset
      end

    changeset
  end

  defp normalize_status_value(:success), do: 0
  defp normalize_status_value(:failure), do: 1
  defp normalize_status_value(other), do: other
end
