defmodule Tuist.Runners.GitLab.Cache do
  @moduledoc """
  Object storage backing GitLab's `cache:` keyword on Tuist Runners.

  GitLab Runner stores cache archives in whatever object store its runner
  configuration names. Each job runs on a fresh machine, so without a remote
  store `cache:` never outlives the job. The job's executor downloads through
  a presigned URL and uploads in parts through presigned part URLs, asking for
  each with its job-scoped report token. It never holds storage credentials.

  The account, GitLab project and ref protection come from the signed token,
  not from the request. Protected and unprotected refs use separate
  namespaces for both reads and writes, so a pipeline on an unprotected ref
  cannot replace an archive that a protected ref restores.
  """

  alias Tuist.Accounts
  alias Tuist.Runners.Workers.AbortGitLabCacheUploadWorker
  alias Tuist.Storage

  @prefix "runner-gitlab-cache"
  @max_key_bytes 512
  @key_pattern ~r/\A[^\x00-\x1f\x7f\/\\]+\z/u
  @default_expires_in 3 * 60 * 60
  @max_expires_in 12 * 60 * 60
  @part_url_expires_in 60 * 60
  @max_parts 10_000
  @max_upload_id_bytes 1024
  @max_etag_bytes 256
  # Report tokens expire after 12 hours, so no upload can still be completing.
  @abandoned_upload_after_seconds 24 * 60 * 60

  def prefix, do: @prefix

  def account_prefix(%{name: account_handle}), do: "#{@prefix}/#{account_handle}/"

  def object_key(account, project_id, protected?, key) do
    account_prefix(account) <> Enum.join([project_id, namespace(protected?), key], "/")
  end

  @doc """
  Returns a download URL for `object_name`, the path GitLab Runner derives for
  a shared cache: `project/<project_id>/<cache_key>`.
  """
  def download_url(identity, object_name, opts \\ []) do
    with {:ok, account, object_key} <- resolve(identity, object_name) do
      expires_in = expires_in(Keyword.get(opts, :expires_in))

      object_key
      |> Storage.generate_download_url(account, expires_in: expires_in)
      |> public_url()
    end
  end

  @doc """
  Starts a multipart upload and schedules its abort, which is a no-op once the
  upload has completed. Without it, the parts of a job that stopped mid-upload
  would be stored indefinitely: object listings, and so retention, never see
  them.
  """
  def start_upload(identity, object_name) do
    with {:ok, account, object_key} <- resolve(identity, object_name),
         {:ok, upload_id} <- start(object_key, account) do
      %{account_id: account.id, object_key: object_key, upload_id: upload_id}
      |> AbortGitLabCacheUploadWorker.new(schedule_in: @abandoned_upload_after_seconds)
      |> Oban.insert!()

      {:ok, upload_id}
    end
  end

  def upload_part_url(identity, object_name, upload_id, part_number) do
    with {:ok, account, object_key} <- resolve(identity, object_name),
         :ok <- validate_upload_id(upload_id),
         :ok <- validate_part_number(part_number) do
      object_key
      |> Storage.multipart_generate_url(upload_id, part_number, account, expires_in: @part_url_expires_in)
      |> public_url()
    end
  end

  def complete_upload(identity, object_name, upload_id, parts) do
    with {:ok, account, object_key} <- resolve(identity, object_name),
         :ok <- validate_upload_id(upload_id),
         {:ok, parts} <- parse_parts(parts) do
      case Storage.multipart_complete_upload(object_key, upload_id, parts, account) do
        :ok -> :ok
        {:error, :multipart_upload_not_found} -> {:error, :upload_not_found}
        {:error, _reason} -> {:error, :storage_unavailable}
      end
    end
  end

  def abort_upload(identity, object_name, upload_id) do
    with {:ok, account, object_key} <- resolve(identity, object_name),
         :ok <- validate_upload_id(upload_id) do
      case Storage.multipart_abort(object_key, upload_id, account) do
        :ok -> :ok
        {:error, _reason} -> {:error, :storage_unavailable}
      end
    end
  end

  defp resolve(%{account_id: account_id, gitlab_project_id: project_id, ref_protected: protected?}, object_name)
       when is_integer(project_id) and is_boolean(protected?) do
    with {:ok, key} <- cache_key(object_name, project_id) do
      case Accounts.get_account_by_id(account_id) do
        {:ok, account} -> {:ok, account, object_key(account, project_id, protected?, key)}
        _ -> {:error, :cache_unavailable}
      end
    end
  end

  defp resolve(_identity, _object_name), do: {:error, :cache_unavailable}

  defp start(object_key, account) do
    case Storage.multipart_start(object_key, account) do
      {:ok, upload_id} -> {:ok, upload_id}
      {:error, _reason} -> {:error, :storage_unavailable}
    end
  end

  defp public_url(url) do
    if Tuist.URL.public_host_url?(url), do: {:ok, url}, else: {:error, :cache_unavailable}
  end

  defp namespace(true), do: "protected"
  defp namespace(false), do: "unprotected"

  defp cache_key(object_name, project_id) when is_binary(object_name) do
    expected_project = Integer.to_string(project_id)

    case String.split(object_name, "/", parts: 3) do
      ["project", ^expected_project, key] -> validate_key(key)
      _ -> {:error, :invalid_object_name}
    end
  end

  defp cache_key(_object_name, _project_id), do: {:error, :invalid_object_name}

  # GitLab rejects `/` in cache keys, so a separator here can only come from
  # a crafted request.
  defp validate_key(key) do
    if key not in [".", ".."] and byte_size(key) <= @max_key_bytes and String.valid?(key) and
         Regex.match?(@key_pattern, key) do
      {:ok, key}
    else
      {:error, :invalid_object_name}
    end
  end

  defp validate_upload_id(upload_id)
       when is_binary(upload_id) and byte_size(upload_id) > 0 and byte_size(upload_id) <= @max_upload_id_bytes, do: :ok

  defp validate_upload_id(_upload_id), do: {:error, :invalid_upload}

  defp validate_part_number(part_number) when is_integer(part_number) and part_number in 1..@max_parts, do: :ok
  defp validate_part_number(_part_number), do: {:error, :invalid_upload}

  defp parse_parts(parts) when is_list(parts) and parts != [] and length(parts) <= @max_parts do
    parsed = Enum.map(parts, &parse_part/1)
    numbers = for {number, _etag} <- parsed, do: number

    if Enum.all?(parsed) and length(Enum.uniq(numbers)) == length(parts) do
      {:ok, Enum.sort_by(parsed, &elem(&1, 0))}
    else
      {:error, :invalid_upload}
    end
  end

  defp parse_parts(_parts), do: {:error, :invalid_upload}

  defp parse_part(%{"part_number" => number, "etag" => etag})
       when is_integer(number) and number in 1..@max_parts and is_binary(etag) and etag != "" and
              byte_size(etag) <= @max_etag_bytes, do: {number, etag}

  defp parse_part(_part), do: nil

  defp expires_in(seconds) when is_integer(seconds) and seconds > 0, do: min(seconds, @max_expires_in)
  defp expires_in(_seconds), do: @default_expires_in
end
