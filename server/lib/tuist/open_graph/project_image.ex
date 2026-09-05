defmodule Tuist.OpenGraph.ProjectImage do
  @moduledoc """
  Renders the social card used by public project pages.

  The card intentionally uses self-contained HTML, fonts, and images so the
  headless browser does not depend on the application or object storage being
  reachable while it captures the image.
  """
  use Phoenix.Component

  alias Phoenix.HTML.Safe

  attr :title, :string, required: true
  attr :project, :string, required: true
  attr :subtitle, :string, default: nil
  attr :badge, :string, default: nil
  attr :metric_one_label, :string, default: nil
  attr :metric_one_value, :string, default: nil
  attr :metric_two_label, :string, default: nil
  attr :metric_two_value, :string, default: nil
  attr :chart, :list, default: []
  attr :chart_label, :string, default: nil
  attr :chart_kind, :string, default: "line"
  attr :chart_categories, :list, default: []
  attr :font_data_uri, :string, required: true
  attr :logo_data_uri, :string, default: nil
  attr :tuist_logo_data_uri, :string, required: true

  def card(assigns) do
    assigns =
      assigns
      |> assign(:project_initial, assigns.project |> String.trim() |> String.first() |> String.upcase())
      |> assign(:chart_points, chart_points(assigns.chart))
      |> assign(:chart_bars, chart_bars(assigns.chart, assigns.chart_categories))
      |> assign(:title_class, title_class(assigns.title))

    ~H"""
    <html>
      <head>
        <meta charset="utf-8" />
        <style>
          @font-face {
            font-family: 'Inter Variable';
            font-style: normal;
            font-weight: 100 900;
            src: url(<%= @font_data_uri %>) format('woff2');
          }
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body {
            width: 1920px;
            height: 1080px;
            overflow: hidden;
            font-family: 'Inter Variable', sans-serif;
            color: #171a1c;
            background:
              radial-gradient(circle at 78% 18%, rgba(120, 119, 238, 0.28), transparent 34%),
              radial-gradient(circle at 88% 94%, rgba(83, 191, 106, 0.18), transparent 32%),
              linear-gradient(145deg, #f7f8ff 0%, #eeeaff 100%);
          }
          body::before {
            content: '';
            position: absolute;
            inset: 0;
            opacity: 0.35;
            background-image: radial-gradient(#9ba4ae 1px, transparent 1px);
            background-size: 34px 34px;
            mask-image: linear-gradient(90deg, transparent 0%, black 55%, black 100%);
          }
          .content {
            position: absolute;
            inset: 82px;
            display: grid;
            grid-template-columns: 1.05fr 0.95fr;
            gap: 88px;
          }
          .identity {
            min-width: 0;
            display: flex;
            flex-direction: column;
          }
          .project {
            display: flex;
            align-items: center;
            gap: 28px;
            min-width: 0;
          }
          .project-logo,
          .project-initial {
            width: 116px;
            height: 116px;
            flex: 0 0 116px;
            border-radius: 28px;
            box-shadow: 0 18px 50px rgba(34, 32, 72, 0.18);
          }
          .project-logo {
            object-fit: contain;
            background: white;
          }
          .project-initial {
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-size: 58px;
            font-weight: 650;
            background: linear-gradient(145deg, #6f6de7, #4b49ba);
          }
          .project-name {
            overflow: hidden;
            color: #525e6b;
            font-size: 43px;
            font-weight: 570;
            letter-spacing: -1.2px;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .copy {
            margin-top: auto;
            margin-bottom: auto;
          }
          .badge {
            display: inline-flex;
            align-items: center;
            min-height: 52px;
            padding: 8px 22px;
            border: 2px solid rgba(98, 95, 209, 0.22);
            border-radius: 999px;
            color: #5653bd;
            background: rgba(255, 255, 255, 0.72);
            font-size: 27px;
            font-weight: 620;
            letter-spacing: 0.1px;
          }
          .title {
            max-width: 900px;
            margin-top: 28px;
            font-size: 112px;
            font-weight: 610;
            letter-spacing: -5.2px;
            line-height: 0.98;
            text-wrap: balance;
          }
          .title.medium { font-size: 94px; letter-spacing: -4.3px; }
          .title.long { font-size: 78px; letter-spacing: -3.4px; overflow-wrap: anywhere; }
          .subtitle {
            max-width: 850px;
            margin-top: 34px;
            color: #5f6b77;
            font-size: 38px;
            font-weight: 470;
            letter-spacing: -0.7px;
            line-height: 1.25;
          }
          .tuist {
            display: flex;
            align-items: center;
            gap: 17px;
            color: #4b5560;
            font-size: 31px;
            font-weight: 560;
          }
          .tuist img {
            width: 48px;
            height: 48px;
          }
          .insight {
            position: relative;
            align-self: center;
            width: 100%;
            height: 760px;
            padding: 54px;
            overflow: hidden;
            border: 2px solid rgba(121, 119, 205, 0.16);
            border-radius: 46px;
            background: rgba(255, 255, 255, 0.82);
            box-shadow:
              0 30px 80px rgba(48, 45, 91, 0.12),
              0 2px 10px rgba(48, 45, 91, 0.06);
          }
          .insight::after {
            content: '';
            position: absolute;
            width: 430px;
            height: 430px;
            right: -190px;
            bottom: -210px;
            border-radius: 50%;
            background: rgba(111, 109, 231, 0.1);
          }
          .metric-grid {
            display: grid;
            grid-template-columns: repeat(2, minmax(0, 1fr));
            gap: 26px;
          }
          .metric {
            min-height: 176px;
            padding: 30px;
            border: 2px solid #ebecef;
            border-radius: 27px;
            background: rgba(255, 255, 255, 0.86);
          }
          .metric-label {
            color: #697582;
            font-size: 27px;
            font-weight: 520;
          }
          .metric-value {
            margin-top: 14px;
            overflow: hidden;
            font-size: 56px;
            font-weight: 650;
            letter-spacing: -2.5px;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .chart-label {
            margin-top: 52px;
            color: #697582;
            font-size: 27px;
            font-weight: 520;
          }
          .bar-chart {
            position: absolute;
            left: 54px;
            right: 54px;
            bottom: 54px;
            height: 345px;
            display: flex;
            align-items: end;
            justify-content: space-around;
            gap: 34px;
            padding: 0 18px;
            border-bottom: 2px solid #e5e7ea;
            background: repeating-linear-gradient(
              to bottom,
              transparent 0,
              transparent 84px,
              #eceef1 85px,
              transparent 87px
            );
          }
          .bar-column {
            height: 100%;
            min-width: 0;
            flex: 1;
            display: flex;
            flex-direction: column;
            justify-content: end;
            align-items: center;
          }
          .bar-value {
            margin-bottom: 10px;
            color: #4b5560;
            font-size: 23px;
            font-weight: 600;
          }
          .bar {
            width: min(116px, 72%);
            min-height: 8px;
            border-radius: 16px 16px 5px 5px;
            background: linear-gradient(180deg, #7774e7, #5d5acb);
            box-shadow: 0 8px 20px rgba(104, 101, 220, 0.2);
          }
          .bar-category {
            width: 100%;
            margin-top: 13px;
            overflow: hidden;
            color: #697582;
            font-size: 22px;
            font-weight: 520;
            text-align: center;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .chart {
            position: absolute;
            left: 54px;
            right: 54px;
            bottom: 58px;
            height: 350px;
          }
          .chart-grid {
            position: absolute;
            inset: 0;
            border-bottom: 2px solid #e5e7ea;
            background: repeating-linear-gradient(
              to bottom,
              transparent 0,
              transparent 86px,
              #eceef1 87px,
              transparent 89px
            );
          }
          .chart-area {
            position: absolute;
            inset: 0;
            clip-path: polygon(<%= Enum.map_join(@chart_points, ", ", fn {x, y} -> "#{x}% #{y}%" end) %>, 100% 100%, 0 100%);
            background: linear-gradient(180deg, rgba(111, 109, 231, 0.34), rgba(111, 109, 231, 0.02));
          }
          .chart-line {
            position: absolute;
            inset: 0;
            clip-path: polygon(<%= Enum.map_join(@chart_points, ", ", fn {x, y} -> "#{x}% #{y}%" end) %>);
            background: #6865dc;
            filter: drop-shadow(0 4px 7px rgba(104, 101, 220, 0.28));
          }
          .chart-line-mask {
            position: absolute;
            inset: 4px 0 0;
            clip-path: polygon(<%= Enum.map_join(@chart_points, ", ", fn {x, y} -> "#{x}% #{y}%" end) %>);
            background: white;
          }
          .empty-visual {
            position: absolute;
            inset: 225px 54px 54px;
            display: grid;
            grid-template-columns: repeat(6, 1fr);
            align-items: end;
            gap: 24px;
          }
          .empty-visual span {
            border-radius: 18px 18px 7px 7px;
            background: linear-gradient(180deg, rgba(111, 109, 231, 0.55), rgba(111, 109, 231, 0.12));
          }
          .empty-visual span:nth-child(1) { height: 30%; }
          .empty-visual span:nth-child(2) { height: 48%; }
          .empty-visual span:nth-child(3) { height: 42%; }
          .empty-visual span:nth-child(4) { height: 71%; }
          .empty-visual span:nth-child(5) { height: 63%; }
          .empty-visual span:nth-child(6) { height: 88%; }
        </style>
      </head>
      <body>
        <div class="content">
          <section class="identity">
            <div class="project">
              <img :if={@logo_data_uri} class="project-logo" src={@logo_data_uri} alt="" />
              <div :if={is_nil(@logo_data_uri)} class="project-initial">{@project_initial}</div>
              <div class="project-name">{@project}</div>
            </div>
            <div class="copy">
              <div :if={@badge} class="badge">{@badge}</div>
              <h1 class={["title", @title_class]}>{@title}</h1>
              <p :if={@subtitle} class="subtitle">{@subtitle}</p>
            </div>
            <div class="tuist">
              <img src={@tuist_logo_data_uri} alt="" />
              <span>Build faster with Tuist · tuist.dev</span>
            </div>
          </section>
          <section class="insight">
            <div :if={@metric_one_value || @metric_two_value} class="metric-grid">
              <div :if={@metric_one_value} class="metric">
                <div class="metric-label">{@metric_one_label}</div>
                <div class="metric-value">{@metric_one_value}</div>
              </div>
              <div :if={@metric_two_value} class="metric">
                <div class="metric-label">{@metric_two_label}</div>
                <div class="metric-value">{@metric_two_value}</div>
              </div>
            </div>
            <div :if={@chart != []} class="chart-label">{@chart_label}</div>
            <div :if={@chart != [] and @chart_kind == "line"} class="chart">
              <div class="chart-grid"></div>
              <div class="chart-area"></div>
              <div class="chart-line"></div>
              <div class="chart-line-mask"></div>
            </div>
            <div :if={@chart != [] and @chart_kind == "bars"} class="bar-chart">
              <div :for={{value, category, height} <- @chart_bars} class="bar-column">
                <div class="bar-value">{value}</div>
                <div class="bar" style={"height: #{height}%"}></div>
                <div class="bar-category">{category}</div>
              </div>
            </div>
            <div :if={@chart == []} class="empty-visual">
              <span></span><span></span><span></span><span></span><span></span><span></span>
            </div>
          </section>
        </div>
      </body>
    </html>
    """
  end

  def render_html(opts) do
    fonts_dir = Keyword.fetch!(opts, :fonts_dir)
    tuist_logo_path = Keyword.fetch!(opts, :tuist_logo_path)

    assigns = %{
      __changed__: nil,
      title: Keyword.fetch!(opts, :title),
      project: Keyword.fetch!(opts, :project),
      subtitle: Keyword.get(opts, :subtitle),
      badge: Keyword.get(opts, :badge),
      metric_one_label: Keyword.get(opts, :metric_one_label),
      metric_one_value: Keyword.get(opts, :metric_one_value),
      metric_two_label: Keyword.get(opts, :metric_two_label),
      metric_two_value: Keyword.get(opts, :metric_two_value),
      chart: Keyword.get(opts, :chart, []),
      chart_label: Keyword.get(opts, :chart_label),
      chart_kind: Keyword.get(opts, :chart_kind, "line"),
      chart_categories: Keyword.get(opts, :chart_categories, []),
      font_data_uri: data_uri(Path.join(fonts_dir, "InterVariable.woff2"), "font/woff2"),
      logo_data_uri: logo_data_uri(opts),
      tuist_logo_data_uri: data_uri(tuist_logo_path, "image/webp")
    }

    "<!DOCTYPE html>" <>
      (assigns |> card() |> Safe.to_iodata() |> IO.iodata_to_binary())
  end

  defp logo_data_uri(opts) do
    with binary when is_binary(binary) <- Keyword.get(opts, :logo_binary),
         content_type when is_binary(content_type) <- Keyword.get(opts, :logo_content_type) do
      "data:#{content_type};base64,#{Base.encode64(binary)}"
    else
      _ -> nil
    end
  end

  defp data_uri(path, content_type) do
    "data:#{content_type};base64,#{path |> File.read!() |> Base.encode64()}"
  end

  defp title_class(title) do
    case String.length(title) do
      length when length > 28 -> "long"
      length when length > 18 -> "medium"
      _ -> nil
    end
  end

  defp chart_points([]), do: []

  defp chart_points(values) do
    max_value = max(Enum.max(values, fn -> 1 end), 1)
    denominator = max(length(values) - 1, 1)

    values
    |> Enum.with_index()
    |> Enum.map(fn {value, index} ->
      x = Float.round(index / denominator * 100, 2)
      y = Float.round(88 - value / max_value * 72, 2)
      {x, y}
    end)
  end

  defp chart_bars([], _categories), do: []

  defp chart_bars(values, categories) do
    max_value = max(Enum.max(values, fn -> 1 end), 1)

    values
    |> Enum.zip(categories)
    |> Enum.map(fn {value, category} ->
      height = max(Float.round(value / max_value * 78, 2), 2)
      {value, category, height}
    end)
  end
end
