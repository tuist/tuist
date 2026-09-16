defmodule Tuist.Runners.GitLab.Cache do
  @moduledoc """
  Presigned object URLs backing GitLab's `cache:` keyword on Tuist Runners.

  GitLab Runner stores cache archives in whatever object store its runner
  configuration names. Each job runs on a fresh machine, so without a remote
  store `cache:` never outlives the job. The job's executor asks for URLs
  with its job-scoped report token and never holds storage credentials.

  The account, GitLab project and ref protection come from the signed token,
  not from the request. Protected and unprotected refs use separate
  namespaces for both reads and writes, so a pipeline on an unprotected ref
  cannot replace an archive that a protected ref restores.
  """

  alias Tuist.Accounts
  alias Tuist.Storage

  @prefix "runner-gitlab-cache"
  @max_key_bytes 512
  @key_pattern ~r/\A[^\x00-\x1f\x7f\/\\]+\z/u
  @default_expires_in 3 * 60 * 60
  @max_expires_in 12 * 60 * 60

  def prefix, do: @prefix

  @doc """
  Returns download and upload URLs for `object_name`, the path GitLab Runner
  derives for a shared cache: `project/<project_id>/<cache_key>`.
  """
  def urls(identity, object_name, opts \\ [])

  def urls(%{account_id: account_id, gitlab_project_id: project_id, ref_protected: protected?}, object_name, opts)
      when is_integer(project_id) and is_boolean(protected?) do
    with {:ok, key} <- cache_key(object_name, project_id),
         {:ok, account} <- Accounts.get_account_by_id(account_id) do
      object_key = object_key(account, project_id, protected?, key)
      expires_in = expires_in(Keyword.get(opts, :expires_in))

      download_url = Storage.generate_download_url(object_key, account, expires_in: expires_in)
      upload_url = Storage.generate_upload_url(object_key, account, expires_in: expires_in)

      if Enum.all?([download_url, upload_url], &Tuist.URL.public_host_url?/1) do
        {:ok, %{download_url: download_url, upload_url: upload_url}}
      else
        {:error, :cache_unavailable}
      end
    else
      {:error, :invalid_object_name} = error -> error
      _ -> {:error, :cache_unavailable}
    end
  end

  def urls(_identity, _object_name, _opts), do: {:error, :cache_unavailable}

  def account_prefix(%{name: account_handle}), do: "#{@prefix}/#{account_handle}/"

  def object_key(account, project_id, protected?, key) do
    account_prefix(account) <> Enum.join([project_id, namespace(protected?), key], "/")
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

  defp expires_in(seconds) when is_integer(seconds) and seconds > 0, do: min(seconds, @max_expires_in)
  defp expires_in(_seconds), do: @default_expires_in
end
