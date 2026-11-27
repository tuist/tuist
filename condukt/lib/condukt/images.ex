defmodule Condukt.Images do
  @moduledoc """
  Opt-in preparation of images before they enter conversation history.

  Configure `:image_policy` on a session (or under `config :condukt`) with
  `:prepare`, an MFA, and positive integer limits: `:max_width`, `:max_height`,
  `:max_base64_bytes`, `:max_input_bytes`, `:max_pixels`, `:max_images`,
  `:max_total_base64_bytes` and `:timeout` (milliseconds).

  The MFA receives decoded bytes, the policy, then its extra arguments. The
  policy includes the sniffed `:media_type`. The callback must fully decode
  pixels, enforce `:max_pixels` before large allocations, orient the image,
  and fit it without cropping or upscaling. It returns
  `{:ok, bytes, mime, %{width: w, height: h}}` or `{:error, reason}`. Only PNG,
  JPEG, GIF and WebP are accepted. Condukt checks output budgets and signature,
  not pixel correctness. Hosts can use Image/Vix without imposing native
  dependencies on text-only consumers. A timeout cannot cancel native work
  already in progress.

  Failures omit an image with a fixed note, never the callback's raw error.
  Prepared input attachments carry a `"condukt.image"` receipt with dimensions
  and a digest. History preflight checks that receipt and current limits
  without decoding or fitting committed images again. Old attachments without
  receipts require explicit host repair when enabling a policy.

  Without a policy, attachment and tool-result behavior is unchanged. Tool
  images keep their JSON-text transport; this module does not introduce
  multimodal tool results or interpret images hidden inside strings.
  """

  alias Condukt.Message

  @limits ~w(max_width max_height max_base64_bytes max_input_bytes max_pixels max_images max_total_base64_bytes timeout)a
  @omitted "[Image omitted: it could not be prepared within the configured image limits.]"
  @receipt "condukt.image"

  @doc false
  def normalize(nil), do: {:ok, nil}

  def normalize(opts) when is_map(opts), do: normalize(Map.to_list(opts))

  def normalize(opts) when is_list(opts) do
    with true <- Keyword.keyword?(opts),
         true <- Enum.sort(Keyword.keys(opts)) == Enum.sort([:prepare | @limits]),
         true <- Enum.all?(@limits, &(is_integer(opts[&1]) and opts[&1] > 0)),
         {module, function, args} when is_atom(module) and is_atom(function) and is_list(args) <- opts[:prepare],
         true <- Code.ensure_loaded?(module) and function_exported?(module, function, 2 + length(args)) do
      {:ok, Map.new(opts)}
    else
      _ -> {:error, :invalid_image_policy}
    end
  end

  def normalize(_), do: {:error, :invalid_image_policy}

  @doc false
  def input(prompt, images, policy, history \\ [])

  def input(prompt, images, nil, _history), do: {prompt, images}

  def input(prompt, images, policy, history) when is_list(images) do
    existing = Enum.flat_map(history, & &1.images)

    policy = %{
      policy
      | max_images: max(policy.max_images - length(existing), 0),
        max_total_base64_bytes:
          max(policy.max_total_base64_bytes - Enum.reduce(existing, 0, &(byte_size(&1.data) + &2)), 0)
    }

    {prepared, notes, _bytes} =
      images
      |> Enum.take(policy.max_images + 1)
      |> Enum.with_index()
      |> Enum.reduce({[], [], 0}, fn {image, index}, {accepted, notes, bytes} ->
        result = if index < policy.max_images, do: prepare(image, policy), else: :omitted

        case result do
          {:ok, fitted, note} when bytes + byte_size(fitted.data) <= policy.max_total_base64_bytes ->
            {[fitted | accepted], [note | notes], bytes + byte_size(fitted.data)}

          _ ->
            {accepted, [@omitted | notes], bytes}
        end
      end)

    {append_notes(prompt, Enum.reverse(notes)), Enum.reverse(prepared)}
  end

  def input(prompt, _images, _policy, _history), do: {append_notes(prompt, [@omitted]), []}

  @doc false
  def tool_result(content, nil), do: content

  def tool_result(%{type: :image} = image, policy) do
    case prepare(image, policy) do
      {:ok, fitted, nil} -> fitted
      {:ok, fitted, note} -> Map.put(fitted, :note, note)
      :omitted -> @omitted
    end
  end

  def tool_result(content, _policy), do: content

  @doc false
  def mcp_content(parts, nil), do: parts

  def mcp_content(parts, policy) do
    {content, _budget} = Enum.map_reduce(parts, {0, 0}, &mcp_part(&1, &2, policy))
    List.flatten(content)
  end

  defp mcp_part(%{"type" => "image"} = part, {count, bytes}, policy) do
    image = %{media_type: part["mimeType"], data: part["data"]}
    result = if count < policy.max_images, do: prepare(image, policy), else: :omitted

    case result do
      {:ok, fitted, note} when bytes + byte_size(fitted.data) <= policy.max_total_base64_bytes ->
        prepared = Map.merge(part, %{"mimeType" => fitted.media_type, "data" => fitted.data})
        content = if note, do: [prepared, %{"type" => "text", "text" => note}], else: [prepared]
        {content, {count + 1, bytes + byte_size(fitted.data)}}

      _ ->
        notes = if count <= policy.max_images, do: [%{"type" => "text", "text" => @omitted}], else: []
        {notes, {count + 1, bytes}}
    end
  end

  defp mcp_part(part, budget, _policy), do: {[part], budget}

  @doc false
  def preflight(_messages, nil), do: :ok

  def preflight(messages, policy) do
    images = Enum.flat_map(messages, fn %Message{images: images} -> images end)

    if length(images) <= policy.max_images and Enum.all?(images, &committed?(&1, policy)) and
         Enum.reduce(images, 0, &(byte_size(&1.data) + &2)) <= policy.max_total_base64_bytes do
      :ok
    else
      {:error, :image_history_requires_repair}
    end
  end

  defp prepare(%{data: data} = image, policy) when is_binary(data) do
    with true <- byte_size(data) <= 4 * div(policy.max_input_bytes + 2, 3),
         {:ok, bytes} <- Base.decode64(data),
         true <- byte_size(bytes) > 0 and byte_size(bytes) <= policy.max_input_bytes,
         mime when not is_nil(mime) <- mime(bytes),
         {:ok, fitted, fitted_mime, %{width: width, height: height}} <- invoke(bytes, mime, policy),
         true <- is_binary(fitted) and byte_size(fitted) > 0,
         true <- mime(fitted) == fitted_mime and not is_nil(fitted_mime),
         true <- dimensions?(width, height, policy),
         true <- 4 * div(byte_size(fitted) + 2, 3) <= min(policy.max_base64_bytes, policy.max_total_base64_bytes) do
      data = Base.encode64(fitted)
      receipt = %{"width" => width, "height" => height, "digest" => digest(data, fitted_mime)}
      fitted_image = Map.merge(image, %{@receipt => receipt, :media_type => fitted_mime, :data => data})

      note =
        if fitted != bytes or fitted_mime != image[:media_type] do
          "[Image prepared as #{width}x#{height} #{fitted_mime}; coordinates refer to the prepared image.]"
        end

      {:ok, fitted_image, note}
    else
      _ -> :omitted
    end
  end

  defp prepare(_image, _policy), do: :omitted

  defp invoke(bytes, mime, policy) do
    {module, function, args} = policy.prepare
    {:ok, supervisor} = Task.Supervisor.start_link()

    try do
      task =
        Task.Supervisor.async_nolink(supervisor, fn ->
          apply(module, function, [bytes, Map.put(policy, :media_type, mime) | args])
        end)

      case Task.yield(task, policy.timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        _ -> {:error, :preparation_failed}
      end
    after
      Supervisor.stop(supervisor)
    end
  end

  defp committed?(%{@receipt => receipt, :data => data, :media_type => mime}, policy) when is_binary(data) do
    case receipt do
      %{"width" => width, "height" => height, "digest" => digest} ->
        dimensions?(width, height, policy) and byte_size(data) <= policy.max_base64_bytes and
          is_binary(mime) and digest == digest(data, mime)

      _ ->
        false
    end
  end

  defp committed?(_image, _policy), do: false

  defp dimensions?(width, height, policy) do
    is_integer(width) and is_integer(height) and width > 0 and height > 0 and
      width <= policy.max_width and height <= policy.max_height and width * height <= policy.max_pixels
  end

  defp digest(data, mime), do: :sha256 |> :crypto.hash([mime, 0, data]) |> Base.encode64()

  defp append_notes(text, notes) do
    notes
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> case do
      [] -> text
      notes -> Enum.join([text | notes], "\n\n")
    end
  end

  defp mime(<<137, "PNG\r\n", 26, "\n", _::binary>>), do: "image/png"
  defp mime(<<255, 216, 255, _::binary>>), do: "image/jpeg"
  defp mime(<<"GIF8", version, "a", _::binary>>) when version in [?7, ?9], do: "image/gif"
  defp mime(<<"RIFF", _::binary-size(4), "WEBP", _::binary>>), do: "image/webp"
  defp mime(_), do: nil
end
