defmodule Tuist.Marketing.OgImages do
  @moduledoc """
  HTML wrapper for the Open Graph images rendered from SVG artwork (the
  customer case studies' and blog posts' covers): a 1920x1080 near-black
  page the artwork fills edge to edge.
  """

  @doc """
  The Open Graph card for a customer case study: the dark variant of the
  generated cover artwork (see Tuist.Marketing.Customers.CoverArtwork),
  full-bleed on the dark-scheme page background. The 352×198 artwork
  scales cleanly to the renderer's 1920×1080 viewport (both 16:9), and
  the colors are baked into the SVG/wrapper because no stylesheet travels
  with a social card.
  """
  def render_case_study_html(opts) do
    svg = Keyword.fetch!(opts, :svg)

    """
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8" />
        <style>
          * { margin: 0; padding: 0; }
          html, body { width: 1920px; height: 1080px; overflow: hidden; background: #0E0E0E; }
          svg[data-part="artwork"] { display: block; width: 1920px; height: 1080px; color: #F6F6F6; }
        </style>
      </head>
      <body>#{svg}</body>
    </html>
    """
  end
end
