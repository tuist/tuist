defmodule Tuist.Runs do
  @moduledoc """
    Module for interacting with runs.
  """
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

  def list_build_runs(attrs) do
    Flop.validate_and_run!(Build, attrs, for: Build)
  end
end
