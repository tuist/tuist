defmodule TuistWeb.PreviewsController do
  use TuistWeb, :controller

  def download(_conn, %{
        "id" => _preview_id
      }) do
    raise TuistWeb.Errors.NotFoundError,
          gettext(
            "To run a Tuist Share link, use the CLI `tuist run` command instead. Opening a share link via a browser is not implemented, yet."
          )
  end
end
