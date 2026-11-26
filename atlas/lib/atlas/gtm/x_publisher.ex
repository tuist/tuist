defmodule Atlas.GTM.XPublisher do
  @moduledoc """
  The X API calls that publish a post: media uploads (one request for images,
  chunked with processing for GIFs and videos) and post creation.

  Errors say whether X may have acted: `{:rejected, detail}` when X answered
  with a 4xx and created nothing, `{:unknown, detail}` when the request failed
  in a way that may still have created the post.
  """

  @api "https://api.x.com/2"
  @chunk_bytes 4 * 1024 * 1024
  @max_status_checks 60

  @doc "Uploads media bytes and returns X's media id, ready to attach."
  def upload_media(token, bytes, content_type, kind)

  def upload_media(token, bytes, _content_type, "image") do
    body = %{media: Base.encode64(bytes), media_category: "tweet_image"}

    with {:ok, %{"data" => %{"id" => id}}} <- request(token, :post, "/media/upload", json: body) do
      {:ok, id}
    end
  end

  def upload_media(token, bytes, content_type, kind) do
    init = %{media_type: content_type, total_bytes: byte_size(bytes), media_category: "tweet_" <> kind}

    with {:ok, %{"data" => %{"id" => id}}} <- request(token, :post, "/media/upload/initialize", json: init),
         :ok <- append(token, id, bytes, 0),
         {:ok, body} <- request(token, :post, "/media/upload/#{id}/finalize", []),
         :ok <- await_processing(token, id, processing(body), @max_status_checks) do
      {:ok, id}
    end
  end

  @doc "Creates a post, optionally as a reply to `reply_to`, and returns its id."
  def create_post(token, text, media_ids, reply_to) do
    body =
      %{text: text}
      |> put_if(media_ids != [], :media, %{media_ids: media_ids})
      |> put_if(reply_to != nil, :reply, %{in_reply_to_tweet_id: reply_to})

    case request(token, :post, "/tweets", json: body) do
      {:ok, %{"data" => %{"id" => id}}} -> {:ok, id}
      {:ok, _body} -> {:error, {:unknown, "X did not return the new post's id."}}
      error -> error
    end
  end

  defp append(_token, _id, <<>>, _index), do: :ok

  defp append(token, id, bytes, index) do
    size = min(byte_size(bytes), @chunk_bytes)
    chunk = binary_part(bytes, 0, size)
    rest = binary_part(bytes, size, byte_size(bytes) - size)

    form = [
      segment_index: Integer.to_string(index),
      media: {chunk, filename: "chunk", content_type: "application/octet-stream"}
    ]

    with {:ok, _body} <- request(token, :post, "/media/upload/#{id}/append", form_multipart: form) do
      append(token, id, rest, index + 1)
    end
  end

  defp await_processing(_token, _id, nil, _checks), do: :ok
  defp await_processing(_token, _id, %{"state" => "succeeded"}, _checks), do: :ok

  defp await_processing(_token, _id, %{"state" => "failed"} = info, _checks),
    do: {:error, {:rejected, "X could not process the media: " <> inspect(info["error"])}}

  defp await_processing(_token, _id, _info, 0), do: {:error, {:rejected, "X took too long to process the media."}}

  defp await_processing(token, id, info, checks) do
    Process.sleep(:timer.seconds(info["check_after_secs"] || 2))

    with {:ok, body} <- request(token, :get, "/media/upload", params: [command: "STATUS", media_id: id]) do
      await_processing(token, id, processing(body) || %{"state" => "succeeded"}, checks - 1)
    end
  end

  defp processing(%{"data" => %{"processing_info" => info}}), do: info
  defp processing(_body), do: nil

  defp request(token, method, path, opts) do
    request = [method: method, url: @api <> path, auth: {:bearer, token}, retry: false, receive_timeout: 60_000]

    case Req.request(request ++ opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      # A 401 means X did not accept the token; SocialAccounts refreshes it and retries.
      {:ok, %Req.Response{status: 401, body: body}} ->
        {:error, {:http, 401, error_detail(body)}}

      {:ok, %Req.Response{status: 429}} ->
        {:error, {:rejected, "X rate limit reached."}}

      {:ok, %Req.Response{status: status, body: body}} when status in 400..499 ->
        {:error, {:rejected, error_detail(body) || "X rejected the request (HTTP #{status})."}}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unknown, "X answered HTTP #{status}."}}

      {:error, exception} ->
        {:error, {:unknown, Exception.message(exception)}}
    end
  end

  defp put_if(map, true, key, value), do: Map.put(map, key, value)
  defp put_if(map, false, _key, _value), do: map

  defp error_detail(%{"detail" => detail} = body), do: Enum.join(Enum.reject([body["title"], detail], &is_nil/1), ": ")
  defp error_detail(%{"errors" => [%{"message" => message} | _]}), do: message
  defp error_detail(_body), do: nil
end
