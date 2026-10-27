defmodule TuistOpsWeb.ErrorJSON do
  # No HTML rendering — this is a JSON-only service. Phoenix calls
  # `render/2` with the template name like "404.json"; we return a
  # minimal shape that downstream Pomerium / Slack tolerate.
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end
end
