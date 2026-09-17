defmodule AtlasWeb.ContractTemplateDownloadController do
  @moduledoc """
  Serves a contract `.docx` template to anyone presenting a valid short-lived
  signed token. The token is the auth: the external MCP client (Claude Code on
  the user's laptop) has no Atlas session cookie, so we cannot use
  `DocumentDownloadController`'s session+presigned-S3 pattern here.
  """

  use AtlasWeb, :controller

  alias Atlas.Contracts
  alias Atlas.Contracts.Template

  def show(conn, %{"template_set" => set, "filename" => filename} = params) do
    with {:ok, token} <- fetch_token(params),
         {:ok, %{"template_set" => ^set, "filename" => ^filename}} <-
           Contracts.verify_download_token(token),
         {:ok, %Template{} = template} <- Contracts.fetch_template(set, filename) do
      conn
      |> put_resp_content_type(Contracts.docx_content_type())
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
      |> send_file(200, Contracts.template_path(template))
    else
      {:error, :expired} ->
        send_resp(
          conn,
          410,
          "This download link has expired. Ask the connected agent to call get_contract_template again."
        )

      _other ->
        send_resp(conn, 404, "Not Found")
    end
  end

  defp fetch_token(%{"token" => token}) when is_binary(token) and token != "", do: {:ok, token}
  defp fetch_token(_params), do: :error
end
