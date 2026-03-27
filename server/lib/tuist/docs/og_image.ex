defmodule Tuist.Docs.OgImage do
  @moduledoc """
  Phoenix component that renders documentation OG image cards as HTML.
  The rendered HTML is passed to Carta for screenshot capture via BrowseChrome.
  """
  use Phoenix.Component

  @noora_tokens_path Path.expand("../../../../noora/css/tokens.css", __DIR__)
  @external_resource @noora_tokens_path
  @noora_tokens File.read!(@noora_tokens_path)

  @max_title_length 60
  @max_description_length 120

  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :category, :string, default: "Docs"
  attr :font_data_uri, :string, required: true
  attr :logo_data_uri, :string, required: true
  attr :noora_tokens, :string, required: true

  def card(assigns) do
    ~H"""
    <html>
      <head>
        <meta charset="utf-8" />
        <meta name="color-scheme" content="light" />
        <style>
          {raw(@noora_tokens)}
        </style>
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
            background-color: var(--noora-purple-50);
          }
          .title {
            position: absolute;
            left: 269px;
            top: 200px;
            width: 1380px;
            max-height: 290px;
            font-size: 128px;
            font-weight: 500;
            letter-spacing: -6.4px;
            color: var(--noora-surface-label-primary);
            line-height: 1.1;
            overflow: hidden;
            word-wrap: break-word;
            overflow-wrap: break-word;
          }
          .description {
            position: absolute;
            left: 269px;
            top: 500px;
            width: 1380px;
            max-height: 380px;
            font-size: 64px;
            font-weight: 500;
            letter-spacing: -3.2px;
            color: var(--noora-surface-label-secondary);
            line-height: 1.2;
            overflow: hidden;
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
            background: linear-gradient(92deg, var(--noora-surface-label-primary) 6%, var(--noora-surface-label-secondary) 109%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            text-shadow: 0px 1.42px 4.26px rgba(27, 37, 80, 0.25);
          }
          .logo-divider {
            position: absolute;
            left: 290px;
            bottom: 67px;
            width: 3px;
            height: 80px;
            background-color: var(--noora-gray-200);
          }
          .logo-docs {
            position: absolute;
            left: 305px;
            bottom: 67px;
            font-size: 59px;
            font-weight: 500;
            letter-spacing: -2.9px;
            line-height: 80px;
            background: linear-gradient(92deg, var(--noora-surface-label-primary) 6%, var(--noora-surface-label-secondary) 109%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
            text-shadow: 0px 1.42px 4.26px rgba(27, 37, 80, 0.25);
          }
          .category {
            position: absolute;
            right: 67px;
            bottom: 67px;
            font-size: 59px;
            font-weight: 500;
            letter-spacing: -2.9px;
            color: var(--noora-surface-label-primary);
            line-height: 80px;
          }
        </style>
      </head>
      <body>
        <div class="title">{truncate(@title, @max_title_length)}</div>
        <div :if={@description} class="description">{truncate(@description, @max_description_length)}</div>
        <img class="logo-img" src={@logo_data_uri} />
        <div class="logo-tuist">Tuist</div>
        <div class="logo-divider"></div>
        <div class="logo-docs">Docs</div>
        <div class="category">{@category}</div>
      </body>
    </html>
    """
  end

  def render_html(opts) do
    title = Keyword.fetch!(opts, :title)
    description = Keyword.get(opts, :description)
    category = Keyword.get(opts, :category, "Docs")
    fonts_dir = Keyword.fetch!(opts, :fonts_dir)
    logo_path = Keyword.fetch!(opts, :logo_path)

    font_base64 = fonts_dir |> Path.join("DMSans-latin.woff2") |> File.read!() |> Base.encode64()
    logo_base64 = logo_path |> File.read!() |> Base.encode64()

    assigns = %{
      title: title,
      description: description,
      category: category,
      font_data_uri: "data:font/woff2;base64,#{font_base64}",
      logo_data_uri: "data:image/webp;base64,#{logo_base64}",
      noora_tokens: @noora_tokens,
      max_title_length: @max_title_length,
      max_description_length: @max_description_length
    }

    "<!DOCTYPE html>" <>
      (card(assigns) |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary())
  end

  def slug_to_filename(slug) do
    [locale | rest] = slug |> String.split("/", trim: true)
    page_path = rest |> Enum.join("-") |> then(&"#{&1}.jpg")
    Path.join(locale, page_path)
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
