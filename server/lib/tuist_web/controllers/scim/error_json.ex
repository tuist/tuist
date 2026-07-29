defmodule TuistWeb.SCIM.ErrorJSON do
  @moduledoc """
  Renders Phoenix error responses as SCIM 2.0 Error resources.
  """

  alias Plug.Parsers
  alias Tuist.SCIM.Resource

  def render(_template, %{status: status} = assigns) when is_integer(status) do
    {detail, scim_type} = error_detail(status, Map.get(assigns, :reason))

    status
    |> Resource.render_error(detail, scim_type)
    |> JSON.encode!()
  end

  defp error_detail(400, %Parsers.ParseError{}), do: {"Invalid JSON payload", "invalidSyntax"}
  defp error_detail(400, %Parsers.BadEncodingError{}), do: {"Invalid JSON payload", "invalidSyntax"}
  defp error_detail(404, _reason), do: {"SCIM endpoint not found", nil}
  defp error_detail(status, _reason), do: {Plug.Conn.Status.reason_phrase(status), nil}
end
