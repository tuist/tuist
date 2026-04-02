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
  attr :icon_data_uri, :string, default: nil

  def card(assigns) do
    ~H"""
    <html>
      <head>
        <meta charset="utf-8" />
        <style>
          @font-face {
            font-family: 'DM Sans';
            font-style: normal;
            font-weight: 400 600;
            src: url(<%= @font_data_uri %>) format('woff2');
          }
          /*
           * Colors are hardcoded as hex instead of using Noora CSS variables because
           * headless Chrome doesn't reliably resolve oklch() values in gradient and
           * background-clip contexts. The hex equivalents match the Figma design
           * and correspond to these Noora tokens:
           *   #f4f5fe / #efe8ff  -> --noora-purple-50 / --noora-purple-100 (background)
           *   #171a1c            -> --noora-neutral-light-1200 (title)
           *   #000 / #6a7581    -> logo gradient (from Figma, not a direct token)
           */
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body {
            width: 1920px;
            height: 1080px;
            overflow: hidden;
            font-family: 'DM Sans', sans-serif;
            color-scheme: light;
            background: linear-gradient(180deg, #f4f5fe 0%, #efe8ff 100%);
          }
          .icon {
            position: absolute;
            left: 50%;
            top: 50%;
            transform: translate(-50%, -30%);
            width: 724px;
            height: 724px;
            opacity: 0.15;
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
            font-family: 'DM Sans';
            font-style: normal;
            font-weight: 400 600;
            src: url(<%= @font_data_uri %>) format('woff2');
          }
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body {
            width: 1920px;
            height: 1080px;
            overflow: hidden;
            font-family: 'DM Sans', sans-serif;
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

  def render_home_html(opts) do
    title = Keyword.fetch!(opts, :title)
    fonts_dir = Keyword.fetch!(opts, :fonts_dir)
    logo_path = Keyword.fetch!(opts, :logo_path)
    phone_path = Keyword.fetch!(opts, :phone_path)

    font_base64 = fonts_dir |> Path.join("DMSans-latin.woff2") |> File.read!() |> Base.encode64()
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
    icon_path = Keyword.get(opts, :icon_path)

    font_base64 = fonts_dir |> Path.join("DMSans-latin.woff2") |> File.read!() |> Base.encode64()
    logo_base64 = logo_path |> File.read!() |> Base.encode64()

    icon_data_uri =
      if icon_path do
        icon_base64 = icon_path |> File.read!() |> Base.encode64()
        mime = if String.ends_with?(icon_path, ".png"), do: "image/png", else: "image/webp"
        "data:#{mime};base64,#{icon_base64}"
      end

    assigns = %{
      title: title,
      font_data_uri: "data:font/woff2;base64,#{font_base64}",
      logo_data_uri: "data:image/webp;base64,#{logo_base64}",
      icon_data_uri: icon_data_uri
    }

    "<!DOCTYPE html>" <>
      (assigns |> card() |> Safe.to_iodata() |> IO.iodata_to_binary())
  end
end
