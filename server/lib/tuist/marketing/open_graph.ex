defmodule Tuist.Marketing.OpenGraph do
  @moduledoc ~S"""
  This module provides utilities for generating open graph images for marketing routes.
  """
  use Phoenix.Component

  embed_templates "og_image/*"

  @max_length 35

  @doc """
  Generates an OG image with the given title and saves it to the specified path.

  If locale is provided, it will be included in the path structure before the filename.
  For example: path="/og/about.jpg", locale="ko" -> "/og/ko/about.jpg"
  """
  def generate_og_image(title, path, locale \\ nil) do
    final_path = apply_locale_to_path(path, locale)
    {title_line_1, title_line_2, title_line_3} = og_image_title_lines(title)

    parent_directory = Path.dirname(final_path)

    if not File.exists?(parent_directory) do
      File.mkdir_p!(parent_directory)
    end

    # Load the background template image
    template_path = Path.join([Application.app_dir(:tuist, "priv"), "static", "images", "og_template.png"])
    {:ok, background} = Image.open(template_path)

    # Text configuration
    # Color oklch(21.5% 0.006 236.9) - converted to RGB [46, 48, 57]
    text_options = [
      font: "Inter Variable",
      font_weight: 500,
      font_size: 100,
      text_fill_color: [46, 48, 57]
    ]

    # Create and composite text overlays
    # Line height: 100% (100px spacing = font size)
    image = background
    font_size = text_options[:font_size]
    base_y = 450

    image =
      if title_line_1 == "" do
        image
      else
        {:ok, text1} = Image.Text.text(title_line_1, text_options)
        {:ok, composed} = Image.compose(image, text1, x: 85, y: base_y)
        composed
      end

    image =
      if title_line_2 == "" do
        image
      else
        {:ok, text2} = Image.Text.text(title_line_2, text_options)
        {:ok, composed} = Image.compose(image, text2, x: 85, y: base_y + font_size)
        composed
      end

    image =
      if title_line_3 == "" do
        image
      else
        {:ok, text3} = Image.Text.text(title_line_3, text_options)
        {:ok, composed} = Image.compose(image, text3, x: 85, y: base_y + font_size * 2)
        composed
      end

    # Save as JPEG with high quality and proper color space
    Image.write!(image, final_path, quality: 95, strip_metadata: false)
  end

  defp apply_locale_to_path(path, nil), do: path
  defp apply_locale_to_path(path, "en"), do: path

  defp apply_locale_to_path(path, locale) do
    dirname = Path.dirname(path)
    basename = Path.basename(path)
    Path.join([dirname, locale, basename])
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
