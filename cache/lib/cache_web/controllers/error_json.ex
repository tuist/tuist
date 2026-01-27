defmodule CacheWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  Returns errors in the format expected by the CLI's OpenAPI client:
  `%{message: "..."}` to match `CacheWeb.API.Schemas.Error`.
  """

  def render(template, _assigns) do
    %{message: Phoenix.Controller.status_message_from_template(template)}
  end
end
