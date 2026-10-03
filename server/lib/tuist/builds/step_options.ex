defmodule Tuist.Builds.StepOptions do
  @moduledoc "Shared validation for recorded build step queries."
  alias Ecto.Changeset

  @types %{
    page: :integer,
    page_size: :integer,
    search: :string,
    project: :string,
    target: :string,
    category: :string,
    status: :string,
    start_ms: :float,
    end_ms: :float,
    sort_by: :string
  }

  def options(params, statuses) do
    changeset =
      {%{page: 1, page_size: 20, sort_by: "duration_ms"}, @types}
      |> Changeset.cast(params, Map.keys(@types))
      |> Changeset.validate_required([:page, :page_size, :sort_by])
      |> Changeset.validate_number(:page, greater_than: 0, less_than_or_equal_to: 100_000)
      |> Changeset.validate_number(:page_size, greater_than: 0, less_than_or_equal_to: 100)
      |> Changeset.validate_number(:start_ms, greater_than_or_equal_to: 0)
      |> Changeset.validate_number(:end_ms, greater_than_or_equal_to: 0)
      |> Changeset.validate_length(:search, max: 512)
      |> Changeset.validate_length(:project, max: 512)
      |> Changeset.validate_length(:target, max: 512)
      |> Changeset.validate_length(:category, max: 128)
      |> Changeset.validate_inclusion(:status, statuses)
      |> Changeset.validate_inclusion(:sort_by, ["duration_ms", "start_ms"])

    case Changeset.apply_action(changeset, :validate) do
      {:ok, opts} ->
        if opts[:start_ms] && opts[:end_ms] && opts.end_ms <= opts.start_ms,
          do: {:error, :invalid_range},
          else: {:ok, opts}

      {:error, _changeset} ->
        {:error, :invalid_filters}
    end
  end
end
