defmodule TuistTestSupport.Fixtures.XcodeFixtures do
  @moduledoc false

  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.CommandEventsFixtures
  alias Tuist.Xcode.XcodeGraph
  alias Tuist.Xcode.XcodeProject
  alias Tuist.Xcode.XcodeTarget

  def xcode_graph_fixture(opts \\ []) do
    command_event_id =
      Keyword.get_lazy(opts, :command_event_id, fn ->
        CommandEventsFixtures.command_event_fixture().id
      end)

    name = Keyword.get(opts, :name, "#{TuistTestSupport.Utilities.unique_integer()}")

    %XcodeGraph{}
    |> XcodeGraph.create_changeset(%{
      name: name,
      command_event_id: command_event_id
    })
    |> Repo.insert!()
  end

  def xcode_project_fixture(opts \\ []) do
    xcode_graph_id =
      Keyword.get_lazy(opts, :xcode_graph_id, fn ->
        xcode_graph_fixture().id
      end)

    name = Keyword.get(opts, :name, "#{TuistTestSupport.Utilities.unique_integer()}")
    path = Keyword.get(opts, :path, "#{TuistTestSupport.Utilities.unique_integer()}")

    %XcodeProject{}
    |> XcodeProject.create_changeset(%{
      name: name,
      path: path,
      xcode_graph_id: xcode_graph_id
    })
    |> Repo.insert!()
  end

  def xcode_target_fixture(opts \\ []) do
    xcode_project_id =
      Keyword.get_lazy(opts, :xcode_project_id, fn ->
        xcode_project_fixture().id
      end)

    name = Keyword.get(opts, :name, "#{TuistTestSupport.Utilities.unique_integer()}")
    binary_cache_hash = Keyword.get(opts, :binary_cache_hash, nil)
    binary_cache_hit = Keyword.get(opts, :binary_cache_hit, :miss)
    selective_testing_hash = Keyword.get(opts, :selective_testing_hash, nil)
    selective_testing_hit = Keyword.get(opts, :selective_testing_hit, nil)

    %XcodeTarget{}
    |> XcodeTarget.create_changeset(%{
      name: name,
      xcode_project_id: xcode_project_id,
      binary_cache_hash: binary_cache_hash,
      binary_cache_hit: binary_cache_hit,
      selective_testing_hash: selective_testing_hash,
      selective_testing_hit: selective_testing_hit
    })
    |> Repo.insert!()
  end
end
