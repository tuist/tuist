defmodule AtlasWeb.AccountLive.Screenshots do
  @moduledoc false

  use Gettext, backend: AtlasWeb.Gettext

  @max_bytes 5 * 1024 * 1024
  @max_count 6
  @allowed_media_types ~w(image/png image/jpeg image/jpg image/webp image/gif)

  def stage(existing_screenshots, pasted_screenshots) do
    {accepted, errors, _remaining} =
      Enum.reduce(pasted_screenshots, {[], [], @max_count - length(existing_screenshots)}, fn params,
                                                                                              {accepted, errors,
                                                                                               remaining} ->
        if remaining <= 0 do
          {accepted,
           add_error(
             errors,
             gettext("Only %{count} screenshots can be staged at once.", count: @max_count)
           ), 0}
        else
          case build(params) do
            {:ok, screenshot} ->
              screenshot = ensure_unique_id(screenshot, existing_screenshots, accepted)
              {[screenshot | accepted], errors, remaining - 1}

            {:error, message} ->
              {accepted, add_error(errors, message), remaining}
          end
        end
      end)

    {existing_screenshots ++ Enum.reverse(accepted), List.first(Enum.reverse(errors))}
  end

  def build(%{"data" => data, "media_type" => media_type} = params) do
    size = size(params["size"], data)

    cond do
      not is_binary(data) or data == "" ->
        {:error, gettext("Could not read screenshot. Please paste it again.")}

      media_type not in @allowed_media_types ->
        {:error, gettext("Unsupported screenshot format. Use PNG, JPEG, WebP, or GIF.")}

      size > @max_bytes ->
        {:error, gettext("Screenshot is too large. Max size is 5 MB.")}

      true ->
        {:ok,
         %{
           id: id(data),
           data: data,
           media_type: media_type,
           size: size,
           name: Map.get(params, "name")
         }}
    end
  end

  def build(_params), do: {:error, gettext("Could not read screenshot. Please paste it again.")}

  def size(size, _data) when is_integer(size), do: size

  def size(size, data) when is_binary(size) do
    case Integer.parse(size) do
      {parsed, ""} -> parsed
      _other -> byte_size(data)
    end
  end

  def size(_size, data), do: byte_size(data)

  def id(data) do
    hash =
      data
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    "screenshot-#{hash}"
  end

  def preview_src(%{media_type: media_type, data: data}) do
    "data:#{media_type};base64,#{data}"
  end

  def count_label(1), do: gettext("1 screenshot ready")
  def count_label(count), do: gettext("%{count} screenshots ready", count: count)

  def analysis_label(1), do: gettext("Analyzing screenshot…")
  def analysis_label(count), do: gettext("Analyzing %{count} screenshots…", count: count)

  defp ensure_unique_id(screenshot, existing_screenshots, accepted_screenshots) do
    used_ids =
      (existing_screenshots ++ accepted_screenshots)
      |> MapSet.new(fn screenshot -> screenshot.id end)

    if MapSet.member?(used_ids, screenshot.id) do
      %{screenshot | id: "#{screenshot.id}-#{System.unique_integer([:positive])}"}
    else
      screenshot
    end
  end

  defp add_error(errors, message) do
    if message in errors, do: errors, else: [message | errors]
  end
end
