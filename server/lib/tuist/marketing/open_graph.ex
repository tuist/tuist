defmodule Tuist.Marketing.OpenGraph do
  @moduledoc ~S"""
  This module provides utilities for generating open graph images for marketing routes.
  """
  use Phoenix.Component

  embed_templates "og_image/*"

  @max_length 35

  def generate_og_image_binary(title) do
    with {:ok, image} <- generate_image(title) do
      Image.write(image, :memory, quality: 95, strip_metadata: false, suffix: ".jpg")
    end
  end

  defp generate_image(title) do
    {title_line_1, title_line_2, title_line_3} = og_image_title_lines(title)

    # Load the background template image
    template_path = Path.join([Application.app_dir(:tuist, "priv"), "static", "images", "og_template.png"])

    # Text configuration
    # Color oklch(21.7% 0.002 247.941) - converted to RGB [25, 26, 27]
    text_options = [
      font: "Inter Variable",
      font_weight: 500,
      font_size: 100,
      text_fill_color: [25, 26, 27]
    ]

    # Composite the text overlays onto the template.
    # Line height: 100% (100px spacing = font size)
    font_size = text_options[:font_size]
    base_y = 450

    lines = [
      {title_line_1, base_y},
      {title_line_2, base_y + font_size},
      {title_line_3, base_y + font_size * 2}
    ]

    with {:ok, background} <- Image.open(template_path) do
      Enum.reduce_while(lines, {:ok, background}, fn {line, y}, {:ok, image} ->
        case compose_line(image, line, y, text_options) do
          {:ok, composed} -> {:cont, {:ok, composed}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp compose_line(image, "", _y, _text_options), do: {:ok, image}

  defp compose_line(image, line, y, text_options) do
    with {:ok, text} <- Image.Text.text(line, text_options) do
      Image.compose(image, text, x: 85, y: y)
    end
  end

  # credo:disable-for-next-line Credo.Check.Refactor.CyclomaticComplexity
  def og_image_title_lines(title) do
    words = String.split(title, " ")

    {line1, line2, line3, _} =
      Enum.reduce(words, {"", "", "", 0}, fn word, {line1, line2, line3, line_number} ->
        cond do
          line_number == 0 and String.length(line1) + String.length(word) + 1 <= @max_length ->
            {line1 <> if(line1 == "", do: "", else: " ") <> word, line2, line3, 0}

          line_number <= 1 and String.length(line2) + String.length(word) + 1 <= @max_length ->
            {line1, line2 <> if(line2 == "", do: "", else: " ") <> word, line3, 1}

          line_number <= 2 and String.length(line3) + String.length(word) + 1 <= @max_length ->
            # credo:disable-for-next-line Credo.Check.Refactor.Nesting
            {line1, line2, line3 <> if(line3 == "", do: "", else: " ") <> word, 2}

          true ->
            {line1, line2, line3 <> "...", 3}
        end
      end)

    {String.trim(line1), String.trim(line2), String.trim(line3)}
  end
end
