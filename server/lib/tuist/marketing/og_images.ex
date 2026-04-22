defmodule Tuist.Marketing.OgImages do
  @moduledoc """
  Phoenix component that renders marketing page OG image cards as HTML.
  The rendered HTML is passed to Carta for screenshot capture via BrowseChrome.
  """
  use Phoenix.Component

  alias Phoenix.HTML.Safe

  attr :title, :string, required: true
  attr :font_data_uri, :string, required: true
  attr :logo_data_uri, :string, required: true
  attr :bg_data_uri, :string, required: true
  attr :icon_data_uri, :string, default: nil

  def card(assigns) do
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
           * Colors are hardcoded as hex instead of using Noora CSS variables because
           * headless Chrome doesn't reliably resolve oklch() values in gradient and
           * background-clip contexts. The hex equivalents match the Figma design
           * and correspond to these Noora tokens:
           *   #171a1c            -> --noora-neutral-light-1200 (title)
           *   #000 / #6a7581    -> logo gradient (from Figma, not a direct token)
           */
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body {
            width: 1920px;
            height: 1080px;
            overflow: hidden;
            font-family: 'Inter Variable', sans-serif;
            color-scheme: light;
          }
          .bg {
            position: absolute;
            inset: 0;
            width: 1920px;
            height: 1080px;
            object-fit: cover;
          }
          .icon {
            position: absolute;
            left: 50%;
            top: 50%;
            transform: translate(-50%, -30%);
            width: 724px;
            height: 724px;
            opacity: 0.45;
          }
          .title {
            position: absolute;
            left: 50%;
            top: 50%;
            transform: translate(-50%, -50%);
            font-size: 170px;
            font-weight: 500;
            letter-spacing: -1.7px;
            color: #171a1c;
            line-height: 1.1;
            text-shadow: 0px 1px 1px rgba(0, 0, 0, 0.25);
            text-align: center;
            max-width: 1700px;
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
            background: linear-gradient(92deg, #000 6%, #6a7581 109%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
          }
        </style>
      </head>
      <body>
        <img class="bg" src={@bg_data_uri} />
        <img :if={@icon_data_uri} class="icon" src={@icon_data_uri} />
        <div class="title">{@title}</div>
        <img class="logo-img" src={@logo_data_uri} />
        <div class="logo-tuist">Tuist</div>
      </body>
    </html>
    """
  end

  attr :title, :string, required: true
  attr :font_data_uri, :string, required: true
  attr :logo_data_uri, :string, required: true
  attr :phone_data_uri, :string, required: true

  def home_card(assigns) do
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
            color-scheme: light;
            background: linear-gradient(180deg, #f4f5fe 0%, #efe8ff 100%);
          }
          .title {
            position: absolute;
            left: 82px;
            top: 100px;
            width: 950px;
            font-size: 150px;
            font-weight: 500;
            letter-spacing: -1.5px;
            color: #171a1c;
            line-height: 1.1;
            text-shadow: 0px 1px 1px rgba(0, 0, 0, 0.25);
          }
          .phone {
            position: absolute;
            right: -20px;
            top: 380px;
            width: 870px;
            height: auto;
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
            background: linear-gradient(92deg, #000 6%, #6a7581 109%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
          }
        </style>
      </head>
      <body>
        <div class="title">{@title}</div>
        <img class="phone" src={@phone_data_uri} />
        <img class="logo-img" src={@logo_data_uri} />
        <div class="logo-tuist">Tuist</div>
      </body>
    </html>
    """
  end

  attr :title, :string, required: true
  attr :font_data_uri, :string, required: true
  attr :logo_data_uri, :string, required: true
  attr :bg_data_uri, :string, required: true
  attr :timeline_data_uri, :string, required: true

  def changelog_card(assigns) do
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
            color-scheme: light;
          }
          .bg {
            position: absolute;
            inset: 0;
            width: 1920px;
            height: 1080px;
            object-fit: cover;
          }
          .title {
            position: absolute;
            left: 50%;
            transform: translateX(-50%);
            top: 147px;
            font-size: 170px;
            font-weight: 500;
            letter-spacing: -1.7px;
            color: #171a1c;
            line-height: 1.1;
            text-shadow: 0px 1px 1px rgba(0, 0, 0, 0.25);
            text-align: center;
          }
          .timeline {
            position: absolute;
            left: 392px;
            top: 186px;
            width: 145px;
            height: 894px;
          }
          .entries {
            position: absolute;
            left: 50%;
            transform: translateX(calc(-50% - 9.5px));
            top: 446px;
            width: 769px;
            display: flex;
            flex-direction: column;
            gap: 100px;
          }
          .entry {
            width: 100%;
            height: 130px;
            background: rgba(255, 255, 255, 0.7);
            border-radius: 29px;
            box-shadow:
              0px 5px 5px 0px rgba(22,24,28,0.05),
              0px 0px 0px 5px rgba(46,51,56,0.08),
              0px 5px 5px 0px rgba(46,51,56,0.1);
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px 29px;
          }
          .entry-bar {
            flex: 1;
            height: 39px;
            background: rgba(230, 232, 234, 0.5);
            border-radius: 10px;
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
            background: linear-gradient(92deg, #000 6%, #6a7581 109%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
          }
        </style>
      </head>
      <body>
        <img class="bg" src={@bg_data_uri} />
        <img class="timeline" src={@timeline_data_uri} />
        <div class="title">{@title}</div>
        <div class="entries">
          <div class="entry">
            <div class="entry-bar"></div>
          </div>
          <div class="entry">
            <div class="entry-bar"></div>
          </div>
          <div class="entry">
            <div class="entry-bar"></div>
          </div>
        </div>
        <img class="logo-img" src={@logo_data_uri} />
        <div class="logo-tuist">Tuist</div>
      </body>
    </html>
    """
  end

  def render_changelog_list_html(opts) do
    title = Keyword.fetch!(opts, :title)
    fonts_dir = Keyword.fetch!(opts, :fonts_dir)
    logo_path = Keyword.fetch!(opts, :logo_path)
    bg_path = Keyword.fetch!(opts, :bg_path)
    timeline_path = Keyword.fetch!(opts, :timeline_path)

    font_base64 = fonts_dir |> Path.join("InterVariable.woff2") |> File.read!() |> Base.encode64()
    logo_base64 = logo_path |> File.read!() |> Base.encode64()
    bg_base64 = bg_path |> File.read!() |> Base.encode64()
    timeline_base64 = timeline_path |> File.read!() |> Base.encode64()

    assigns = %{
      title: title,
      font_data_uri: "data:font/woff2;base64,#{font_base64}",
      logo_data_uri: "data:image/webp;base64,#{logo_base64}",
      bg_data_uri: "data:image/webp;base64,#{bg_base64}",
      timeline_data_uri: "data:image/svg+xml;base64,#{timeline_base64}"
    }

    "<!DOCTYPE html>" <>
      (assigns |> changelog_card() |> Safe.to_iodata() |> IO.iodata_to_binary())
  end

  attr :title, :string, required: true
  attr :font_data_uri, :string, required: true
  attr :logo_data_uri, :string, required: true
  attr :bg_data_uri, :string, required: true

  def api_docs_card(assigns) do
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
            color-scheme: light;
          }
          .bg {
            position: absolute;
            inset: 0;
            width: 1920px;
            height: 1080px;
            object-fit: cover;
          }
          .title {
            position: absolute;
            left: 50%;
            transform: translateX(-50%);
            top: 151px;
            font-size: 170px;
            font-weight: 500;
            letter-spacing: -1.7px;
            color: #171a1c;
            line-height: 1.1;
            text-shadow: 0px 1px 1px rgba(0, 0, 0, 0.25);
            text-align: center;
            white-space: nowrap;
          }
          .cards-wrapper {
            position: absolute;
            left: 50%;
            transform: translateX(-50%);
            top: 350px;
            width: 870px;
            height: 920px;
          }
          .card-back {
            position: absolute;
            width: 693px;
            height: 765px;
            background: rgba(255, 255, 255, 0.6);
            border-radius: 28px;
            box-shadow:
              0px 10px 23px 0px rgba(0,0,0,0.04),
              0px 42px 42px 0px rgba(0,0,0,0.04),
              0px 94px 57px 0px rgba(0,0,0,0.02);
          }
          .card-back-left {
            left: 0;
            top: 50%;
            transform: translateY(-50%) rotate(-15deg);
            transform-origin: center;
          }
          .card-back-right {
            right: 0;
            top: 50%;
            transform: translateY(-50%) rotate(15deg);
            transform-origin: center;
          }
          .card-front {
            position: absolute;
            left: 50%;
            transform: translateX(-50%);
            top: 13px;
            width: 693px;
            height: 765px;
            background: rgba(255, 255, 255, 0.7);
            border-radius: 28px;
            box-shadow:
              0px 10px 23px 0px rgba(0,0,0,0.04),
              0px 42px 42px 0px rgba(0,0,0,0.04),
              0px 94px 57px 0px rgba(0,0,0,0.02);
            overflow: hidden;
          }
          .api-rows {
            position: absolute;
            left: 81px;
            top: 63px;
            display: flex;
            flex-direction: column;
            gap: 80px;
            width: 531px;
          }
          .api-row {
            display: flex;
            align-items: center;
            gap: 52px;
            width: 100%;
          }
          .api-dot {
            width: 45px;
            height: 45px;
            border-radius: 50%;
            background: rgba(160, 160, 220, 0.4);
            flex-shrink: 0;
          }
          .api-bar {
            flex: 1;
            height: 38px;
            background: rgba(179, 186, 193, 0.8);
            border-radius: 28px;
            opacity: 0.2;
          }
          .card-fade {
            position: absolute;
            bottom: 0;
            left: 0;
            right: 0;
            height: 300px;
            background: linear-gradient(to bottom, transparent 0%, rgba(244,245,254,0.8) 70%, #f0eaff 100%);
            border-radius: 0 0 28px 28px;
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
            background: linear-gradient(92deg, #000 6%, #6a7581 109%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
          }
        </style>
      </head>
      <body>
        <img class="bg" src={@bg_data_uri} />
        <div class="title">{@title}</div>
        <div class="cards-wrapper">
          <div class="card-back card-back-left"></div>
          <div class="card-back card-back-right"></div>
          <div class="card-front">
            <div class="api-rows">
              <div class="api-row">
                <div class="api-dot"></div>
                <div class="api-bar"></div>
              </div>
              <div class="api-row">
                <div class="api-dot"></div>
                <div class="api-bar"></div>
              </div>
              <div class="api-row">
                <div class="api-dot"></div>
                <div class="api-bar"></div>
              </div>
              <div class="api-row">
                <div class="api-dot"></div>
                <div class="api-bar"></div>
              </div>
              <div class="api-row">
                <div class="api-dot"></div>
                <div class="api-bar"></div>
              </div>
              <div class="api-row">
                <div class="api-dot"></div>
                <div class="api-bar"></div>
              </div>
            </div>
            <div class="card-fade"></div>
          </div>
        </div>
        <img class="logo-img" src={@logo_data_uri} />
        <div class="logo-tuist">Tuist</div>
      </body>
    </html>
    """
  end

  def render_api_docs_html(opts) do
    title = Keyword.fetch!(opts, :title)
    fonts_dir = Keyword.fetch!(opts, :fonts_dir)
    logo_path = Keyword.fetch!(opts, :logo_path)
    bg_path = Keyword.fetch!(opts, :bg_path)

    font_base64 = fonts_dir |> Path.join("InterVariable.woff2") |> File.read!() |> Base.encode64()
    logo_base64 = logo_path |> File.read!() |> Base.encode64()
    bg_base64 = bg_path |> File.read!() |> Base.encode64()

    assigns = %{
      title: title,
      font_data_uri: "data:font/woff2;base64,#{font_base64}",
      logo_data_uri: "data:image/webp;base64,#{logo_base64}",
      bg_data_uri: "data:image/webp;base64,#{bg_base64}"
    }

    "<!DOCTYPE html>" <>
      (assigns |> api_docs_card() |> Safe.to_iodata() |> IO.iodata_to_binary())
  end

  attr :title, :string, required: true
  attr :font_data_uri, :string, required: true
  attr :logo_data_uri, :string, required: true
  attr :bg_data_uri, :string, required: true
  attr :icon_data_uri, :string, required: true

  def newsletter_card(assigns) do
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
            color-scheme: light;
          }
          .bg {
            position: absolute;
            inset: 0;
            width: 1920px;
            height: 1080px;
            object-fit: cover;
          }
          .title {
            position: absolute;
            left: 50%;
            transform: translateX(-50%);
            top: 147px;
            font-size: 170px;
            font-weight: 500;
            letter-spacing: -1.7px;
            color: #171a1c;
            line-height: 1.1;
            text-shadow: 0px 1px 1px rgba(0, 0, 0, 0.25);
            text-align: center;
          }
          .envelope {
            position: absolute;
            left: 50%;
            transform: translateX(-50%);
            top: 446px;
            width: 878px;
            height: auto;
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
            background: linear-gradient(92deg, #000 6%, #6a7581 109%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
          }
        </style>
      </head>
      <body>
        <img class="bg" src={@bg_data_uri} />
        <div class="title">{@title}</div>
        <img class="envelope" src={@icon_data_uri} />
        <img class="logo-img" src={@logo_data_uri} />
        <div class="logo-tuist">Tuist</div>
      </body>
    </html>
    """
  end

  def render_newsletter_html(opts) do
    title = Keyword.fetch!(opts, :title)
    fonts_dir = Keyword.fetch!(opts, :fonts_dir)
    logo_path = Keyword.fetch!(opts, :logo_path)
    bg_path = Keyword.fetch!(opts, :bg_path)
    icon_path = Keyword.fetch!(opts, :icon_path)

    font_base64 = fonts_dir |> Path.join("InterVariable.woff2") |> File.read!() |> Base.encode64()
    logo_base64 = logo_path |> File.read!() |> Base.encode64()
    bg_base64 = bg_path |> File.read!() |> Base.encode64()
    icon_base64 = icon_path |> File.read!() |> Base.encode64()

    assigns = %{
      title: title,
      font_data_uri: "data:font/woff2;base64,#{font_base64}",
      logo_data_uri: "data:image/webp;base64,#{logo_base64}",
      bg_data_uri: "data:image/webp;base64,#{bg_base64}",
      icon_data_uri: "data:image/webp;base64,#{icon_base64}"
    }

    "<!DOCTYPE html>" <>
      (assigns |> newsletter_card() |> Safe.to_iodata() |> IO.iodata_to_binary())
  end

  attr :title, :string, required: true
  attr :font_data_uri, :string, required: true
  attr :logo_data_uri, :string, required: true
  attr :bg_data_uri, :string, required: true

  def blog_card(assigns) do
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
            color-scheme: light;
          }
          .bg {
            position: absolute;
            inset: 0;
            width: 1920px;
            height: 1080px;
            object-fit: cover;
          }
          .title {
            position: absolute;
            left: 50%;
            transform: translateX(-50%);
            top: 129px;
            font-size: 170px;
            font-weight: 500;
            letter-spacing: -1.7px;
            color: #171a1c;
            line-height: 1.1;
            text-shadow: 0px 1px 1px rgba(0, 0, 0, 0.25);
            text-align: center;
          }
          .blog-card {
            position: absolute;
            left: 50%;
            transform: translateX(-50%);
            top: 363px;
            width: 693px;
            height: 765px;
            background: rgba(255, 255, 255, 0.8);
            border-radius: 28px;
            box-shadow:
              0px 10px 23px 0px rgba(0,0,0,0.04),
              0px 42px 42px 0px rgba(0,0,0,0.04),
              0px 94px 57px 0px rgba(0,0,0,0.02);
            overflow: hidden;
          }
          .blog-image {
            position: absolute;
            left: 50%;
            transform: translateX(-50%);
            top: 39px;
            width: 621px;
            height: 313px;
            background: rgba(179, 186, 193, 0.5);
            border-radius: 28px;
            opacity: 0.2;
          }
          .blog-line {
            position: absolute;
            height: 38px;
            background: rgba(179, 186, 193, 0.5);
            border-radius: 28px;
            opacity: 0.2;
          }
          .blog-line-1 { left: 244px; top: 474px; width: 161px; }
          .blog-line-2 { left: 36px; top: 535px; width: 369px; }
          .blog-line-3 { left: 36px; top: 597px; width: 184px; }
          .blog-line-4 { left: 36px; top: 658px; width: 369px; }
          .blog-fade {
            position: absolute;
            left: 50%;
            transform: translateX(-50%);
            bottom: 0;
            width: 693px;
            height: 300px;
            background: linear-gradient(to bottom, transparent 0%, rgba(244,245,254,0.8) 70%, #f0eaff 100%);
            border-radius: 0 0 28px 28px;
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
            background: linear-gradient(92deg, #000 6%, #6a7581 109%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
          }
        </style>
      </head>
      <body>
        <img class="bg" src={@bg_data_uri} />
        <div class="title">{@title}</div>
        <div class="blog-card">
          <div class="blog-image"></div>
          <div class="blog-line blog-line-1"></div>
          <div class="blog-line blog-line-2"></div>
          <div class="blog-line blog-line-3"></div>
          <div class="blog-line blog-line-4"></div>
          <div class="blog-fade"></div>
        </div>
        <img class="logo-img" src={@logo_data_uri} />
        <div class="logo-tuist">Tuist</div>
      </body>
    </html>
    """
  end

  def render_blog_html(opts) do
    title = Keyword.fetch!(opts, :title)
    fonts_dir = Keyword.fetch!(opts, :fonts_dir)
    logo_path = Keyword.fetch!(opts, :logo_path)
    bg_path = Keyword.fetch!(opts, :bg_path)

    font_base64 = fonts_dir |> Path.join("InterVariable.woff2") |> File.read!() |> Base.encode64()
    logo_base64 = logo_path |> File.read!() |> Base.encode64()
    bg_base64 = bg_path |> File.read!() |> Base.encode64()

    assigns = %{
      title: title,
      font_data_uri: "data:font/woff2;base64,#{font_base64}",
      logo_data_uri: "data:image/webp;base64,#{logo_base64}",
      bg_data_uri: "data:image/webp;base64,#{bg_base64}"
    }

    "<!DOCTYPE html>" <>
      (assigns |> blog_card() |> Safe.to_iodata() |> IO.iodata_to_binary())
  end

  def render_home_html(opts) do
    title = Keyword.fetch!(opts, :title)
    fonts_dir = Keyword.fetch!(opts, :fonts_dir)
    logo_path = Keyword.fetch!(opts, :logo_path)
    phone_path = Keyword.fetch!(opts, :phone_path)

    font_base64 = fonts_dir |> Path.join("InterVariable.woff2") |> File.read!() |> Base.encode64()
    logo_base64 = logo_path |> File.read!() |> Base.encode64()
    phone_base64 = phone_path |> File.read!() |> Base.encode64()

    assigns = %{
      title: title,
      font_data_uri: "data:font/woff2;base64,#{font_base64}",
      logo_data_uri: "data:image/webp;base64,#{logo_base64}",
      phone_data_uri: "data:image/png;base64,#{phone_base64}"
    }

    "<!DOCTYPE html>" <>
      (assigns |> home_card() |> Safe.to_iodata() |> IO.iodata_to_binary())
  end

  def render_html(opts) do
    title = Keyword.fetch!(opts, :title)
    fonts_dir = Keyword.fetch!(opts, :fonts_dir)
    logo_path = Keyword.fetch!(opts, :logo_path)
    bg_path = Keyword.fetch!(opts, :bg_path)
    icon_path = Keyword.get(opts, :icon_path)

    font_base64 = fonts_dir |> Path.join("InterVariable.woff2") |> File.read!() |> Base.encode64()
    logo_base64 = logo_path |> File.read!() |> Base.encode64()
    bg_base64 = bg_path |> File.read!() |> Base.encode64()

    icon_data_uri =
      if icon_path do
        icon_base64 = icon_path |> File.read!() |> Base.encode64()

        mime =
          cond do
            String.ends_with?(icon_path, ".svg") -> "image/svg+xml"
            String.ends_with?(icon_path, ".png") -> "image/png"
            true -> "image/webp"
          end

        "data:#{mime};base64,#{icon_base64}"
      end

    assigns = %{
      title: title,
      font_data_uri: "data:font/woff2;base64,#{font_base64}",
      logo_data_uri: "data:image/webp;base64,#{logo_base64}",
      bg_data_uri: "data:image/webp;base64,#{bg_base64}",
      icon_data_uri: icon_data_uri
    }

    "<!DOCTYPE html>" <>
      (assigns |> card() |> Safe.to_iodata() |> IO.iodata_to_binary())
  end
end
