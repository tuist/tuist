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
      {analytics, _meta} = Clickhouse.selective_testing_analytics(command_event)

      # Then
      assert length(analytics.test_modules) == 3

      target_names = analytics.test_modules |> Enum.map(& &1.name) |> Enum.sort()
      assert target_names == ["TestTarget1", "TestTarget2", "TestTarget3"]

      # Verify hit types
      hits_by_name = Map.new(analytics.test_modules, &{&1.name, &1.selective_testing_hit})
      assert hits_by_name["TestTarget1"] == :local
      assert hits_by_name["TestTarget2"] == :remote
      assert hits_by_name["TestTarget3"] == :miss
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
      {analytics, _meta} = Clickhouse.binary_cache_analytics(command_event)

      # Then
      assert length(analytics.cacheable_targets) == 4

      target_names = analytics.cacheable_targets |> Enum.map(& &1.name) |> Enum.sort()
      assert target_names == ["CacheTarget1", "CacheTarget2", "CacheTarget3", "CacheTarget4"]

      # Verify hit types
      hits_by_name = Map.new(analytics.cacheable_targets, &{&1.name, &1.binary_cache_hit})
      assert hits_by_name["CacheTarget1"] == :local
      assert hits_by_name["CacheTarget2"] == :remote
      assert hits_by_name["CacheTarget3"] == :miss
      assert hits_by_name["CacheTarget4"] == :local
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
      {analytics, _meta} = Postgres.selective_testing_analytics(command_event)

      # Then
      assert length(analytics.test_modules) == 3

      target_names = analytics.test_modules |> Enum.map(& &1.name) |> Enum.sort()
      assert target_names == ["TestTarget1", "TestTarget2", "TestTarget3"]

      # Verify hit types
      hits_by_name = Map.new(analytics.test_modules, &{&1.name, &1.selective_testing_hit})
      assert hits_by_name["TestTarget1"] == :local
      assert hits_by_name["TestTarget2"] == :remote
      assert hits_by_name["TestTarget3"] == :miss
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
      {analytics, _meta} = Postgres.binary_cache_analytics(command_event)

      # Then
      assert length(analytics.cacheable_targets) == 4

      target_names = analytics.cacheable_targets |> Enum.map(& &1.name) |> Enum.sort()
      assert target_names == ["CacheTarget1", "CacheTarget2", "CacheTarget3", "CacheTarget4"]

      # Verify hit types
      hits_by_name = Map.new(analytics.cacheable_targets, &{&1.name, &1.binary_cache_hit})
      assert hits_by_name["CacheTarget1"] == :local
      assert hits_by_name["CacheTarget2"] == :remote
      assert hits_by_name["CacheTarget3"] == :miss
      assert hits_by_name["CacheTarget4"] == :local
    end
  end

  describe "Tuist.Xcode paginated analytics" do
    test "selective_testing_analytics/2 with pagination for Postgres" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      # Create 25 targets to test pagination
      targets =
        for i <- 1..25 do
          %{
            "name" => "TestTarget#{i}",
            "selective_testing_metadata" => %{
              "hash" => "hash-#{i}",
              "hit" => Enum.random(["local", "remote", "miss"])
            }
          }
        end

      {:ok, _xcode_graph} =
        Postgres.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "TestGraph",
            projects: [
              %{
                "name" => "TestProject",
                "path" => "TestApp",
                "targets" => targets
              }
            ]
          }
        })

      # When - First page
      {result, meta} = Postgres.selective_testing_analytics(command_event, %{page_size: 10})

      # Then
      assert length(result.test_modules) == 10
      assert meta.total_count == 25
      assert meta.total_pages == 3
      assert meta.current_page == 1
      assert meta.has_next_page? == true
      assert meta.has_previous_page? == false

      # When - Second page
      {result2, meta2} = Postgres.selective_testing_analytics(command_event, %{page: 2, page_size: 10})

      # Then
      assert length(result2.test_modules) == 10
      assert meta2.current_page == 2
      assert meta2.has_next_page? == true
      assert meta2.has_previous_page? == true

      # When - Last page
      {result3, meta3} = Postgres.selective_testing_analytics(command_event, %{page: 3, page_size: 10})

      # Then
      assert length(result3.test_modules) == 5
      assert meta3.current_page == 3
      assert meta3.has_next_page? == false
      assert meta3.has_previous_page? == true
    end

    test "selective_testing_analytics/2 with filtering for Postgres" do
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
                    "name" => "AppTarget",
                    "selective_testing_metadata" => %{"hash" => "hash-1", "hit" => "local"}
                  },
                  %{
                    "name" => "AppTests",
                    "selective_testing_metadata" => %{"hash" => "hash-2", "hit" => "remote"}
                  },
                  %{
                    "name" => "FrameworkTarget",
                    "selective_testing_metadata" => %{"hash" => "hash-3", "hit" => "miss"}
                  }
                ]
              }
            ]
          }
        })

      # When - Filter by name
      {result, meta} =
        Postgres.selective_testing_analytics(command_event, %{
          filters: [%{field: :name, op: :ilike_and, value: "App"}]
        })

      # Then
      assert length(result.test_modules) == 2
      assert meta.total_count == 2
      target_names = result.test_modules |> Enum.map(& &1.name) |> Enum.sort()
      assert target_names == ["AppTarget", "AppTests"]
    end

    test "selective_testing_analytics/2 with sorting for Postgres" do
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
                    "name" => "CTarget",
                    "selective_testing_metadata" => %{"hash" => "hash-1", "hit" => "local"}
                  },
                  %{
                    "name" => "ATarget",
                    "selective_testing_metadata" => %{"hash" => "hash-2", "hit" => "remote"}
                  },
                  %{
                    "name" => "BTarget",
                    "selective_testing_metadata" => %{"hash" => "hash-3", "hit" => "miss"}
                  }
                ]
              }
            ]
          }
        })

      # When - Sort by name ascending
      {result, _meta} =
        Postgres.selective_testing_analytics(command_event, %{
          order_by: [:name],
          order_directions: [:asc]
        })

      # Then
      target_names = Enum.map(result.test_modules, & &1.name)
      assert target_names == ["ATarget", "BTarget", "CTarget"]

      # When - Sort by hit type
      {result2, _meta2} =
        Postgres.selective_testing_analytics(command_event, %{
          order_by: [:selective_testing_hit],
          order_directions: [:asc]
        })

      # Then
      hit_types = Enum.map(result2.test_modules, & &1.selective_testing_hit)
      assert hit_types == [:miss, :local, :remote]
    end

    test "binary_cache_analytics/2 with pagination for Postgres" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      # Create 15 targets to test pagination
      targets =
        for i <- 1..15 do
          %{
            "name" => "CacheTarget#{i}",
            "binary_cache_metadata" => %{
              "hash" => "cache-hash-#{i}",
              "hit" => Enum.random(["local", "remote", "miss"])
            }
          }
        end

      {:ok, _xcode_graph} =
        Postgres.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "CacheGraph",
            projects: [
              %{
                "name" => "CacheProject",
                "path" => "CacheApp",
                "targets" => targets
              }
            ]
          }
        })

      # When - First page
      {result, meta} = Postgres.binary_cache_analytics(command_event, %{page_size: 10})

      # Then
      assert length(result.cacheable_targets) == 10
      assert meta.total_count == 15
      assert meta.total_pages == 2
      assert meta.current_page == 1

      # When - Second page
      {result2, meta2} = Postgres.binary_cache_analytics(command_event, %{page: 2, page_size: 10})

      # Then
      assert length(result2.cacheable_targets) == 5
      assert meta2.current_page == 2
    end

    test "selective_testing_analytics/2 with pagination for ClickHouse" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      # Create 25 targets to test pagination
      targets =
        for i <- 1..25 do
          %{
            "name" => "TestTarget#{i}",
            "selective_testing_metadata" => %{
              "hash" => "hash-#{i}",
              "hit" => Enum.random(["local", "remote", "miss"])
            }
          }
        end

      {:ok, _xcode_graph} =
        Clickhouse.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "TestGraph",
            projects: [
              %{
                "name" => "TestProject",
                "path" => "TestApp",
                "targets" => targets
              }
            ]
          }
        })

      # When - First page
      {result, meta} = Clickhouse.selective_testing_analytics(command_event, %{page_size: 10})

      # Then
      assert length(result.test_modules) == 10
      assert meta.total_count == 25
      assert meta.total_pages == 3
      assert meta.current_page == 1
    end

    test "binary_cache_analytics/2 with pagination for ClickHouse" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      # Create 15 targets to test pagination
      targets =
        for i <- 1..15 do
          %{
            "name" => "CacheTarget#{i}",
            "binary_cache_metadata" => %{
              "hash" => "cache-hash-#{i}",
              "hit" => Enum.random(["local", "remote", "miss"])
            }
          }
        end

      {:ok, _xcode_graph} =
        Clickhouse.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "CacheGraph",
            projects: [
              %{
                "name" => "CacheProject",
                "path" => "CacheApp",
                "targets" => targets
              }
            ]
          }
        })

      # When - First page
      {result, meta} = Clickhouse.binary_cache_analytics(command_event, %{page_size: 10})

      # Then
      assert length(result.cacheable_targets) == 10
      assert meta.total_count == 15
      assert meta.total_pages == 2
    end

    test "selective_testing_counts/1 returns aggregate counts for Postgres" do
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
                    "selective_testing_metadata" => %{"hash" => "hash-2", "hit" => "local"}
                  },
                  %{
                    "name" => "TestTarget3",
                    "selective_testing_metadata" => %{"hash" => "hash-3", "hit" => "remote"}
                  },
                  %{
                    "name" => "TestTarget4",
                    "selective_testing_metadata" => %{"hash" => "hash-4", "hit" => "miss"}
                  },
                  %{
                    "name" => "TestTarget5",
                    "binary_cache_metadata" => %{"hash" => "cache-5", "hit" => "miss"}
                  }
                ]
              }
            ]
          }
        })

      # When
      counts = Postgres.selective_testing_counts(command_event)

      # Then
      assert counts.selective_testing_local_hits_count == 2
      assert counts.selective_testing_remote_hits_count == 1
      assert counts.selective_testing_misses_count == 1
      assert counts.total_count == 4
    end

    test "binary_cache_counts/1 returns aggregate counts for Postgres" do
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
                    "binary_cache_metadata" => %{"hash" => "cache-hash-2", "hit" => "local"}
                  },
                  %{
                    "name" => "CacheTarget3",
                    "binary_cache_metadata" => %{"hash" => "cache-hash-3", "hit" => "local"}
                  },
                  %{
                    "name" => "CacheTarget4",
                    "binary_cache_metadata" => %{"hash" => "cache-hash-4", "hit" => "remote"}
                  },
                  %{
                    "name" => "CacheTarget5",
                    "binary_cache_metadata" => %{"hash" => "cache-hash-5", "hit" => "miss"}
                  },
                  %{
                    "name" => "TestTarget6",
                    "selective_testing_metadata" => %{"hash" => "test-6", "hit" => "miss"}
                  }
                ]
              }
            ]
          }
        })

      # When
      counts = Postgres.binary_cache_counts(command_event)

      # Then
      assert counts.binary_cache_local_hits_count == 3
      assert counts.binary_cache_remote_hits_count == 1
      assert counts.binary_cache_misses_count == 1
      assert counts.total_count == 5
    end

    test "selective_testing_counts/1 returns aggregate counts for ClickHouse" do
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
      counts = Clickhouse.selective_testing_counts(command_event)

      # Then
      assert counts.selective_testing_local_hits_count == 1
      assert counts.selective_testing_remote_hits_count == 1
      assert counts.selective_testing_misses_count == 1
      assert counts.total_count == 3
    end

    test "binary_cache_counts/1 returns aggregate counts for ClickHouse" do
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
                    "binary_cache_metadata" => %{"hash" => "cache-hash-4", "hit" => "miss"}
                  }
                ]
              }
            ]
          }
        })

      # When
      counts = Clickhouse.binary_cache_counts(command_event)

      # Then
      assert counts.binary_cache_local_hits_count == 1
      assert counts.binary_cache_remote_hits_count == 1
      assert counts.binary_cache_misses_count == 2
      assert counts.total_count == 4
    end
  end

  describe "Edge cases and empty results" do
    test "selective_testing_counts/1 returns zeros for empty data - Postgres" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        Postgres.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "EmptyGraph",
            projects: [
              %{
                "name" => "EmptyProject",
                "path" => "EmptyApp",
                "targets" => []
              }
            ]
          }
        })

      # When
      counts = Postgres.selective_testing_counts(command_event)

      # Then
      assert counts.selective_testing_local_hits_count == 0
      assert counts.selective_testing_remote_hits_count == 0
      assert counts.selective_testing_misses_count == 0
      assert counts.total_count == 0
    end

    test "selective_testing_counts/1 returns zeros for empty data - ClickHouse" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        Clickhouse.create_xcode_graph(%{
          command_event: command_event,
          xcode_graph: %{
            name: "EmptyGraph",
            projects: [
              %{
                "name" => "EmptyProject",
                "path" => "EmptyApp",
                "targets" => []
              }
            ]
          }
        })

      # When
      counts = Clickhouse.selective_testing_counts(command_event)

      # Then
      assert counts.selective_testing_local_hits_count == 0
      assert counts.selective_testing_remote_hits_count == 0
      assert counts.selective_testing_misses_count == 0
      assert counts.total_count == 0
    end

    test "analytics with empty flop params returns all data - Postgres" do
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
                  }
                ]
              }
            ]
          }
        })

      # When - Call without flop params
      {result, meta} = Postgres.selective_testing_analytics(command_event)

      # Then
      assert length(result.test_modules) == 2
      assert meta.total_count == 2
    end

    test "analytics with empty flop params returns all data - ClickHouse" do
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
                  }
                ]
              }
            ]
          }
        })

      # When - Call without flop params
      {result, meta} = Clickhouse.selective_testing_analytics(command_event)

      # Then
      assert length(result.test_modules) == 2
      assert meta.total_count == 2
    end

    test "counts handle targets with only one hit type - Postgres" do
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
                    "selective_testing_metadata" => %{"hash" => "hash-2", "hit" => "local"}
                  },
                  %{
                    "name" => "TestTarget3",
                    "selective_testing_metadata" => %{"hash" => "hash-3", "hit" => "local"}
                  }
                ]
              }
            ]
          }
        })

      # When
      counts = Postgres.selective_testing_counts(command_event)

      # Then
      assert counts.selective_testing_local_hits_count == 3
      assert counts.selective_testing_remote_hits_count == 0
      assert counts.selective_testing_misses_count == 0
      assert counts.total_count == 3
    end

    test "counts handle targets with only one hit type - ClickHouse" do
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
                    "binary_cache_metadata" => %{"hash" => "hash-1", "hit" => "miss"}
                  },
                  %{
                    "name" => "TestTarget2",
                    "binary_cache_metadata" => %{"hash" => "hash-2", "hit" => "miss"}
                  }
                ]
              }
            ]
          }
        })

      # When
      counts = Clickhouse.binary_cache_counts(command_event)

      # Then
      assert counts.binary_cache_local_hits_count == 0
      assert counts.binary_cache_remote_hits_count == 0
      assert counts.binary_cache_misses_count == 2
      assert counts.total_count == 2
    end
  end
end
