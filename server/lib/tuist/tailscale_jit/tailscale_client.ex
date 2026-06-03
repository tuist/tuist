defmodule Tuist.TailscaleJIT.TailscaleClient do
  @moduledoc """
  Tailscale Policy File API client. Two operations the bot needs:
  fetch the current ACL document with its ETag, and replace it
  using optimistic concurrency via `If-Match`. Token is OAuth
  client-credentials with `policy_file:write` scope; the bot
  caches it in `:persistent_term` until expiry.

  The 412 (Precondition Failed) retry policy lives in
  `post_acl_with_retry/3` because it composes the GET-modify-POST
  loop the caller actually wants. Callers should prefer that to
  `post_acl/3`.
  """

  alias Tuist.Environment

  @api_base "https://api.tailscale.com/api/v2"
  @token_url @api_base <> "/oauth/token"
  @token_cache_key {__MODULE__, :token}

  @retry_backoffs_ms [250, 500, 1000]

  @doc """
  Fetches the ACL as `{:ok, body_text, etag}`. `body_text` is the
  raw HuJSON document (preserved verbatim for the splice path);
  `etag` is opaque, pass it back as-is in `post_acl/3`.
  """
  def get_acl(opts \\ []) do
    tailnet = Keyword.get(opts, :tailnet, tailnet())

    with {:ok, token} <- token() do
      url = "#{@api_base}/tailnet/#{tailnet}/acl"

      url
      |> Req.get(headers: bearer(token) ++ [{"Accept", "application/hujson"}])
      |> handle_get_acl()
    end
  end

  @doc """
  Replaces the ACL with `body` if the current ETag matches `etag`.
  Returns `{:ok, new_etag}` on success or `{:error, :etag_mismatch}`
  on 412. Other failures are `{:error, reason}`.
  """
  def post_acl(body, etag, opts \\ []) when is_binary(body) and is_binary(etag) do
    tailnet = Keyword.get(opts, :tailnet, tailnet())

    with {:ok, token} <- token() do
      url = "#{@api_base}/tailnet/#{tailnet}/acl"

      headers =
        bearer(token) ++
          [
            {"Content-Type", "application/hujson"},
            {"If-Match", etag}
          ]

      url
      |> Req.post(headers: headers, body: body)
      |> handle_post_acl()
    end
  end

  @doc """
  Read-modify-write loop with bounded retry on 412. `mutate` is a
  function `(body_text -> {:ok, new_body} | {:error, reason})`
  that produces the next document from the current one. Returns
  `{:ok, :updated}` or `{:ok, :unchanged}` (when the mutation
  returns the same document and the post is therefore skipped), or
  `{:error, reason}`.
  """
  def update_acl(mutate, opts \\ []) when is_function(mutate, 1) do
    do_update_acl(mutate, opts, @retry_backoffs_ms)
  end

  defp do_update_acl(mutate, opts, backoffs) do
    with {:ok, current, etag} <- get_acl(opts),
         {:ok, next} <- mutate.(current) do
      cond do
        next == current ->
          {:ok, :unchanged}

        true ->
          case post_acl(next, etag, opts) do
            {:ok, _new_etag} ->
              {:ok, :updated}

            {:error, :etag_mismatch} ->
              case backoffs do
                [delay | rest] ->
                  Process.sleep(delay + :rand.uniform(div(delay, 4)))
                  do_update_acl(mutate, opts, rest)

                [] ->
                  {:error, :etag_mismatch_exhausted}
              end

            {:error, reason} ->
              {:error, reason}
          end
      end
    end
  end

  defp token do
    case :persistent_term.get(@token_cache_key, nil) do
      {token, expires_at} ->
        if DateTime.compare(DateTime.utc_now(), expires_at) == :lt do
          {:ok, token}
        else
          fetch_and_cache_token()
        end

      nil ->
        fetch_and_cache_token()
    end
  end

  defp fetch_and_cache_token do
    body = %{
      grant_type: "client_credentials",
      scope: "policy_file:write"
    }

    auth = Base.encode64("#{client_id()}:#{client_secret()}")

    @token_url
    |> Req.post(
      form: body,
      headers: [
        {"Authorization", "Basic #{auth}"},
        {"Accept", "application/json"}
      ]
    )
    |> handle_token_response()
  end

  defp handle_token_response({:ok, %Req.Response{status: status, body: body}}) when status in 200..299 do
    access_token = body["access_token"]
    expires_in = body["expires_in"] || 3600
    # Refresh 60s before actual expiry so an in-flight request
    # cannot use a token that expires mid-call.
    expires_at = DateTime.utc_now() |> DateTime.add(expires_in - 60, :second)
    :persistent_term.put(@token_cache_key, {access_token, expires_at})
    {:ok, access_token}
  end

  defp handle_token_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:token_request_failed, status, body}}
  end

  defp handle_token_response({:error, reason}) do
    {:error, {:token_request_error, reason}}
  end

  defp handle_get_acl({:ok, %Req.Response{status: 200, body: body, headers: headers}}) do
    body_text =
      case body do
        binary when is_binary(binary) -> binary
        other -> JSON.encode!(other)
      end

    etag = header_value(headers, "etag") || header_value(headers, "ETag")

    if is_nil(etag) do
      {:error, :missing_etag}
    else
      {:ok, body_text, etag}
    end
  end

  defp handle_get_acl({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:get_acl_failed, status, body}}
  end

  defp handle_get_acl({:error, reason}) do
    {:error, {:get_acl_error, reason}}
  end

  defp handle_post_acl({:ok, %Req.Response{status: status, headers: headers}}) when status in 200..299 do
    {:ok, header_value(headers, "etag") || header_value(headers, "ETag")}
  end

  defp handle_post_acl({:ok, %Req.Response{status: 412}}) do
    {:error, :etag_mismatch}
  end

  defp handle_post_acl({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:post_acl_failed, status, body}}
  end

  defp handle_post_acl({:error, reason}) do
    {:error, {:post_acl_error, reason}}
  end

  defp header_value(headers, name) when is_list(headers) do
    headers
    |> Enum.find(fn {k, _} -> String.downcase(k) == String.downcase(name) end)
    |> case do
      {_, v} when is_list(v) -> List.first(v)
      {_, v} -> v
      _ -> nil
    end
  end

  defp header_value(headers, name) when is_map(headers) do
    case Map.get(headers, String.downcase(name)) do
      [v | _] -> v
      v when is_binary(v) -> v
      _ -> nil
    end
  end

  defp bearer(token), do: [{"Authorization", "Bearer #{token}"}]

  defp client_id, do: Environment.tailscale_jit_client_id()
  defp client_secret, do: Environment.tailscale_jit_client_secret()
  defp tailnet, do: Environment.tailscale_jit_tailnet() || "-"
end
