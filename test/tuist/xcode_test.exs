defmodule Tuist.XcodeTest do
  use TuistTestSupport.Cases.DataCase

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Repo
  alias Tuist.Xcode.Clickhouse
  alias Tuist.Xcode.Clickhouse.XcodeGraph, as: CHXcodeGraph
  alias Tuist.Xcode.Clickhouse.XcodeProject, as: CHXcodeProject
  alias Tuist.Xcode.Clickhouse.XcodeTarget, as: CHXcodeTarget
  alias Tuist.Xcode.Postgres
  alias Tuist.Xcode.Postgres.XcodeGraph, as: PGXcodeGraph
  alias Tuist.Xcode.Postgres.XcodeProject, as: PGXcodeProject
  alias Tuist.Xcode.Postgres.XcodeTarget, as: PGXcodeTarget
  alias TuistTestSupport.Fixtures.CommandEventsFixtures

  describe "Tuist.Xcode.Clickhouse" do
    test "creates an Xcode graph with projects and targets" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      xcode_data = %{
        command_event: command_event,
        xcode_graph: %{
          name: "TestGraph",
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
      }

      # When
      {:ok, xcode_graph} = Clickhouse.create_xcode_graph(xcode_data)

      # Then
      assert xcode_graph.name == "TestGraph"
      assert xcode_graph.command_event_id == command_event.id

      # Verify data was written to ClickHouse
      [graph_ch] = ClickHouseRepo.all(from g in CHXcodeGraph, where: g.command_event_id == ^command_event.id)
      assert graph_ch.name == "TestGraph"
      assert graph_ch.command_event_id == command_event.id

      [project_ch] = ClickHouseRepo.all(from p in CHXcodeProject, where: p.xcode_graph_id == ^graph_ch.id)
      assert project_ch.name == "ProjectA"
      assert project_ch.path == "App"
      assert project_ch.xcode_graph_id == graph_ch.id

      targets_ch =
        from(t in CHXcodeTarget, where: t.xcode_project_id == ^project_ch.id)
        |> ClickHouseRepo.all()
        |> Enum.map(&CHXcodeTarget.normalize_enums/1)
        |> Enum.sort_by(& &1.name)

      assert Enum.map(targets_ch, & &1.name) == ["TargetA", "TargetB", "TargetBTests"]
      assert Enum.map(targets_ch, & &1.binary_cache_hash) == ["hash-a", "hash-b", nil]
      assert Enum.map(targets_ch, & &1.binary_cache_hit) == [:miss, :local, :miss]
      assert Enum.map(targets_ch, & &1.selective_testing_hash) == [nil, nil, "hash-c"]
      assert Enum.map(targets_ch, & &1.selective_testing_hit) == [:miss, :miss, :remote]
    end
  end

  describe "Tuist.Xcode.Postgres" do
    test "creates an Xcode graph with projects and targets" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      xcode_data = %{
        command_event: command_event,
        xcode_graph: %{
          name: "TestGraph",
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
      }

      # When
      {:ok, xcode_graph} = Postgres.create_xcode_graph(xcode_data)

      # Then
      assert xcode_graph.name == "TestGraph"
      assert xcode_graph.command_event_id == command_event.id

      # Verify data was written to Postgres
      [graph_pg] = Repo.all(from g in PGXcodeGraph, where: g.command_event_id == ^command_event.id)
      assert graph_pg.name == "TestGraph"
      assert graph_pg.command_event_id == command_event.id

      [project_pg] = Repo.all(from p in PGXcodeProject, where: p.xcode_graph_id == ^graph_pg.id)
      assert project_pg.name == "ProjectA"
      assert project_pg.path == "App"
      assert project_pg.xcode_graph_id == graph_pg.id

      targets_pg =
        from(t in PGXcodeTarget, where: t.xcode_project_id == ^project_pg.id)
        |> Repo.all()
        |> Enum.sort_by(& &1.name)

      assert Enum.map(targets_pg, & &1.name) == ["TargetA", "TargetB", "TargetBTests"]
      assert Enum.map(targets_pg, & &1.binary_cache_hash) == ["hash-a", "hash-b", nil]
      assert Enum.map(targets_pg, & &1.binary_cache_hit) == [:miss, :local, nil]
      assert Enum.map(targets_pg, & &1.selective_testing_hash) == [nil, nil, "hash-c"]
      assert Enum.map(targets_pg, & &1.selective_testing_hit) == [nil, nil, :remote]
    end
  end

  describe "Tuist.Xcode.Clickhouse analytics" do
    test "has_selective_testing_data?/1 returns true when selective testing data exists" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        Clickhouse.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "TestGraph",
            projects: [
              %{
                "name" => "TestProject",
                "path" => "TestApp",
                "targets" => [
                  %{
                    "name" => "TestTarget1",
                    "selective_testing_metadata" => %{"hash" => "hash-1", "hit" => "local"}
                  }
                ]
              }
            ]
          }
        })

      # When
      result = Clickhouse.has_selective_testing_data?(command_event)

      # Then
      assert result == true
    end

    test "has_selective_testing_data?/1 returns false when no selective testing data exists" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        Clickhouse.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "TestGraph",
            projects: [
              %{
                "name" => "TestProject",
                "path" => "TestApp",
                "targets" => [
                  %{
                    "name" => "TestTarget1",
                    "binary_cache_metadata" => %{"hash" => "hash-1", "hit" => "local"}
                  }
                ]
              }
            ]
          }
        })

      # When
      result = Clickhouse.has_selective_testing_data?(command_event)

      # Then
      assert result == false
    end

    test "has_binary_cache_data?/1 returns true when binary cache data exists" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        Clickhouse.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "TestGraph",
            projects: [
              %{
                "name" => "TestProject",
                "path" => "TestApp",
                "targets" => [
                  %{
                    "name" => "TestTarget1",
                    "binary_cache_metadata" => %{"hash" => "hash-1", "hit" => "local"}
                  }
                ]
              }
            ]
          }
        })

      # When
      result = Clickhouse.has_binary_cache_data?(command_event)

      # Then
      assert result == true
    end

    test "has_binary_cache_data?/1 returns false when no binary cache data exists" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        Clickhouse.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "TestGraph",
            projects: [
              %{
                "name" => "TestProject",
                "path" => "TestApp",
                "targets" => [
                  %{
                    "name" => "TestTarget1",
                    "selective_testing_metadata" => %{"hash" => "hash-1", "hit" => "local"}
                  }
                ]
              }
            ]
          }
        })

      # When
      result = Clickhouse.has_binary_cache_data?(command_event)

      # Then
      assert result == false
    end

    test "selective_testing_analytics/1 returns analytics from ClickHouse data" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        Clickhouse.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "TestGraph",
            projects: [
              %{
                "name" => "TestProject",
                "path" => "TestApp",
                "targets" => [
                  %{
                    "name" => "TestTarget1",
                    "selective_testing_metadata" => %{"hash" => "hash-1", "hit" => "local"}
                  },
                  %{
                    "name" => "TestTarget2",
                    "selective_testing_metadata" => %{"hash" => "hash-2", "hit" => "remote"}
                  },
                  %{
                    "name" => "TestTarget3",
                    "selective_testing_metadata" => %{"hash" => "hash-3", "hit" => "miss"}
                  }
                ]
              }
            ]
          }
        })

      # When
      analytics = Clickhouse.selective_testing_analytics(command_event)

      # Then
      assert analytics.selective_testing_local_hits_count == 1
      assert analytics.selective_testing_remote_hits_count == 1
      assert analytics.selective_testing_misses_count == 1
      assert length(analytics.test_modules) == 3

      target_names = analytics.test_modules |> Enum.map(& &1.name) |> Enum.sort()
      assert target_names == ["TestTarget1", "TestTarget2", "TestTarget3"]
    end

    test "binary_cache_analytics/1 returns analytics from ClickHouse data" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        Clickhouse.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "CacheGraph",
            projects: [
              %{
                "name" => "CacheProject",
                "path" => "CacheApp",
                "targets" => [
                  %{
                    "name" => "CacheTarget1",
                    "binary_cache_metadata" => %{"hash" => "cache-hash-1", "hit" => "local"}
                  },
                  %{
                    "name" => "CacheTarget2",
                    "binary_cache_metadata" => %{"hash" => "cache-hash-2", "hit" => "remote"}
                  },
                  %{
                    "name" => "CacheTarget3",
                    "binary_cache_metadata" => %{"hash" => "cache-hash-3", "hit" => "miss"}
                  },
                  %{
                    "name" => "CacheTarget4",
                    "binary_cache_metadata" => %{"hash" => "cache-hash-4", "hit" => "local"}
                  }
                ]
              }
            ]
          }
        })

      # When
      analytics = Clickhouse.binary_cache_analytics(command_event)

      # Then
      assert analytics.binary_cache_local_hits_count == 2
      assert analytics.binary_cache_remote_hits_count == 1
      assert analytics.binary_cache_misses_count == 1
      assert length(analytics.cacheable_targets) == 4

      target_names = analytics.cacheable_targets |> Enum.map(& &1.name) |> Enum.sort()
      assert target_names == ["CacheTarget1", "CacheTarget2", "CacheTarget3", "CacheTarget4"]
    end
  end

  describe "Tuist.Xcode.Postgres analytics" do
    test "has_selective_testing_data?/1 returns true when selective testing data exists" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        Postgres.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "TestGraph",
            projects: [
              %{
                "name" => "TestProject",
                "path" => "TestApp",
                "targets" => [
                  %{
                    "name" => "TestTarget1",
                    "selective_testing_metadata" => %{"hash" => "hash-1", "hit" => "local"}
                  }
                ]
              }
            ]
          }
        })

      # When
      result = Postgres.has_selective_testing_data?(command_event)

      # Then
      assert result == true
    end

    test "has_selective_testing_data?/1 returns false when no selective testing data exists" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        Postgres.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "TestGraph",
            projects: [
              %{
                "name" => "TestProject",
                "path" => "TestApp",
                "targets" => [
                  %{
                    "name" => "TestTarget1",
                    "binary_cache_metadata" => %{"hash" => "hash-1", "hit" => "local"}
                  }
                ]
              }
            ]
          }
        })

      # When
      result = Postgres.has_selective_testing_data?(command_event)

      # Then
      assert result == false
    end

    test "has_binary_cache_data?/1 returns true when binary cache data exists" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        Postgres.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "TestGraph",
            projects: [
              %{
                "name" => "TestProject",
                "path" => "TestApp",
                "targets" => [
                  %{
                    "name" => "TestTarget1",
                    "binary_cache_metadata" => %{"hash" => "hash-1", "hit" => "local"}
                  }
                ]
              }
            ]
          }
        })

      # When
      result = Postgres.has_binary_cache_data?(command_event)

      # Then
      assert result == true
    end

    test "has_binary_cache_data?/1 returns false when no binary cache data exists" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        Postgres.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "TestGraph",
            projects: [
              %{
                "name" => "TestProject",
                "path" => "TestApp",
                "targets" => [
                  %{
                    "name" => "TestTarget1",
                    "selective_testing_metadata" => %{"hash" => "hash-1", "hit" => "local"}
                  }
                ]
              }
            ]
          }
        })

      # When
      result = Postgres.has_binary_cache_data?(command_event)

      # Then
      assert result == false
    end

    test "selective_testing_analytics/1 returns analytics from Postgres data" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        Postgres.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "TestGraph",
            projects: [
              %{
                "name" => "TestProject",
                "path" => "TestApp",
                "targets" => [
                  %{
                    "name" => "TestTarget1",
                    "selective_testing_metadata" => %{"hash" => "hash-1", "hit" => "local"}
                  },
                  %{
                    "name" => "TestTarget2",
                    "selective_testing_metadata" => %{"hash" => "hash-2", "hit" => "remote"}
                  },
                  %{
                    "name" => "TestTarget3",
                    "selective_testing_metadata" => %{"hash" => "hash-3", "hit" => "miss"}
                  }
                ]
              }
            ]
          }
        })

      # When
      analytics = Postgres.selective_testing_analytics(command_event)

      # Then
      assert analytics.selective_testing_local_hits_count == 1
      assert analytics.selective_testing_remote_hits_count == 1
      assert analytics.selective_testing_misses_count == 1
      assert length(analytics.test_modules) == 3

      target_names = analytics.test_modules |> Enum.map(& &1.name) |> Enum.sort()
      assert target_names == ["TestTarget1", "TestTarget2", "TestTarget3"]
    end

    test "binary_cache_analytics/1 returns analytics from Postgres data" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        Postgres.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "CacheGraph",
            projects: [
              %{
                "name" => "CacheProject",
                "path" => "CacheApp",
                "targets" => [
                  %{
                    "name" => "CacheTarget1",
                    "binary_cache_metadata" => %{"hash" => "cache-hash-1", "hit" => "local"}
                  },
                  %{
                    "name" => "CacheTarget2",
                    "binary_cache_metadata" => %{"hash" => "cache-hash-2", "hit" => "remote"}
                  },
                  %{
                    "name" => "CacheTarget3",
                    "binary_cache_metadata" => %{"hash" => "cache-hash-3", "hit" => "miss"}
                  },
                  %{
                    "name" => "CacheTarget4",
                    "binary_cache_metadata" => %{"hash" => "cache-hash-4", "hit" => "local"}
                  }
                ]
              }
            ]
          }
        })

      # When
      analytics = Postgres.binary_cache_analytics(command_event)

      # Then
      assert analytics.binary_cache_local_hits_count == 2
      assert analytics.binary_cache_remote_hits_count == 1
      assert analytics.binary_cache_misses_count == 1
      assert length(analytics.cacheable_targets) == 4

      target_names = analytics.cacheable_targets |> Enum.map(& &1.name) |> Enum.sort()
      assert target_names == ["CacheTarget1", "CacheTarget2", "CacheTarget3", "CacheTarget4"]
    end
  end
end
