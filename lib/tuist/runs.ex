defmodule Tuist.Runs do
  @moduledoc """
    Module for interacting with runs.
  """

  import Ecto.Query

  alias Tuist.Projects.Project
  alias Tuist.Repo
  alias Tuist.Runs.Build

  def get_build(id) do
    Repo.get(Build, id)
  end

  def create_build(attrs) do
    %Build{}
    |> Build.create_changeset(attrs)
    |> Repo.insert()
  end

  def list_build_runs(attrs, opts \\ []) do
    preload = Keyword.get(opts, :preload, [])

    Build
    |> preload(^preload)
    |> Flop.validate_and_run!(attrs, for: Build)
  end

  def project_build_schemes(%Project{} = project) do
    from(b in Build)
    |> where([b], b.project_id == ^project.id)
    |> where([b], not is_nil(b.scheme))
    |> where([b], b.inserted_at > ^DateTime.add(DateTime.utc_now(), -30, :day))
    |> distinct([b], b.scheme)
    |> Repo.all()
    |> Enum.map(& &1.scheme)
  end
end
