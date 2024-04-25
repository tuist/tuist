defmodule TuistCloudWeb.Authentication do
  @moduledoc ~s"""
  A module that provides functions for authenticating requests.
  """
  import Plug.Conn
  import Plug.Conn

  @authenticated_user_key :authenticated_user
  @authenticated_project_key :authenticated_project

  def authenticated?(conn),
    do: authenticated_user(conn) != nil or authenticated_project(conn) != nil

  def authenticated_user(conn) do
    if Map.has_key?(conn.assigns, :current_user) do
      conn.assigns[:current_user]
    else
      conn.assigns[@authenticated_user_key]
    end
  end

  def authenticated_project(conn), do: conn.assigns[@authenticated_project_key]

  def authenticated_subject(conn) do
    case authenticated_user(conn) do
      nil -> authenticated_project(conn)
      user -> user
    end
  end

  def put_authenticated_user(conn, user) do
    assign(conn, @authenticated_user_key, user)
  end

  def put_authenticated_project(conn, project) do
    assign(conn, @authenticated_project_key, project)
  end

  def get_token(conn) do
    case conn |> get_req_header("authorization") do
      ["Bearer " <> token] -> token
      _ -> nil
    end
  end
end
