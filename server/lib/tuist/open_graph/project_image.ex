defmodule Tuist.OpenGraph.ProjectImage do
  @moduledoc """
  Renders the social card used by public project pages.

  The card intentionally uses self-contained HTML, fonts, and images so the
  headless browser does not depend on the application or object storage being
  reachable while it captures the image.
  """
  use Phoenix.Component

  alias Phoenix.HTML.Safe

  @max_title_length 60
  @max_subtitle_length 140

  attr :title, :string, required: true
  attr :project, :string, required: true
  attr :subtitle, :string, default: nil
  attr :badge, :string, default: nil
  attr :font_data_uri, :string, required: true
  attr :tuist_logo_data_uri, :string, required: true

  def card(assigns) do
    assigns =
      assigns
      |> assign(:title_class, title_class(assigns.title))
      |> assign(:max_title_length, @max_title_length)
      |> assign(:max_subtitle_length, @max_subtitle_length)

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
          /*
           * Colors match Asmit's dashboard OG designs in Figma
           * (nodes 524-464999 and 525-616230). Hardcoded as hex because
           * headless Chrome does not reliably resolve oklch() in gradient
           * and background-clip contexts.
           */
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body {
            width: 1920px;
            height: 1080px;
            overflow: hidden;
            font-family: 'Inter Variable', sans-serif;
            color-scheme: dark;
            background: #0a0a0c;
          }
          .pattern {
            position: absolute;
            inset: 0;
            overflow: hidden;
          }
          .pattern span {
            position: absolute;
            border: 1px solid rgba(255, 255, 255, 0.04);
            background: rgba(255, 255, 255, 0.012);
            border-radius: 4px;
          }
          .pattern .rect-a { left: -60px; top: -40px; width: 640px; height: 150px; }
          .pattern .rect-b { left: 520px; top: -40px; width: 700px; height: 210px; }
          .pattern .rect-c { left: 1160px; top: -40px; width: 820px; height: 190px; }
          .pattern .rect-d { left: -80px; top: 190px; width: 190px; height: 470px; }
          .pattern .rect-e { left: 60px; top: 190px; width: 90px; height: 210px; }
          .pattern .rect-f { left: 100px; top: 470px; width: 420px; height: 200px; }
          .pattern .rect-g { left: 470px; top: 720px; width: 470px; height: 180px; }
          .pattern .rect-h { left: 900px; top: 690px; width: 620px; height: 250px; }
          .pattern .rect-i { left: 1490px; top: 730px; width: 520px; height: 260px; }
          .pattern .rect-j { left: 1360px; top: 220px; width: 420px; height: 260px; }
          .content {
            position: absolute;
            left: 130px;
            right: 130px;
            top: 260px;
            display: flex;
            flex-direction: column;
            gap: 44px;
          }
          .title {
            max-width: 1520px;
            font-size: 168px;
            font-weight: 500;
            letter-spacing: -6.4px;
            color: #f2f3f5;
            line-height: 1.02;
            word-wrap: break-word;
            overflow-wrap: break-word;
          }
          .title.medium { font-size: 138px; letter-spacing: -5.2px; }
          .title.long { font-size: 108px; letter-spacing: -4px; }
          .subtitle {
            max-width: 1520px;
            font-size: 56px;
            font-weight: 400;
            letter-spacing: -1.8px;
            color: #9098a1;
            line-height: 1.25;
            word-wrap: break-word;
            overflow-wrap: break-word;
          }
          .logo-img {
            position: absolute;
            left: 67px;
            bottom: 67px;
            width: 80px;
            height: 80px;
          }
          .logo-tuist {
            position: absolute;
            left: 161px;
            bottom: 67px;
            font-size: 59px;
            font-weight: 500;
            letter-spacing: -2.9px;
            line-height: 80px;
            background: linear-gradient(92deg, #ffffff 6%, #8a929b 109%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
          }
          .logo-divider {
            position: absolute;
            left: 290px;
            bottom: 67px;
            width: 3px;
            height: 80px;
            background-color: rgba(255, 255, 255, 0.12);
          }
          .project-name {
            position: absolute;
            left: 305px;
            bottom: 67px;
            max-width: 900px;
            overflow: hidden;
            font-size: 59px;
            font-weight: 500;
            letter-spacing: -2.9px;
            line-height: 80px;
            color: #d8dbe0;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
          .badge {
            position: absolute;
            right: 67px;
            bottom: 67px;
            max-width: 700px;
            overflow: hidden;
            font-size: 59px;
            font-weight: 500;
            letter-spacing: -2.9px;
            line-height: 80px;
            color: #f2f3f5;
            text-align: right;
            text-overflow: ellipsis;
            white-space: nowrap;
          }
        </style>
      </head>
      <body>
        <div class="pattern">
          <span class="rect-a"></span>
          <span class="rect-b"></span>
          <span class="rect-c"></span>
          <span class="rect-d"></span>
          <span class="rect-e"></span>
          <span class="rect-f"></span>
          <span class="rect-g"></span>
          <span class="rect-h"></span>
          <span class="rect-i"></span>
          <span class="rect-j"></span>
        </div>
        <div class="content">
          <div class={["title", @title_class]}>{truncate(@title, @max_title_length)}</div>
          <div :if={@subtitle} class="subtitle">{truncate(@subtitle, @max_subtitle_length)}</div>
        </div>
        <img class="logo-img" src={@tuist_logo_data_uri} />
        <div class="logo-tuist">Tuist</div>
        <div class="logo-divider"></div>
        <div class="project-name">{@project}</div>
        <div :if={@badge} class="badge">{@badge}</div>
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
      font_data_uri: data_uri(Path.join(fonts_dir, "InterVariable.woff2"), "font/woff2"),
      tuist_logo_data_uri: data_uri(tuist_logo_path, "image/webp")
    }

    "<!DOCTYPE html>" <>
      (assigns |> card() |> Safe.to_iodata() |> IO.iodata_to_binary())
  end

  defp data_uri(path, content_type) do
    "data:#{content_type};base64,#{path |> File.read!() |> Base.encode64()}"
  end

  defp title_class(title) do
    case String.length(title) do
      length when length > 26 -> "long"
      length when length > 14 -> "medium"
      _ -> nil
    end
  end

  defp truncate(nil, _max), do: ""

  defp truncate(text, max) do
    if String.length(text) > max do
      text |> String.slice(0, max) |> String.trim_trailing() |> Kernel.<>("...")
    else
      text
    end
  end
end
