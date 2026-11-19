defmodule Tuist.Snapshots.Thumbnail do
  @moduledoc """
  The small copy of a snapshot that the library grid shows: scaled down,
  never up, to fit 600×320 pixels (a tile at twice its CSS size), with
  its aspect ratio and transparency kept. It is a lossy WebP: UI renders
  compress well as PNG, and resampling them adds colours that a PNG copy pays
  for, so a PNG thumbnail of a small render can outweigh the original. The
  review pages keep showing the original.
  """

  @width 600
  @height 320

  def render(binary) do
    with {:ok, image} <- Image.from_binary(binary),
         {:ok, thumbnail} <- Image.thumbnail(image, @width, height: @height, resize: :down) do
      Image.write(thumbnail, :memory, suffix: ".webp", quality: 85)
    end
  end
end
