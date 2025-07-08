defmodule TuistWeb.ErrorJSON do
  alias TuistWeb.Errors.NotFoundError

  def render(_template, %{reason: %NotFoundError{message: message}}) do
    %{message: message}
  end

  def render(template, _assigns) do
    %{message: Phoenix.Controller.status_message_from_template(template)}
  end
end
