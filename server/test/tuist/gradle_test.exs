defmodule Tuist.GradleTest do
  use TuistTestSupport.Cases.DataCase, async: false

  alias Tuist.Gradle
  alias TuistTestSupport.Fixtures.GradleFixtures

  describe "cache_hit_rate/1" do
    test "returns 100.0 when all cacheable tasks are cache hits" do
      build = %{tasks_local_hit_count: 3, tasks_remote_hit_count: 2, cacheable_tasks_count: 5}
      assert Gradle.cache_hit_rate(build) == 100.0
    end

    test "returns 0.0 when all cacheable tasks are misses" do
      build = %{tasks_local_hit_count: 0, tasks_remote_hit_count: 0, cacheable_tasks_count: 4}
      assert Gradle.cache_hit_rate(build) == 0.0
    end

    test "returns the correct percentage for a mix of hits and misses" do
      build = %{tasks_local_hit_count: 2, tasks_remote_hit_count: 1, cacheable_tasks_count: 4}
      assert Gradle.cache_hit_rate(build) == 75.0
    end

    test "returns nil when there are no cacheable tasks" do
      build = %{tasks_local_hit_count: 0, tasks_remote_hit_count: 0, cacheable_tasks_count: 0}
      assert Gradle.cache_hit_rate(build) == nil
    end
  end

  describe "cacheable_tasks_count" do
    test "counts executed and hit cacheable tasks" do
      build_id =
        GradleFixtures.build_fixture(
          tasks: [
            %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true},
            %{task_path: ":app:compileJava", outcome: "remote_hit", cacheable: true},
            %{task_path: ":app:processResources", outcome: "executed", cacheable: true}
          ]
        )

      {:ok, build} = Gradle.get_build(build_id)
      assert build.cacheable_tasks_count == 3
    end

    test "excludes up_to_date cacheable tasks" do
      build_id =
        GradleFixtures.build_fixture(
          tasks: [
            %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true},
            %{task_path: ":app:processResources", outcome: "up_to_date", cacheable: true}
          ]
        )

      {:ok, build} = Gradle.get_build(build_id)
      assert build.cacheable_tasks_count == 1
    end

    test "excludes non-cacheable executed tasks" do
      build_id =
        GradleFixtures.build_fixture(
          tasks: [
            %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true},
            %{task_path: ":app:assemble", outcome: "executed", cacheable: false}
          ]
        )

      {:ok, build} = Gradle.get_build(build_id)
      assert build.cacheable_tasks_count == 1
    end

    test "returns 0 when all cacheable tasks are up_to_date" do
      build_id =
        GradleFixtures.build_fixture(
          tasks: [
            %{task_path: ":app:compileKotlin", outcome: "up_to_date", cacheable: true},
            %{task_path: ":app:assemble", outcome: "executed", cacheable: false}
          ]
        )

      {:ok, build} = Gradle.get_build(build_id)
      assert build.cacheable_tasks_count == 0
    end
  end

  describe "cache_hit_rate/1 with cacheable_tasks_count" do
    test "is 100% when all cacheable tasks are hits, even with non-cacheable executed tasks" do
      build_id =
        GradleFixtures.build_fixture(
          tasks: [
            %{task_path: ":app:compileKotlin", outcome: "local_hit", cacheable: true},
            %{task_path: ":app:compileJava", outcome: "remote_hit", cacheable: true},
            %{task_path: ":app:assemble", outcome: "executed", cacheable: false},
            %{task_path: ":app:package", outcome: "executed", cacheable: false}
          ]
        )

      {:ok, build} = Gradle.get_build(build_id)
      assert Gradle.cache_hit_rate(build) == 100.0
    end

    test "is nil when there are only up_to_date cacheable tasks" do
      build_id =
        GradleFixtures.build_fixture(
          tasks: [
            %{task_path: ":app:compileKotlin", outcome: "up_to_date", cacheable: true},
            %{task_path: ":app:assemble", outcome: "executed", cacheable: false}
          ]
        )

      {:ok, build} = Gradle.get_build(build_id)
      assert Gradle.cache_hit_rate(build) == nil
    end
  end
end
