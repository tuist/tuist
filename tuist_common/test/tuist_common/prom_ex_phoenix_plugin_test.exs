defmodule TuistCommon.PromExPhoenixPluginTest do
  use ExUnit.Case, async: true

  alias PromEx.MetricTypes.Event
  alias TuistCommon.PromExPhoenixPlugin

  defmodule Endpoint do
    def url, do: "https://tuist.dev"
  end

  defmodule ArticleController do
    def init(opts), do: opts
    def call(conn, _opts), do: conn
  end

  defmodule Router do
    use Phoenix.Router

    get("/articles", TuistCommon.PromExPhoenixPluginTest.ArticleController, :index)
  end

  describe "event_metrics/1" do
    test "omits host from Phoenix HTTP metric tags by default" do
      http_event = phoenix_http_event(router: Router, endpoint: Endpoint)

      assert Enum.all?(http_event.metrics, fn metric -> :host not in metric.tags end)

      [request_duration | _] = http_event.metrics

      conn =
        Plug.Test.conn(:get, "/articles")
        |> Map.put(:host, "preview-123.tuist.dev")
        |> Map.put(:status, 200)

      tag_values = request_duration.tag_values.(%{conn: conn})

      assert tag_values.path == "/articles"
      assert tag_values.method == "GET"
      assert tag_values.status == 200
      refute Map.has_key?(tag_values, :host)
    end

    test "can opt back into host labels" do
      http_event =
        phoenix_http_event(
          router: Router,
          endpoint: Endpoint,
          include_host_tag: true
        )

      assert Enum.all?(http_event.metrics, fn metric -> :host in metric.tags end)
    end

    test "can collapse status to status class" do
      http_event =
        phoenix_http_event(
          router: Router,
          endpoint: Endpoint,
          http_status_tag: :status_class
        )

      assert Enum.all?(http_event.metrics, fn metric ->
               :status_class in metric.tags and :status not in metric.tags
             end)

      [request_duration | _] = http_event.metrics

      conn =
        Plug.Test.conn(:get, "/articles")
        |> Map.put(:status, 404)

      tag_values = request_duration.tag_values.(%{conn: conn})

      assert tag_values.status_class == "4xx"
      refute Map.has_key?(tag_values, :status)
    end

    test "can drop controller and action labels while keeping path" do
      http_event =
        phoenix_http_event(
          router: Router,
          endpoint: Endpoint,
          include_controller_action_tags: false
        )

      assert Enum.all?(http_event.metrics, fn metric ->
               :path in metric.tags and :controller not in metric.tags and
                 :action not in metric.tags
             end)

      [request_duration | _] = http_event.metrics

      conn =
        Plug.Test.conn(:get, "/articles")
        |> Map.put(:status, 200)

      tag_values = request_duration.tag_values.(%{conn: conn})

      assert tag_values.path == "/articles"
      refute Map.has_key?(tag_values, :controller)
      refute Map.has_key?(tag_values, :action)
    end
  end

  defp phoenix_http_event(opts) do
    opts
    |> Keyword.put(:otp_app, :tuist_common)
    |> PromExPhoenixPlugin.event_metrics()
    |> Enum.find(fn %Event{group_name: group_name} ->
      group_name == :phoenix_http_event_metrics
    end)
  end
end
