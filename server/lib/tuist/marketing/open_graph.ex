defmodule Tuist.Marketing.OpenGraph do
  @moduledoc ~S"""
  This module provides utilities for generating open graph images for marketing routes.
  """
  use Phoenix.Component

  embed_templates "og_image/*"

  @max_length 35

  @doc """
  The title-on-template card for blog posts without a cover, changelog
  entries and newsletter issues: the title left-aligned on
  `og_template.png`.
  """
  def generate_og_image_binary(title) do
    generate(title, "og_template.png", :left)
  end

  @doc """
  The card for marketing pages without a designed one: the title centered
  on `og_marketing_template.png`.
  """
  def generate_title_card_binary(title) do
    generate(title, "og_marketing_template.png", :center)
  end

  defp generate(title, template, layout) do
    with {:ok, image} <- generate_image(title, template, layout) do
      Image.write(image, :memory, quality: 95, strip_metadata: false, suffix: ".jpg")
    end
  end

  # Text configuration: plain regular Inter in the primary label color on
  # the dark templates (neutral-light-50, #FDFDFD) — no weight, gradient
  # or shadow treatment. Line height is 100% (one font size per line).
  @font_size 100
  @text_options [
    font: "Inter Variable",
    font_weight: :normal,
    font_size: @font_size,
    text_fill_color: [253, 253, 253]
  ]
  @canvas_width 1920
  @canvas_height 1080
  @left_x 85
  @left_base_y 450

  defp generate_image(title, template, layout) do
    lines =
      title
      |> og_image_title_lines()
      |> Tuple.to_list()
      |> Enum.reject(&(&1 == ""))

    template_path = Path.join([Application.app_dir(:tuist, "priv"), "static", "images", template])

    with {:ok, background} <- Image.open(template_path) do
      lines
      |> Enum.with_index()
      |> Enum.reduce_while({:ok, background}, fn {line, index}, {:ok, image} ->
        case compose_line(image, line, index, length(lines), layout) do
          {:ok, composed} -> {:cont, {:ok, composed}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  # :left — the lines hang from a fixed baseline block above the wordmark;
  # :center — the block is centered on the canvas, every line centered.
  defp compose_line(image, line, index, line_count, layout) do
    with {:ok, text} <- Image.Text.text(line, @text_options) do
      {x, y} =
        case layout do
          :left ->
            {@left_x, @left_base_y + index * @font_size}

          :center ->
            block_top = div(@canvas_height - line_count * @font_size, 2)
            {div(@canvas_width - Image.width(text), 2), block_top + index * @font_size}
        end

      Image.compose(image, text, x: x, y: y)
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
