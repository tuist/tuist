defmodule AtlasWeb.ErrorsLive.Event do
  @moduledoc """
  Detail page for a single event captured under an issue. Renders the
  same panels as the issue detail page (Tags, Contexts, Request,
  Breadcrumbs, Additional data, Modules, SDK, Stack trace) but scoped
  to the specific event referenced in the URL rather than the latest.
  """

  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []
  import AtlasWeb.ErrorsLive.EventPanels
  import AtlasWeb.PlatformIcon

  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Errors.CodeHighlight
  alias Atlas.Engineering.Errors.Policy

  @impl true
  def mount(%{"id" => id, "event_id" => event_id}, _session, socket) do
    user = socket.assigns[:current_user]

    with true <- Policy.authorize?(:error_issue_read, user, nil) || :unauthorized,
         {:ok, issue} <- Errors.fetch_issue(id),
         %{} = event <- Errors.fetch_event(issue.id, event_id) do
      payload = event[:payload] || %{}

      {:ok,
       socket
       |> assign(:issue, issue)
       |> assign(:event, event)
       |> assign(:payload, payload)
       |> assign(
         :page_title,
         gettext("Event %{short}", short: short_id(event[:event_id] || event_id))
       )}
    else
      :unauthorized ->
        {:ok,
         socket
         |> put_flash(:error, gettext("You do not have access to errors."))
         |> push_navigate(to: ~p"/")}

      nil ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Event not found."))
         |> push_navigate(to: ~p"/engineering/errors/#{id}")}

      {:error, :not_found} ->
        {:ok,
         socket
         |> put_flash(:error, gettext("Issue not found."))
         |> push_navigate(to: ~p"/engineering/errors")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section id="error-event">
      <div data-part="header">
        <div data-part="title-group">
          <div data-part="breadcrumbs">
            <.link navigate={~p"/engineering/errors"}>{gettext("Errors")}</.link>
            <span data-part="separator">/</span>
            <.link navigate={~p"/engineering/errors/#{@issue.id}"}>
              {truncate_display(@issue.title, 60)}
            </.link>
            <span data-part="separator">/</span>
            <span>
              {gettext("Event %{short}",
                short: short_id(@event.event_id)
              )}
            </span>
          </div>
          <h1>
            <.platform_icon platform={to_string(@issue.platform)} size="medium" />
            <span>{event_headline(@event, @payload)}</span>
          </h1>
          <p data-part="event-meta-header">
            <span>{format_datetime(@event.timestamp)}</span>
            <span :if={present?(@event.environment)}>· {@event.environment}</span>
            <span :if={present?(@event.release)}>
              · {gettext("Release %{release}", release: @event.release)}
            </span>
          </p>
        </div>
      </div>

      <.card
        :if={stack_frames(@payload) != []}
        title={gettext("Stack trace")}
        icon="alert_triangle"
      >
        <.card_section>
          <div data-part="stack-frames">
            <div
              :for={frame <- stack_frames(@payload)}
              data-part="frame"
              data-in-app={to_string(frame["in_app"] == true)}
            >
              <div data-part="frame-header">
                <span
                  data-part="frame-indicator"
                  title={
                    if frame["in_app"] == true,
                      do: gettext("In-app frame"),
                      else: gettext("External frame")
                  }
                />
                <span data-part="frame-mfa">
                  <span :if={frame["module"]} data-part="frame-module">{frame["module"]}</span><span :if={
                    frame["module"] && frame["function"]
                  }>.</span><span data-part="frame-function">{frame["function"] || "?"}</span>
                </span>
                <span :if={frame["filename"]} data-part="frame-location">
                  {frame["filename"]}<span :if={frame["lineno"]}>:{frame["lineno"]}</span>
                </span>
              </div>
              <div :if={highlighted_frame(frame, @payload)} data-part="context">
                {Phoenix.HTML.raw(highlighted_frame(frame, @payload))}
              </div>
            </div>
          </div>
        </.card_section>
      </.card>

      <.card
        :if={stack_frames(@payload) == [] && latest_message(@payload)}
        title={gettext("Message")}
        icon="info_circle"
      >
        <.card_section>
          <pre data-part="message-body">{latest_message(@payload)}</pre>
        </.card_section>
      </.card>

      <.tags_card issue={@issue} payload={@payload} />
      <.contexts_card payload={@payload} />
      <.request_card payload={@payload} />
      <.breadcrumbs_card payload={@payload} />
      <.additional_data_card payload={@payload} />
      <.modules_card payload={@payload} />
      <.sdk_card payload={@payload} />
    </section>
    """
  end

  ## Local helpers

  defp event_headline(event, payload) do
    cond do
      present?(event[:exception_type]) and present?(event[:exception_value]) ->
        "#{event.exception_type}: #{event.exception_value}"

      present?(event[:exception_type]) ->
        event.exception_type

      msg = latest_message(payload) ->
        truncate_display(msg, 140)

      true ->
        gettext("Event %{short}", short: short_id(event[:event_id]))
    end
  end

  defp short_id(nil), do: "?"

  defp short_id(id) when is_binary(id) do
    id
    |> String.replace("-", "")
    |> String.slice(0, 8)
  end

  defp short_id(other), do: other |> to_string() |> short_id()

  defp stack_frames(%{"exception" => %{"values" => [%{"stacktrace" => %{"frames" => frames}} | _]}})
       when is_list(frames) do
    frames |> Enum.reverse() |> Enum.take(30)
  end

  defp stack_frames(_), do: []

  defp highlighted_frame(frame, payload) do
    platform = Map.get(payload, "platform")
    CodeHighlight.highlight_frame(frame, platform)
  end

  defp latest_message(payload) do
    case payload["message"] do
      %{"formatted" => formatted} when is_binary(formatted) and formatted != "" -> formatted
      %{"message" => message} when is_binary(message) and message != "" -> message
      msg when is_binary(msg) and msg != "" -> msg
      _ -> nil
    end
  end

  defp present?(value) when is_binary(value) and byte_size(value) > 0, do: true
  defp present?(_), do: false

  defp truncate_display(nil, _), do: ""

  defp truncate_display(text, max) when is_binary(text) do
    if String.length(text) > max, do: String.slice(text, 0, max) <> "…", else: text
  end
end
