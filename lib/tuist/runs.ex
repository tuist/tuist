defmodule Tuist.Runs do
  @moduledoc """
    Module for interacting with runs.
  """
  alias Tuist.Runs.Build
  alias Tuist.Repo

  def get_build(id) do
    Build |> Repo.get(id)
  end

  def create_build(attrs) do
    %Build{}
    |> Build.create_changeset(attrs)
    |> Repo.insert()
  end

  def list_build_runs(attrs) do
    Build
    |> Flop.validate_and_run!(attrs, for: Build)
  end
end
