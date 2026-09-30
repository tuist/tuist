defmodule Tuist.Application.RuntimeChildrenTest do
  use ExUnit.Case, async: true

  alias Tuist.Application.RuntimeChildren
  alias Tuist.Environment

  describe "guardian_db_sweeper/1" do
    test ":web starts the sweeper" do
      assert [{Guardian.DB.Sweeper, opts}] = RuntimeChildren.guardian_db_sweeper(:web)
      assert Keyword.fetch!(opts, :interval) > 0
    end

    test "every non-web mode returns no children" do
      for mode <- Environment.modes(), mode != :web do
        assert RuntimeChildren.guardian_db_sweeper(mode) == [],
               "expected no Guardian.DB.Sweeper child for #{inspect(mode)} — " <>
                 "non-web pods connect with a DB role that lacks privileges on " <>
                 "`guardian_tokens` and the sweeper would fail every interval " <>
                 "with `permission denied`"
      end
    end
  end

  describe "open_graph_image_renderer/1" do
    test ":web starts the renderer and its task supervisor" do
      children = RuntimeChildren.open_graph_image_renderer(:web)

      assert {Task.Supervisor, name: Tuist.OpenGraphImageRenderer.TaskSupervisor} in children
      assert Tuist.OpenGraphImageRenderer in children
    end

    test "every non-web mode returns no children" do
      for mode <- Environment.modes(), mode != :web do
        assert RuntimeChildren.open_graph_image_renderer(mode) == [],
               "expected no Tuist.OpenGraphImageRenderer child for #{inspect(mode)} — " <>
                 "non-web images have no Chrome installed, so Browse.Pool.init_worker/1 " <>
                 "raises :chrome_not_found and NimblePool retries it forever without backoff"
      end
    end
  end

  describe "marketing_stats/1" do
    test ":web starts the poller" do
      assert RuntimeChildren.marketing_stats(:web) == [Tuist.Marketing.Stats]
    end

    test "every non-web mode returns no children" do
      for mode <- Environment.modes(), mode != :web do
        assert RuntimeChildren.marketing_stats(mode) == [],
               "expected no Tuist.Marketing.Stats child for #{inspect(mode)} — " <>
                 "it polls ClickHouse every 5 s only to feed the marketing LiveViews, " <>
                 "which non-web pods never serve"
      end
    end
  end
end
