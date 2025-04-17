defmodule Tuist.XcodeTest do
  use TuistTestSupport.Cases.DataCase

  alias Tuist.Repo
  alias Tuist.Xcode
  alias TuistTestSupport.Fixtures.CommandEventsFixtures

  describe "create_xcode_graph/1" do
    test "creates an Xcode graph with projects and targets" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      # When
      {:ok, xcode_graph} =
        Xcode.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "Graph",
            projects: [
              %{
                "name" => "ProjectA",
                "path" => "App",
                "targets" => [
                  %{
                    "name" => "TargetA",
                    "binary_cache_metadata" => %{
                      "hash" => "hash-a",
                      "hit" => "miss"
                    }
                  },
                  %{
                    "name" => "TargetB",
                    "binary_cache_metadata" => %{"hash" => "hash-b", "hit" => "local"}
                  },
                  %{
                    "name" => "TargetBTests",
                    "selective_testing_metadata" => %{"hash" => "hash-c", "hit" => "remote"}
                  }
                ]
              }
            ]
          }
        })

      # Then
      assert xcode_graph.name == "Graph"
      xcode_graph = Repo.preload(xcode_graph, xcode_projects: :xcode_targets)
      assert length(xcode_graph.xcode_projects) == 1
      assert xcode_graph.xcode_projects |> hd() |> Map.get(:name) == "ProjectA"

      xcode_targets =
        xcode_graph.xcode_projects |> hd() |> Map.get(:xcode_targets) |> Enum.sort_by(& &1.name)

      assert Enum.map(xcode_targets, & &1.name) == ["TargetA", "TargetB", "TargetBTests"]
      assert Enum.map(xcode_targets, & &1.binary_cache_hash) == ["hash-a", "hash-b", nil]
      assert Enum.map(xcode_targets, & &1.binary_cache_hit) == [:miss, :local, nil]
      assert Enum.map(xcode_targets, & &1.selective_testing_hash) == [nil, nil, "hash-c"]
      assert Enum.map(xcode_targets, & &1.selective_testing_hit) == [nil, nil, :remote]
    end
  end
end
