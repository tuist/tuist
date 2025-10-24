defmodule Cache.Storage do
  @moduledoc """
  Handles S3 storage operations for CAS objects.
  """

  alias ExAws.S3

  def get_object(key, account_handle, project_handle) do
    object_key = build_object_key(account_handle, project_handle, key)
    
    bucket()
    |> S3.get_object(object_key)
    |> ExAws.request()
    |> case do
      {:ok, %{body: body, headers: headers}} ->
        {:ok, body, headers}
      
      {:error, {:http_error, 404, _}} ->
        {:error, :not_found}
      
      error ->
        error
    end
  end

  def put_object(key, account_handle, project_handle, body, opts \\ []) do
    object_key = build_object_key(account_handle, project_handle, key)
    content_type = Keyword.get(opts, :content_type, "application/octet-stream")
    
    bucket()
    |> S3.put_object(object_key, body, content_type: content_type)
    |> ExAws.request()
    |> case do
      {:ok, _} -> :ok
      error -> error
    end
  end

  def object_exists?(key, account_handle, project_handle) do
    object_key = build_object_key(account_handle, project_handle, key)
    
    bucket()
    |> S3.head_object(object_key)
    |> ExAws.request()
    |> case do
      {:ok, _} -> true
      {:error, {:http_error, 404, _}} -> false
      _ -> false
    end
  end

  defp build_object_key(account_handle, project_handle, key) do
    "#{account_handle}/#{project_handle}/cas/#{key}"
  end

  defp bucket do
    bucket_name = Application.get_env(:cache, :s3_bucket)
    if is_nil(bucket_name) do
      raise "S3 bucket not configured. Please set TUIST_S3_BUCKET_NAME environment variable."
    end
    bucket_name
  end
end