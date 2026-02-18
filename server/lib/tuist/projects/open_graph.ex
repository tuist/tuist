defmodule Tuist.Projects.OpenGraph do
  @moduledoc """
  Utilities for generating and caching project dashboard Open Graph images.
  """

  alias Plug.Crypto
  alias Tuist.Storage

  @hash_version 8
  @max_key_values 3
  @max_title_length 72
  @max_key_length 24
  @max_value_length 48

  @title_font_sizes [140, 130, 120, 110, 100, 90, 80]
  @title_max_width 1_180

  @handle_x 116
  @handle_y 114

  @title_y 406

  @key_value_label_y 640
  @key_value_value_y 728
  @key_value_gap 56
  @key_value_side_padding 180
  @key_value_min_column_width 260
  @key_value_max_column_width 560
  @key_value_inner_padding 18
  @key_label_font_sizes [48, 44, 40, 36]
  @key_value_font_sizes [58, 54, 50, 46, 42, 38, 34]

  @template_relative_path Path.join(["static", "images", "open-graph", "card.png"])

  def image_url(account_handle, project_handle, title, key_values \\ []) do
    account_handle = normalize_handle(account_handle)
    project_handle = normalize_handle(project_handle)
    title = normalize_title(title)
    key_values = normalize_key_values(key_values)
    hash = image_hash(account_handle, project_handle, title, key_values)

    path = "/#{account_handle}/#{project_handle}/og/#{hash}"
    query_params = query_params(title, key_values)

    build_app_url(path, query_params)
  end

  def payload_from_request(account_handle, project_handle, hash, params) do
    account_handle = normalize_handle(account_handle)
    project_handle = normalize_handle(project_handle)
    title = normalize_title(Map.get(params, "title"))
    key_values = key_values_from_query(params)

    cond do
      title == "" ->
        {:error, :invalid_payload}

      valid_hash?(hash, image_hash(account_handle, project_handle, title, key_values)) ->
        {:ok,
         %{
           account_handle: account_handle,
           project_handle: project_handle,
           hash: normalize_hash(hash),
           title: title,
           key_values: key_values
         }}

      true ->
        {:error, :invalid_hash}
    end
  end

  def storage_key(%{account_handle: account_handle, project_handle: project_handle, hash: hash}) do
    "og/#{normalize_handle(account_handle)}/#{normalize_handle(project_handle)}/#{normalize_hash(hash)}.jpg"
  end

  def fetch_or_generate(payload, account) do
    object_key = storage_key(payload)

    if Storage.object_exists?(object_key, account) do
      {:ok, {:cached, object_key}}
    else
      with {:ok, image_binary} <- render_jpeg(payload) do
        Storage.put_object(object_key, image_binary, account)
        {:ok, {:generated, image_binary}}
      end
    end
  end

  def render_jpeg(%{account_handle: account_handle, project_handle: project_handle, title: title, key_values: key_values}) do
    key_values = normalize_key_values(key_values)
    handle = "#{normalize_handle(account_handle)}/#{normalize_handle(project_handle)}"
    title = normalize_title(title)

    with {:ok, base_image} <- Image.open(template_path()),
         {:ok, image} <- compose_text(base_image, handle, handle_text_options(), @handle_x, @handle_y),
         {:ok, title_image} <- render_fitted_title(title),
         {:ok, image} <- compose_centered_text(image, title_image, @title_y),
         {:ok, image} <- compose_key_values(image, key_values) do
      Image.write(image, :memory, suffix: ".jpg", quality: 95, strip_metadata: false)
    end
  end

  def default_title(nil), do: "Project"

  def default_title(head_title) when is_binary(head_title) do
    head_title
    |> String.split(" · ")
    |> List.first()
    |> normalize_title()
    |> case do
      "" -> "Project"
      title -> title
    end
  end

  def default_title(_), do: "Project"

  def default_key_values(account, project) do
    account_handle =
      account
      |> Map.get(:name)
      |> normalize_handle()
      |> case do
        "" -> "account"
        handle -> handle
      end

    [
      %{key: "Build System", value: build_system_label(Map.get(project, :build_system))},
      %{key: "Access", value: visibility_label(Map.get(project, :visibility))},
      %{key: "Account", value: account_handle}
    ]
  end

  defp compose_key_values(image, []), do: {:ok, image}

  defp compose_key_values(image, key_values) do
    count = length(key_values)
    column_widths = key_value_column_widths(image, key_values)
    total_width = Enum.sum(column_widths) + (count - 1) * @key_value_gap
    start_x = div(Image.width(image) - total_width, 2)

    key_values
    |> Enum.zip(column_widths)
    |> Enum.reduce_while({:ok, image, start_x}, fn {%{key: key, value: value}, column_width},
                                                   {:ok, current_image, column_x} ->
      image_width = Image.width(current_image)
      next_column_x = column_x + column_width + @key_value_gap

      with {:ok, key_image} <- render_fitted_key_label_text(key, column_width),
           {:ok, value_image} <- render_fitted_key_value_text(value, column_width),
           {:ok, image} <-
             Image.compose(current_image, key_image,
               x: centered_column_x(column_x, column_width, key_image, image_width),
               y: @key_value_label_y
             ),
           {:ok, image} <-
             Image.compose(image, value_image,
               x: centered_column_x(column_x, column_width, value_image, image_width),
               y: @key_value_value_y
             ) do
        {:cont, {:ok, image, next_column_x}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, image, _column_x} -> {:ok, image}
      {:error, _reason} = error -> error
    end
  end

  defp key_value_column_widths(_image, []), do: []

  defp key_value_column_widths(image, key_values) do
    count = length(key_values)
    gap_total = max(count - 1, 0) * @key_value_gap

    available_width =
      max(
        Image.width(image) - 2 * @key_value_side_padding - gap_total,
        count * @key_value_min_column_width
      )

    base_width =
      available_width
      |> div(max(count, 1))
      |> clamp(@key_value_min_column_width, @key_value_max_column_width)

    priorities = Enum.map(key_values, &column_priority/1)
    widths = List.duplicate(base_width, count)
    remaining = available_width - Enum.sum(widths)

    distribute_remaining_column_width(widths, priorities, remaining)
  end

  defp distribute_remaining_column_width(widths, _priorities, remaining) when remaining <= 0, do: widths

  defp distribute_remaining_column_width(widths, priorities, remaining) do
    if Enum.all?(widths, &(&1 >= @key_value_max_column_width)) do
      widths
    else
      current_index =
        widths
        |> Enum.with_index()
        |> Enum.filter(fn {width, _index} -> width < @key_value_max_column_width end)
        |> Enum.max_by(fn {width, index} ->
          priority = Enum.at(priorities, index)
          priority / width
        end)
        |> elem(1)

      width = Enum.at(widths, current_index)

      if width < @key_value_max_column_width do
        widths
        |> List.update_at(current_index, &(&1 + 1))
        |> distribute_remaining_column_width(priorities, remaining - 1)
      else
        distribute_remaining_column_width(widths, priorities, remaining)
      end
    end
  end

  defp column_priority(%{key: key, value: value}) do
    max(weighted_text_length(key), weighted_text_length(value) * 1.2)
  end

  defp weighted_text_length(text) do
    text
    |> to_string_safe()
    |> normalize_whitespace()
    |> String.graphemes()
    |> Enum.reduce(1.0, fn grapheme, acc ->
      acc + grapheme_weight(grapheme)
    end)
  end

  defp grapheme_weight(grapheme) do
    cond do
      grapheme in [" ", ".", "/", "-", "_"] -> 0.45
      grapheme =~ ~r/[A-Z]/ -> 1.05
      grapheme =~ ~r/[0-9]/ -> 0.9
      true -> 1.0
    end
  end

  defp centered_column_x(column_x, column_width, text_image, image_width) do
    centered_x = column_x + div(column_width - Image.width(text_image), 2)
    min_x = max(image_width - Image.width(text_image), 0)

    centered_x
    |> max(0)
    |> min(min_x)
  end

  defp render_fitted_key_label_text(text, column_width) do
    render_fitted_column_text(text, @key_label_font_sizes, &key_label_text_options/1, 1, column_width)
  end

  defp render_fitted_key_value_text(text, column_width) do
    render_fitted_column_text(text, @key_value_font_sizes, &key_value_text_options/1, 2, column_width)
  end

  defp render_fitted_column_text(_text, [], _options_fun, _max_lines, _column_width),
    do: {:error, :unable_to_render_key_value_text}

  defp render_fitted_column_text(text, [font_size | rest], options_fun, max_lines, column_width) do
    options = options_fun.(font_size)
    max_text_width = max(column_width - 2 * @key_value_inner_padding, 1)

    with {:ok, wrapped_text} <- wrap_text_to_width(text, options, max_lines, max_text_width),
         {:ok, image} <- Image.Text.text(wrapped_text, options) do
      {:ok, image}
    else
      {:overflow, lines} ->
        if rest == [] do
          lines = replace_last_line_with_ellipsis(lines, options, max_text_width)
          Image.Text.text(Enum.join(lines, "\n"), options)
        else
          render_fitted_column_text(text, rest, options_fun, max_lines, column_width)
        end

      {:error, :token_too_wide} ->
        if rest == [] do
          with {:ok, truncated_text} <- truncate_to_width_with_ellipsis(text, options, max_text_width) do
            Image.Text.text(truncated_text, options)
          end
        else
          render_fitted_column_text(text, rest, options_fun, max_lines, column_width)
        end

      {:error, _reason} = error ->
        if rest == [] do
          error
        else
          render_fitted_column_text(text, rest, options_fun, max_lines, column_width)
        end
    end
  end

  defp wrap_text_to_width(text, options, max_lines, max_text_width) do
    tokens = tokenize_for_wrap(text)

    case build_lines(tokens, options, max_lines, max_text_width, [], "") do
      {:ok, lines} ->
        {:ok, Enum.join(lines, "\n")}

      other ->
        other
    end
  end

  defp tokenize_for_wrap(text) do
    text
    |> to_string_safe()
    |> normalize_whitespace()
    |> String.split(" ", trim: true)
  end

  defp build_lines([], _options, _max_lines, _max_text_width, lines, current) do
    lines =
      if current == "" do
        lines
      else
        lines ++ [current]
      end

    if lines == [] do
      {:ok, [""]}
    else
      {:ok, lines}
    end
  end

  defp build_lines([token | rest], options, max_lines, max_text_width, lines, current) do
    with {:ok, token_width} <- text_width(token, options) do
      if token_width > max_text_width do
        {:error, :token_too_wide}
      else
        build_lines_with_fitting_token(token, rest, options, max_lines, max_text_width, lines, current)
      end
    end
  end

  defp build_lines_with_fitting_token(token, rest, options, max_lines, max_text_width, lines, current) do
    candidate =
      if current == "" do
        token
      else
        current <> " " <> token
      end

    case text_width(candidate, options) do
      {:ok, width} when width <= max_text_width ->
        build_lines(rest, options, max_lines, max_text_width, lines, candidate)

      {:ok, _width} ->
        if current == "" do
          {:error, :token_too_wide}
        else
          updated_lines = lines ++ [current]

          if length(updated_lines) >= max_lines do
            {:overflow, updated_lines}
          else
            build_lines([token | rest], options, max_lines, max_text_width, updated_lines, "")
          end
        end

      {:error, _reason} = error ->
        error
    end
  end

  defp text_width("", _options), do: {:ok, 0}

  defp text_width(text, options) do
    with {:ok, image} <- Image.Text.text(text, options) do
      {:ok, Image.width(image)}
    end
  end

  defp replace_last_line_with_ellipsis(lines, options, max_text_width) do
    {last, prefix} =
      lines
      |> Enum.reverse()
      |> then(fn [last | tail] -> {last, Enum.reverse(tail)} end)

    adjusted_last = fit_ellipsis(last, options, max_text_width)
    prefix ++ [adjusted_last]
  end

  defp fit_ellipsis(line, options, max_text_width) do
    candidate = String.trim_trailing(line) <> "…"

    case text_width(candidate, options) do
      {:ok, width} when width <= max_text_width ->
        candidate

      {:ok, _width} ->
        trimmed = line |> String.graphemes() |> Enum.drop(-1) |> Enum.join()

        if trimmed == "" do
          "…"
        else
          fit_ellipsis(trimmed, options, max_text_width)
        end

      {:error, _reason} ->
        "…"
    end
  end

  defp truncate_to_width_with_ellipsis(text, options, max_text_width) do
    text =
      text
      |> to_string_safe()
      |> normalize_whitespace()

    {:ok, fit_ellipsis(text, options, max_text_width)}
  end

  defp clamp(value, min_value, max_value) do
    value
    |> max(min_value)
    |> min(max_value)
  end

  defp compose_text(image, text, text_options, x, y) do
    with {:ok, text_image} <- Image.Text.text(text, text_options) do
      Image.compose(image, text_image, x: x, y: y)
    end
  end

  defp compose_centered_text(image, text_image, y) do
    x = div(Image.width(image) - Image.width(text_image), 2)
    Image.compose(image, text_image, x: max(x, 0), y: y)
  end

  defp render_fitted_title(title), do: render_fitted_title(title, @title_font_sizes)

  defp render_fitted_title(_title, []), do: {:error, :unable_to_render_title}

  defp render_fitted_title(title, [font_size | rest]) do
    case Image.Text.text(title, title_text_options(font_size)) do
      {:ok, title_image} ->
        cond do
          Image.width(title_image) <= @title_max_width -> {:ok, title_image}
          rest == [] -> {:ok, title_image}
          true -> render_fitted_title(title, rest)
        end

      {:error, _reason} = error ->
        if rest == [] do
          error
        else
          render_fitted_title(title, rest)
        end
    end
  end

  defp query_params(title, key_values) do
    Enum.reduce(Enum.with_index(key_values, 1), %{"title" => title}, fn {%{key: key, value: value}, index}, acc ->
      acc
      |> Map.put("k#{index}", key)
      |> Map.put("v#{index}", value)
    end)
  end

  defp key_values_from_query(params) do
    1..@max_key_values
    |> Enum.map(fn index ->
      key = params |> Map.get("k#{index}") |> normalize_key()
      value = params |> Map.get("v#{index}") |> normalize_value(@max_value_length)

      if key == "" or value == "" do
        nil
      else
        %{key: key, value: value}
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp image_hash(account_handle, project_handle, title, key_values) do
    key_values_for_hash =
      Enum.map(key_values, fn %{key: key, value: value} ->
        {key, value}
      end)

    payload = [
      @hash_version,
      normalize_handle(account_handle),
      normalize_handle(project_handle),
      normalize_title(title),
      key_values_for_hash
    ]

    secret = Tuist.Environment.secret_key_tokens()

    payload
    |> :erlang.term_to_binary()
    |> then(&:crypto.mac(:hmac, :sha256, secret, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_key_values(key_values) do
    key_values
    |> List.wrap()
    |> Enum.map(&normalize_key_value/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.take(@max_key_values)
  end

  defp normalize_key_value(%{key: key, value: value}), do: normalize_key_value({key, value})

  defp normalize_key_value({key, value}) do
    key = normalize_key(key)
    value = normalize_value(value, @max_value_length)

    if key == "" or value == "" do
      nil
    else
      %{key: key, value: value}
    end
  end

  defp normalize_key_value(_), do: nil

  defp normalize_title(value), do: normalize_value(value, @max_title_length)
  defp normalize_key(value), do: normalize_value(value, @max_key_length)

  defp normalize_value(value, max_length) do
    value
    |> to_string_safe()
    |> normalize_whitespace()
    |> String.slice(0, max_length)
  end

  defp normalize_handle(value) do
    value
    |> to_string_safe()
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_hash(value) do
    value
    |> to_string_safe()
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_whitespace(value) do
    value
    |> String.trim()
    |> String.replace(~r/\s+/, " ")
  end

  defp build_app_url(path, query_params) do
    [path: path]
    |> Tuist.Environment.app_url()
    |> URI.parse()
    |> Map.put(:query, URI.encode_query(query_params))
    |> URI.to_string()
  end

  defp template_path do
    :tuist
    |> :code.priv_dir()
    |> to_string()
    |> Path.join(@template_relative_path)
  end

  defp valid_hash?(actual, expected) when is_binary(actual) and is_binary(expected) do
    actual = normalize_hash(actual)
    expected = normalize_hash(expected)

    if byte_size(actual) == byte_size(expected) do
      Crypto.secure_compare(actual, expected)
    else
      false
    end
  end

  defp valid_hash?(_, _), do: false

  defp to_string_safe(nil), do: ""
  defp to_string_safe(value) when is_binary(value), do: value
  defp to_string_safe(value), do: to_string(value)

  defp visibility_label(:public), do: "Public"
  defp visibility_label(:private), do: "Private"
  defp visibility_label(_), do: "Public"

  defp build_system_label(:gradle), do: "Gradle"
  defp build_system_label(:xcode), do: "Xcode"
  defp build_system_label(_), do: "Unknown"

  defp handle_text_options do
    [
      font: "Inter Variable",
      font_weight: 400,
      font_size: 58,
      text_fill_color: [23, 25, 31]
    ]
  end

  defp title_text_options(font_size) do
    [
      font: "Inter Variable",
      font_weight: 400,
      font_size: font_size,
      text_fill_color: [9, 10, 16]
    ]
  end

  defp key_label_text_options(font_size) do
    [font: "Inter Variable", font_weight: 400, font_size: font_size, text_fill_color: [130, 141, 153]]
  end

  defp key_value_text_options(font_size) do
    [font: "Inter Variable", font_weight: 400, font_size: font_size, text_fill_color: [19, 22, 31]]
  end
end
