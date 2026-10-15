defmodule Tuist.Origin.Client do
  @moduledoc """
  Origin app authentication and native-repository pull request comments.
  Credentials are never accepted from repository URLs or returned in errors.
  """

  alias Tuist.Environment
  alias Tuist.VCS.Comment

  @base_url "https://api.cursor.com/v1/origin"
  @scopes ["repository:pull_requests:read", "repository:pull_requests:reviews:write"]
  @installation_scopes ["repository:metadata:read" | @scopes]

  def scopes, do: @scopes

  def configured? do
    is_binary(Environment.origin_app_id()) and Environment.origin_app_id() != "" and
      is_binary(Environment.origin_app_private_key()) and
      Environment.origin_app_private_key() != ""
  end

  def app_token do
    if configured?() do
      app_id = Environment.origin_app_id()
      now = System.system_time(:second)
      key = JOSE.JWK.from_pem(Environment.origin_app_private_key())

      {_header, token} =
        key
        |> JOSE.JWT.sign(%{"alg" => "EdDSA", "kid" => app_id, "typ" => "JWT"}, %{
          "iss" => app_id,
          "aud" => "origin-apps",
          "iat" => now,
          "exp" => now + 300
        })
        |> JOSE.JWS.compact()

      {:ok, token}
    else
      {:error, :origin_not_configured}
    end
  rescue
    _ -> {:error, :invalid_origin_key}
  end

  def get_installation(installation_id) do
    with {:ok, token} <- app_token() do
      request(:get, "/app/installations/#{segment(installation_id)}", token)
    end
  end

  def installation_token(%{installation_id: installation_id, app_id: app_id}) do
    with true <- app_id == Environment.origin_app_id(),
         {:ok, token} <- app_token(),
         {:ok, %{"token" => installation_token}} <-
           request(:post, "/app/installations/#{segment(installation_id)}/access_tokens", token,
             json: %{scopes: @installation_scopes}
           ) do
      {:ok, installation_token}
    else
      false -> {:error, :origin_app_mismatch}
      {:error, _} = error -> error
      _ -> {:error, :invalid_origin_response}
    end
  end

  def list_repositories(installation) do
    with {:ok, token} <- installation_token(installation) do
      pages("/installation/repos", token, "repositories")
    end
  end

  def get_repository(installation, handle) do
    with {:ok, path} <- repository_path(handle),
         {:ok, token} <- installation_token(installation),
         {:ok, repository} <- request(:get, path, token),
         {:ok, %{"pullRequests" => pulls}} when is_list(pulls) <-
           request(:get, path <> "/pulls", token, params: [pageSize: 1]) do
      # Mirror metadata requires an extra scope. The PR read probe enforces
      # Origin's native-repository ceiling without asking for mirror access.
      {:ok, repository}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_origin_response}
    end
  end

  def get_pull_request_number(%{
        installation: installation,
        repository_full_handle: handle,
        git_ref: ref,
        git_commit_sha: sha
      }) do
    with {:ok, path} <- repository_path(handle),
         {:ok, token} <- installation_token(installation),
         {:ok, pulls} <-
           pages(path <> "/pulls", token, "pullRequests", headSha: sha, state: "open") do
      ref_number = Tuist.VCS.pull_request_number_from_git_ref(ref)
      branch = String.replace_prefix(ref, "refs/heads/", "")

      candidates =
        Enum.filter(pulls, fn pull ->
          head = pull["head"] || %{}

          String.downcase(head["sha"] || "") == String.downcase(sha) and
            if(ref_number,
              do: pull["number"] == to_string(ref_number),
              else: head["ref"] == branch
            )
        end)

      case candidates do
        [%{"number" => number}] ->
          case Integer.parse(number) do
            {number, ""} when number > 0 -> {:ok, number}
            _ -> {:error, :invalid_origin_response}
          end

        _ ->
          {:error, :not_pull_request}
      end
    end
  end

  def get_comments(%{repository_full_handle: handle, issue_id: number, installation: installation}) do
    with {:ok, path} <- repository_path(handle),
         {:ok, token} <- installation_token(installation),
         {:ok, comments} <- pages(path <> "/pulls/#{number}/comments", token, "comments") do
      {:ok,
       Enum.map(comments, fn comment ->
         %Comment{
           id: comment["id"],
           client_id: get_in(comment, ["author", "app", "id"]),
           body: comment["body"] || ""
         }
       end)}
    end
  end

  def create_comment(%{repository_full_handle: handle, issue_id: number, body: body, installation: installation}) do
    write_comment(:post, handle, "/pulls/#{number}/comments", body, installation)
  end

  def update_comment(%{repository_full_handle: handle, comment_id: id, body: body, installation: installation}) do
    write_comment(:patch, handle, "/pulls/comments/#{segment(id)}", body, installation)
  end

  defp write_comment(method, handle, suffix, body, installation) do
    if length(String.to_charlist(body)) <= 65_536 do
      with {:ok, path} <- repository_path(handle),
           {:ok, token} <- installation_token(installation) do
        request(method, path <> suffix, token, json: %{body: body})
      end
    else
      {:error, :origin_comment_too_long}
    end
  end

  def signing_keys do
    case Req.get(@base_url <> "/keys", retry: false, receive_timeout: 5_000, redirect: false) do
      {:ok, %{status: 200, body: %{"keys" => keys}}} when is_list(keys) -> {:ok, keys}
      _ -> {:error, :origin_keys_unavailable}
    end
  end

  defp pages(path, token, field, params \\ [], seen \\ MapSet.new()) do
    with {:ok, body} <- request(:get, path, token, params: [pageSize: 100] ++ params),
         values when is_list(values) <- body[field] do
      case body["nextPageToken"] do
        next when next in [nil, ""] ->
          {:ok, values}

        next when is_binary(next) ->
          if MapSet.member?(seen, next) do
            {:error, :invalid_origin_pagination}
          else
            with {:ok, rest} <-
                   pages(
                     path,
                     token,
                     field,
                     Keyword.put(params, :pageToken, next),
                     MapSet.put(seen, next)
                   ) do
              {:ok, values ++ rest}
            end
          end

        _ ->
          {:error, :invalid_origin_response}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_origin_response}
    end
  end

  defp request(method, path, token, options \\ []) do
    case Req.request(
           [
             method: method,
             url: @base_url <> path,
             auth: {:bearer, token},
             retry: false,
             redirect: false
           ] ++ options
         ) do
      {:ok, %{status: status, body: body}} when status in 200..299 -> {:ok, body}
      {:ok, %{status: status}} -> {:error, {:origin_http_error, status}}
      {:error, _} -> {:error, :origin_unavailable}
    end
  end

  defp repository_path(handle) when is_binary(handle) do
    if Regex.match?(~r/^[\w\-.]+\/[\w\-.]+$/, handle) do
      {:ok, "/repos/" <> (handle |> String.split("/") |> Enum.map_join("/", &segment/1))}
    else
      {:error, :invalid_repository_handle}
    end
  end

  defp repository_path(_), do: {:error, :invalid_repository_handle}
  defp segment(value), do: URI.encode(to_string(value), &URI.char_unreserved?/1)
end
