defmodule AtlasWeb.Docs.SocialImage do
  @moduledoc false
  use Phoenix.Component

  import Phoenix.HTML

  alias Phoenix.HTML.Safe

  @mark_path Path.expand("../../../priv/static/images/atlas-docs-mark.svg", __DIR__)
  @external_resource @mark_path
  @mark File.read!(@mark_path)

  def render(page) do
    %{page: page, mark: @mark, __changed__: nil}
    |> card()
    |> Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  attr :page, :map, required: true
  attr :mark, :string, required: true

  defp card(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <style>
          * { margin: 0; padding: 0; box-sizing: border-box; }
          html, body { width: 1920px; height: 1080px; overflow: hidden; font-family: Arial, sans-serif; background: #0e0e0e; color: #fdfdfd; }
          [data-part="content"] { position: absolute; left: 76px; top: 260px; width: 1768px; display: flex; flex-direction: column; gap: 67px; }
          [data-part="title"] { font-size: 136px; font-weight: 400; line-height: 136px; letter-spacing: -0.03em; overflow-wrap: break-word; }
          [data-part="description"] { font-size: 56px; line-height: 70px; letter-spacing: -0.01em; color: #c7ccd1; max-width: 1640px; }
          [data-part="footer"] { position: absolute; left: 76px; bottom: 66px; display: flex; align-items: center; gap: 24px; font-size: 58px; }
          [data-part="footer"] svg { width: 72px; height: 72px; }
          [data-part="divider"] { width: 2px; height: 58px; background: #464646; }
          [data-part="category"] { position: absolute; right: 77px; bottom: 66px; font-size: 58px; line-height: 72px; color: #72c9ec; }
        </style>
      </head>
      <body>
        <div data-part="content">
          <h1 data-part="title">{@page.title}</h1>
          <p data-part="description">{@page.description}</p>
        </div>
        <div data-part="footer">
          {raw(@mark)}<span>Atlas</span><span data-part="divider"></span><span>Docs</span>
        </div>
        <div data-part="category">{@page.category}</div>
      </body>
    </html>
    """
  end
end
