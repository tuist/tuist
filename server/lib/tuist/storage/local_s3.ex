defmodule Tuist.Storage.LocalS3 do
  @moduledoc """
  Provides the local storage directory paths for S3-compatible storage in development.
  """

  @project_root [__DIR__, "..", "..", ".."] |> Path.join() |> Path.expand()
  @base_dir Path.join([@project_root, "tmp", "local_s3_storage"])

  @doc """
  Get the base storage directory path.
  """
  def storage_directory do
    @base_dir
  end

  @doc """
  Get the directory for multipart uploads in progress.
  """
  def uploads_directory do
    Path.join(@base_dir, "uploads")
  end

  @doc """
  Get the directory for completed objects.
  """
  def completed_directory do
    Path.join(@base_dir, "completed")
  end
end
