defmodule CacheWeb.CacheFallbackController do
  @moduledoc """
  Translates controller action results into JSON responses.

  This module is used as the `action_fallback` for controllers that need
  standardized JSON error responses.
  """

  use CacheWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> json(%{message: "Artifact not found"})
  end

  def call(conn, {:error, :too_large}) do
    conn
    |> put_status(:request_entity_too_large)
    |> json(%{message: "Request body exceeded allowed size"})
  end

  def call(conn, {:error, :part_too_large}) do
    conn
    |> put_status(:request_entity_too_large)
    |> json(%{message: "Part exceeds 10MB limit"})
  end

  def call(conn, {:error, :total_size_exceeded}) do
    conn
    |> put_status(:unprocessable_entity)
    |> json(%{message: "Total upload size exceeds 500MB limit"})
  end

  def call(conn, {:error, :parts_mismatch}) do
    conn
    |> put_status(:bad_request)
    |> json(%{message: "Parts mismatch or missing parts"})
  end

  def call(conn, {:error, :timeout}) do
    conn
    |> put_status(:request_timeout)
    |> json(%{message: "Request body read timed out"})
  end

  def call(conn, {:error, :persist_error}) do
    conn
    |> put_status(:internal_server_error)
    |> json(%{message: "Failed to persist artifact"})
  end
end
