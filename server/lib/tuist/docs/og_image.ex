defmodule Tuist.Docs.OgImage do
  @moduledoc """
  Generates the HTML used by Carta to render documentation open graph images.
  """

  def render_html(opts) do
    title = Keyword.fetch!(opts, :title)
    description = Keyword.get(opts, :description)
    category = Keyword.get(opts, :category, "Docs")
    fonts_dir = Keyword.fetch!(opts, :fonts_dir)
    logo_path = Keyword.fetch!(opts, :logo_path)

    font_base64 = fonts_dir |> Path.join("DMSans-latin.woff2") |> File.read!() |> Base.encode64()
    logo_base64 = logo_path |> File.read!() |> Base.encode64()

    """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <style>
      @font-face {
        font-family: 'DM Sans';
        font-style: normal;
        font-weight: 400 600;
        src: url(data:font/woff2;base64,#{font_base64}) format('woff2');
      }

      * { margin: 0; padding: 0; box-sizing: border-box; }

      body {
        width: 1920px;
        height: 1080px;
        overflow: hidden;
        font-family: 'DM Sans', sans-serif;
        background: linear-gradient(to bottom, #f4f5fe, #efe8ff);
        position: relative;
      }

      .content {
        position: absolute;
        top: 50%;
        left: 269px;
        transform: translateY(-50%);
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
        line-height: 1;
        word-wrap: break-word;
      }

      .description {
        font-size: 64px;
        font-weight: 500;
        letter-spacing: -3.2px;
        color: #4e575f;
        line-height: 1.15;
        word-wrap: break-word;
      }

      .footer {
        position: absolute;
        bottom: 67px;
        left: 67px;
        right: 67px;
        display: flex;
        align-items: center;
        justify-content: space-between;
      }

      .logo-group {
        display: flex;
        align-items: center;
        gap: 14px;
      }

      .logo-img {
        width: 80px;
        height: 80px;
        object-fit: contain;
      }

      .logo-text {
        display: flex;
        align-items: center;
        gap: 12px;
        font-size: 59px;
        font-weight: 500;
        letter-spacing: -2.9px;
        background: linear-gradient(92deg, #000 6%, #6a7581 109%);
        -webkit-background-clip: text;
        -webkit-text-fill-color: transparent;
      }

      .logo-divider {
        width: 0;
        height: 80px;
        border-left: 3px solid #c0c8cf;
      }

      .category {
        font-size: 59px;
        font-weight: 500;
        letter-spacing: -2.9px;
        color: #171a1c;
      }
    </style>
    </head>
    <body>
      <div class="content">
        <div class="title">#{escape_html(title)}</div>
        #{if description, do: "<div class=\"description\">#{escape_html(description)}</div>", else: ""}
      </div>

      <div class="footer">
        <div class="logo-group">
          <img class="logo-img" src="data:image/webp;base64,#{logo_base64}" />
          <div class="logo-text">
            <span>Tuist</span>
            <div class="logo-divider"></div>
            <span>Docs</span>
          </div>
        </div>
        <div class="category">#{escape_html(category)}</div>
      </div>
    </body>
    </html>
    """
  end

  defp escape_html(nil), do: ""

  defp escape_html(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
  end
end
