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
  attr :date, :string, default: nil
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
            top: 44%;
            transform: translate(-50%, -50%);
            width: 1383px;
            display: flex;
            flex-direction: column;
            gap: 48px;
          }
          .date {
            font-size: 42px;
            font-weight: 500;
            letter-spacing: -1px;
            color: #4e575f;
            line-height: normal;
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
            display: flex;
            align-items: center;
            gap: 12px;
            font-size: 36px;
            font-weight: 500;
            letter-spacing: -1px;
            color: #4e575f;
            line-height: 80px;
          }
          .pull-request svg {
            width: 40px;
            height: 40px;
            fill: #4e575f;
          }
        </style>
      </head>
      <body>
        <div class="content">
          <div :if={@date} class="date">{@date}</div>
          <div class="title">{truncate(@title, @max_title_length)}</div>
          <div :if={@description} class="description">
            {truncate(@description, @max_description_length)}
          </div>
        </div>
        <img class="logo-img" src={@logo_data_uri} />
        <div class="logo-tuist">Tuist</div>
        <div class="logo-divider"></div>
        <div class="logo-section">Changelog</div>
        <div :if={@pull_request} class="pull-request">
          <svg viewBox="0 0 16 16" xmlns="http://www.w3.org/2000/svg">
            <path d="M8 0c4.42 0 8 3.58 8 8a8.013 8.013 0 0 1-5.45 7.59c-.4.08-.55-.17-.55-.38 0-.27.01-1.13.01-2.2 0-.75-.25-1.23-.54-1.48 1.78-.2 3.65-.88 3.65-3.95 0-.88-.31-1.59-.82-2.15.08-.2.36-1.02-.08-2.12 0 0-.67-.22-2.2.82-.64-.18-1.32-.27-2-.27-.68 0-1.36.09-2 .27-1.53-1.03-2.2-.82-2.2-.82-.44 1.1-.16 1.92-.08 2.12-.51.56-.82 1.28-.82 2.15 0 3.06 1.86 3.75 3.64 3.95-.23.2-.44.55-.51 1.07-.46.21-1.61.55-2.33-.66-.15-.24-.6-.83-1.23-.82-.67.01-.27.38.01.53.34.19.73.9.82 1.13.16.45.68 1.31 2.69.94 0 .67.01 1.3.01 1.49 0 .21-.15.45-.55.38A7.995 7.995 0 0 1 0 8c0-4.42 3.58-8 8-8Z" />
          </svg>
          {"github.com/tuist/tuist/pull/#{@pull_request}"}
        </div>
      </body>
    </html>
    """
  end

  def render_html(opts) do
    title = Keyword.fetch!(opts, :title)
    description = Keyword.get(opts, :description)
    date = Keyword.get(opts, :date)
    pull_request = Keyword.get(opts, :pull_request)
    fonts_dir = Keyword.fetch!(opts, :fonts_dir)
    logo_path = Keyword.fetch!(opts, :logo_path)

    font_base64 = fonts_dir |> Path.join("DMSans-latin.woff2") |> File.read!() |> Base.encode64()
    logo_base64 = logo_path |> File.read!() |> Base.encode64()

    assigns = %{
      title: title,
      description: description,
      date: date,
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
