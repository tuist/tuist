defmodule Tuist.Snapshots.Diff do
  @moduledoc """
  Pixel comparison of a snapshot with its baseline.

  The comparison is exact: a pixel differs when any of its RGBA channels
  differs. Both images are read as 8-bit sRGB with alpha, so an opaque PNG and
  the same pixels with an alpha channel compare equal. Images of different
  sizes are laid on a transparent canvas of the larger width and height,
  anchored top left, so a screen that grew by a row shows that row as changed
  rather than the whole image.

  The rendered diff paints the differing pixels red over a faded grayscale
  copy of the new image, so a reviewer sees where the change is.
  """
  alias Vix.Vips.Operation

  def compare(head_binary, baseline_binary) do
    with {:ok, head} <- normalize(head_binary),
         {:ok, baseline} <- normalize(baseline_binary) do
      {width, height} = canvas(head, baseline)

      with {:ok, head} <- extend(head, width, height),
           {:ok, baseline} <- extend(baseline, width, height) do
        compare_pixels(head, baseline)
      end
    end
  end

  def dimensions(%Vix.Vips.Image{} = image), do: {Image.width(image), Image.height(image)}

  def dimensions(binary) when is_binary(binary) do
    with {:ok, image} <- Image.from_binary(binary) do
      {:ok, dimensions(image)}
    end
  end

  defp canvas(head, baseline) do
    {head_width, head_height} = dimensions(head)
    {baseline_width, baseline_height} = dimensions(baseline)
    {max(head_width, baseline_width), max(head_height, baseline_height)}
  end

  defp extend(image, width, height) do
    if dimensions(image) == {width, height} do
      {:ok, image}
    else
      Operation.embed(image, 0, 0, width, height, extend: :VIPS_EXTEND_BACKGROUND, background: [0.0, 0.0, 0.0, 0.0])
    end
  end

  defp compare_pixels(head, baseline) do
    with {:ok, different} <- Operation.relational(head, baseline, :VIPS_OPERATION_RELATIONAL_NOTEQ),
         {:ok, mask} <- Operation.bandbool(different, :VIPS_OPERATION_BOOLEAN_OR),
         {:ok, average} <- Operation.avg(mask) do
      ratio = average / 255

      if ratio == 0 do
        {:ok, %{ratio: 0.0, diff_png: nil}}
      else
        with {:ok, diff_png} <- render(head, mask) do
          {:ok, %{ratio: ratio, diff_png: diff_png}}
        end
      end
    end
  end

  defp render(head, mask) do
    with {:ok, rgb} <- Operation.extract_band(head, 0, n: 3),
         {:ok, gray} <- Operation.colourspace(rgb, :VIPS_INTERPRETATION_B_W),
         {:ok, faded} <- Operation.linear(gray, [0.3], [178.5]),
         {:ok, faded} <- Operation.cast(faded, :VIPS_FORMAT_UCHAR),
         {:ok, background} <- Operation.bandjoin([faded, faded, faded]),
         {:ok, painted} <- Image.if_then_else(mask, [255, 0, 0], background) do
      Image.write(painted, :memory, suffix: ".png")
    end
  end

  defp normalize(binary) do
    with {:ok, image} <- Image.from_binary(binary),
         {:ok, image} <- Image.to_colorspace(image, :srgb),
         {:ok, image} <- ensure_alpha(image) do
      Operation.cast(image, :VIPS_FORMAT_UCHAR)
    end
  end

  defp ensure_alpha(image) do
    if Image.has_alpha?(image), do: {:ok, image}, else: Image.add_alpha(image, 255)
  end
end
