defmodule Noora.Time do
  @moduledoc """
  A component to render a time.

  ## Example

  ```elixir
  <.time time={@created_at} />
  <.time time={@updated_at} show_time={true} />
  <.time time={@last_login} relative={true} />
  ```
  """
  use Phoenix.Component

  import Noora.Tooltip

  attr(:time, DateTime, required: true, doc: "The time to render.")
  attr(:show_time, :boolean, default: false, doc: "Whether to show the time or date only.")
  attr(:relative, :boolean, default: false, doc: "Whether to show the time relative to now.")

  def time(assigns) do
    format_string =
      if assigns.show_time,
        do: "{Mfull} {D}, {YYYY}, at {h12}:{m}:{s} {AM}",
        else: "{Mfull} {D}, {YYYY}"

    assigns = assign(assigns, format_string: format_string)

    ~H"""
    <div class="noora-time">
      <%= if @relative do %>
        <.tooltip id={Uniq.UUID.uuid4()} title={Timex.format!(@time, @format_string)}>
          <:trigger :let={attrs}>
            <span {attrs}>{Timex.from_now(@time)}</span>
          </:trigger>
        </.tooltip>
      <% else %>
        <time datetime={DateTime.to_iso8601(@time)}>
          {Timex.format!(@time, @format_string)}
        </time>
      <% end %>
    </div>
    """
  end
end
