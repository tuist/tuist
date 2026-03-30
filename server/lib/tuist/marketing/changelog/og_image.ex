defmodule Tuist.Marketing.Changelog.OgImage do
  @moduledoc """
  Phoenix component that renders changelog OG image cards as HTML.
  The rendered HTML is passed to Carta for screenshot capture via BrowseChrome.
  """
  use Phoenix.Component

  @max_title_length 60
  @max_description_length 120

  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :pull_request, :integer, default: nil
  attr :font_data_uri, :string, required: true
  attr :logo_data_uri, :string, required: true

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
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body {
            width: 1920px;
            height: 1080px;
            overflow: hidden;
            font-family: 'DM Sans', sans-serif;
            color-scheme: light;
            background: linear-gradient(180deg, #f4f5fe 0%, #efe8ff 100%);
          }
          .content {
            position: absolute;
            left: calc(50% - 191.5px);
            top: 50%;
            transform: translate(-50%, -50%);
            width: 1383px;
            display: flex;
            flex-direction: column;
            gap: 48px;
          }
          .title {
            font-size: 128px;
            font-weight: 500;
            letter-spacing: -6.4px;
            color: #171a1c;
            line-height: normal;
            word-wrap: break-word;
            overflow-wrap: break-word;
          }
          .description {
            font-size: 64px;
            font-weight: 500;
            letter-spacing: -3.2px;
            color: #4e575f;
            line-height: normal;
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
            background: linear-gradient(92deg, #000 6%, #6a7581 109%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
          }
          .logo-divider {
            position: absolute;
            left: 290px;
            bottom: 67px;
            width: 3px;
            height: 80px;
            background-color: #c0c8cf;
          }
          .logo-section {
            position: absolute;
            left: 305px;
            bottom: 67px;
            font-size: 59px;
            font-weight: 500;
            letter-spacing: -2.9px;
            line-height: 80px;
            background: linear-gradient(92deg, #000 6%, #6a7581 109%);
            -webkit-background-clip: text;
            -webkit-text-fill-color: transparent;
          }
          .pull-request {
            position: absolute;
            right: 67px;
            bottom: 67px;
            font-size: 59px;
            font-weight: 500;
            letter-spacing: -2.9px;
            color: #171a1c;
            line-height: 80px;
          }
        </style>
      </head>
      <body>
        <div class="content">
          <div class="title">{truncate(@title, @max_title_length)}</div>
          <div :if={@description} class="description">
            {truncate(@description, @max_description_length)}
          </div>
        </div>
        <img class="logo-img" src={@logo_data_uri} />
        <div class="logo-tuist">Tuist</div>
        <div class="logo-divider"></div>
        <div class="logo-section">Changelog</div>
        <div :if={@pull_request} class="pull-request">{"##{@pull_request}"}</div>
      </body>
    </html>
    """
  end

  def render_html(opts) do
    title = Keyword.fetch!(opts, :title)
    description = Keyword.get(opts, :description)
    pull_request = Keyword.get(opts, :pull_request)
    fonts_dir = Keyword.fetch!(opts, :fonts_dir)
    logo_path = Keyword.fetch!(opts, :logo_path)

    font_base64 = fonts_dir |> Path.join("DMSans-latin.woff2") |> File.read!() |> Base.encode64()
    logo_base64 = logo_path |> File.read!() |> Base.encode64()

    assigns = %{
      title: title,
      description: description,
      pull_request: pull_request,
      font_data_uri: "data:font/woff2;base64,#{font_base64}",
      logo_data_uri: "data:image/webp;base64,#{logo_base64}",
      max_title_length: @max_title_length,
      max_description_length: @max_description_length
    }

    "<!DOCTYPE html>" <>
      (assigns |> card() |> Phoenix.HTML.Safe.to_iodata() |> IO.iodata_to_binary())
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
