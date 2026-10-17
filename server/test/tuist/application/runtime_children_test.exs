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
                 "it polls marketing stats only to feed the marketing LiveViews, " <>
                 "which non-web pods never serve"
      end
    end
  end

  describe "readiness_server/1" do
    test ":xcresult_processor serves Tuist.Readiness.Plug on the readiness port" do
      assert [{Plug.Cowboy, opts}] = RuntimeChildren.readiness_server(:xcresult_processor)
      assert Keyword.fetch!(opts, :plug) == Tuist.Readiness.Plug
      assert opts |> Keyword.fetch!(:options) |> Keyword.fetch!(:port) == Tuist.Readiness.port()
    end

    test "every other mode returns no children" do
      for mode <- Environment.modes(), mode != :xcresult_processor do
        assert RuntimeChildren.readiness_server(mode) == [],
               "expected no readiness listener for #{inspect(mode)}; only the xcresult processor is probed through it"
      end
    end
  end
end
