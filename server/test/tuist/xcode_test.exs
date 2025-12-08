defmodule Tuist.XcodeTest do
  use TuistTestSupport.Cases.DataCase

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Xcode
  alias Tuist.Xcode.XcodeGraph
  alias Tuist.Xcode.XcodeProject
  alias Tuist.Xcode.XcodeTarget
  alias TuistTestSupport.Fixtures.CommandEventsFixtures

  describe "Tuist.Xcode" do
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
      {:ok, xcode_graph} =
        with_flushed_ingestion_buffers(fn ->
          Xcode.create_xcode_graph(xcode_data)
        end)

      # Then
      assert xcode_graph.name == "TestGraph"
      assert xcode_graph.command_event_id == command_event.id

      # Verify data was written to ClickHouse
      [graph_ch] =
        ClickHouseRepo.all(from(g in XcodeGraph, where: g.command_event_id == ^command_event.id))

      assert graph_ch.name == "TestGraph"
      assert graph_ch.command_event_id == command_event.id

      [project_ch] =
        ClickHouseRepo.all(from(p in XcodeProject, where: p.xcode_graph_id == ^graph_ch.id))

      assert project_ch.name == "ProjectA"
      assert project_ch.path == "App"
      assert project_ch.xcode_graph_id == graph_ch.id

      targets_ch =
        from(t in XcodeTarget, where: t.xcode_project_id == ^project_ch.id)
        |> ClickHouseRepo.all()
        |> Enum.map(&XcodeTarget.normalize_enums/1)
        |> Enum.sort_by(& &1.name)

      assert Enum.map(targets_ch, & &1.name) == ["TargetA", "TargetB", "TargetBTests"]
      assert Enum.map(targets_ch, & &1.binary_cache_hash) == ["hash-a", "hash-b", nil]
      assert Enum.map(targets_ch, & &1.binary_cache_hit) == [:miss, :local, :miss]
      assert Enum.map(targets_ch, & &1.selective_testing_hash) == [nil, nil, "hash-c"]
      assert Enum.map(targets_ch, & &1.selective_testing_hit) == [:miss, :miss, :remote]
    end

    test "has_selective_testing_data?/1 returns true when selective testing data exists" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        with_flushed_ingestion_buffers(fn ->
          Xcode.create_xcode_graph(%{
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
        end)

      # When
      result = Xcode.has_selective_testing_data?(command_event)

      # Then
      assert result == true
    end

    test "has_selective_testing_data?/1 returns false when no selective testing data exists" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        with_flushed_ingestion_buffers(fn ->
          Xcode.create_xcode_graph(%{
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
        end)

      # When
      result = Xcode.has_selective_testing_data?(command_event)

      # Then
      assert result == false
    end

    test "has_binary_cache_data?/1 returns true when binary cache data exists" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        with_flushed_ingestion_buffers(fn ->
          Xcode.create_xcode_graph(%{
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
        end)

      # When
      result = Xcode.has_binary_cache_data?(command_event)

      # Then
      assert result == true
    end

    test "has_binary_cache_data?/1 returns false when no binary cache data exists" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        with_flushed_ingestion_buffers(fn ->
          Xcode.create_xcode_graph(%{
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
        end)

      # When
      result = Xcode.has_binary_cache_data?(command_event)

      # Then
      assert result == false
    end

    test "selective_testing_analytics/1 returns analytics from ClickHouse data" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        with_flushed_ingestion_buffers(fn ->
          Xcode.create_xcode_graph(%{
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
        end)

      # When (with retry for materialized view population)
      {analytics, _meta} = Xcode.selective_testing_analytics(command_event)

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
        with_flushed_ingestion_buffers(fn ->
          Xcode.create_xcode_graph(%{
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
        end)

      # When
      {analytics, _meta} = Xcode.binary_cache_analytics(command_event)

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

  describe "Tuist.Xcode analytics" do
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
        with_flushed_ingestion_buffers(fn ->
          Xcode.create_xcode_graph(%{
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
        end)

      # When - First page (with retry for materialized view population)
      {result, meta} = Xcode.selective_testing_analytics(command_event, %{page_size: 10})

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
        with_flushed_ingestion_buffers(fn ->
          Xcode.create_xcode_graph(%{
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
        end)

      # When - First page (with retry for materialized view population)
      {result, meta} = Xcode.binary_cache_analytics(command_event, %{page_size: 10})

      # Then
      assert length(result.cacheable_targets) == 10
      assert meta.total_count == 15
      assert meta.total_pages == 2
    end

    test "selective_testing_counts/1 returns aggregate counts for ClickHouse" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        with_flushed_ingestion_buffers(fn ->
          Xcode.create_xcode_graph(%{
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
        end)

      # When (with retry for materialized view population)
      counts = Xcode.selective_testing_counts(command_event)

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
        with_flushed_ingestion_buffers(fn ->
          Xcode.create_xcode_graph(%{
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
        end)

      # When (with retry for materialized view population)
      counts = Xcode.binary_cache_counts(command_event)

      # Then
      assert counts.binary_cache_local_hits_count == 1
      assert counts.binary_cache_remote_hits_count == 1
      assert counts.binary_cache_misses_count == 2
      assert counts.total_count == 4
      assert counts.cache_hit_rate == 50.0
    end

    test "binary_cache_counts/1 returns zeros and 0.0 cache hit rate for empty data" do
      # Given
      command_event = CommandEventsFixtures.command_event_fixture()

      {:ok, _xcode_graph} =
        with_flushed_ingestion_buffers(fn ->
          Xcode.create_xcode_graph(%{
            command_event: command_event,
            xcode_graph: %{
              name: "EmptyCacheGraph",
              projects: [
                %{
                  "name" => "EmptyProject",
                  "path" => "EmptyApp",
                  "targets" => []
                }
              ]
            }
          })
        end)

      # When
      counts = Xcode.binary_cache_counts(command_event)

      # Then
      assert counts.binary_cache_local_hits_count == 0
      assert counts.binary_cache_remote_hits_count == 0
      assert counts.binary_cache_misses_count == 0
      assert counts.total_count == 0
      assert counts.cache_hit_rate == 0.0
    end
  end

  test "selective_testing_counts/1 returns zeros for empty data" do
    # Given
    command_event = CommandEventsFixtures.command_event_fixture()

    {:ok, _xcode_graph} =
      with_flushed_ingestion_buffers(fn ->
        Xcode.create_xcode_graph(%{
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
      end)

    # When
    counts = Xcode.selective_testing_counts(command_event)

    # Then
    assert counts.selective_testing_local_hits_count == 0
    assert counts.selective_testing_remote_hits_count == 0
    assert counts.selective_testing_misses_count == 0
    assert counts.total_count == 0
  end

  test "analytics with empty flop params returns all data" do
    # Given
    command_event = CommandEventsFixtures.command_event_fixture()

    {:ok, _xcode_graph} =
      with_flushed_ingestion_buffers(fn ->
        Xcode.create_xcode_graph(%{
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
      end)

    # When - Call without flop params (with retry for materialized view population)
    {result, meta} = Xcode.selective_testing_analytics(command_event)

    # Then
    assert length(result.test_modules) == 2
    assert meta.total_count == 2
  end

  test "counts handle targets with only one hit type" do
    # Given
    command_event = CommandEventsFixtures.command_event_fixture()

    {:ok, _xcode_graph} =
      with_flushed_ingestion_buffers(fn ->
        Xcode.create_xcode_graph(%{
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
      end)

    # When
    counts = Xcode.binary_cache_counts(command_event)

    # Then
    assert counts.binary_cache_local_hits_count == 0
    assert counts.binary_cache_remote_hits_count == 0
    assert counts.binary_cache_misses_count == 2
    assert counts.total_count == 2
  end

  describe "humanize_xcode_target_destination/1" do
    test "returns human-readable name for known destinations" do
      assert Xcode.humanize_xcode_target_destination("iphone") == "iPhone"
      assert Xcode.humanize_xcode_target_destination("mac_with_ipad_design") == "Mac with iPad design"
    end

    test "returns input unchanged for unknown destinations" do
      assert Xcode.humanize_xcode_target_destination("unknown") == "unknown"
    end
  end
end
