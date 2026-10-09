defmodule TuistWeb.ProjectSitemapController do
  use TuistWeb, :controller

  alias Tuist.Environment
  alias Tuist.Projects
  alias TuistWeb.Errors.NotFoundError

  @page_size 1000
  @namespace "http://www.sitemaps.org/schemas/sitemap/0.9"

  def index(conn, _params) do
    page_count = max(1, ceil(Projects.public_projects_count() / @page_size))

    sitemaps =
      Enum.map(1..page_count, fn page ->
        ["<sitemap><loc>", escape(Environment.app_url(path: "/sitemaps/projects/#{page}.xml")), "</loc></sitemap>"]
      end)

    xml(conn, [~s(<sitemapindex xmlns="#{@namespace}">), sitemaps, "</sitemapindex>"])
  end

  def show(conn, %{"page" => page}) do
    with [_, number] <- Regex.run(~r/\A([1-9][0-9]{0,5})\.xml\z/, page),
         page_number = String.to_integer(number),
         projects when projects != [] or page_number == 1 <- Projects.public_project_handles(page_number, @page_size) do
      urls =
        Enum.map(projects, fn %{account: account, project: project} ->
          path = "/#{URI.encode(account, &URI.char_unreserved?/1)}/#{URI.encode(project, &URI.char_unreserved?/1)}"
          ["<url><loc>", escape(Environment.app_url(path: path)), "</loc></url>"]
        end)

      xml(conn, [~s(<urlset xmlns="#{@namespace}">), urls, "</urlset>"])
    else
      _ -> raise NotFoundError
    end
  end

  defp xml(conn, body) do
    conn
    |> put_resp_content_type("application/xml")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(:ok, [~s(<?xml version="1.0" encoding="UTF-8"?>), body])
  end

  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
