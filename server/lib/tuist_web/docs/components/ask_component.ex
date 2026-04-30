defmodule TuistWeb.Docs.AskComponent do
  @moduledoc false
  use TuistWeb, :live_component
  use Noora

  alias Tuist.Docs.AskAgent

  @slash_commands [
    %{
      name: "/new",
      description: "Start a new conversation."
    }
  ]

  @rate_limit_scale_ms to_timeout(minute: 1)
  @rate_limit_per_minute 10

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       messages: [],
       pending_input: "",
       streaming?: false,
       agent_pid: nil,
       hydrated?: false,
       slash_open?: false,
       slash_filter: "",
       remote_ip: nil
     )}
  end

  @impl true
  def update(%{stream_event: event}, socket) do
    {:ok, apply_stream_event(socket, event)}
  end

  def update(assigns, socket) do
    socket = assign(socket, assigns)

    socket =
      if connected?(socket) and is_nil(socket.assigns.agent_pid) do
        case AskAgent.start_session() do
          {:ok, pid} -> assign(socket, :agent_pid, pid)
          {:error, _} -> assign(socket, :agent_pid, nil)
        end
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("hydrate", %{"messages" => messages}, socket) when is_list(messages) do
    sanitised = Enum.flat_map(messages, &sanitise_message/1)
    {:noreply, assign(socket, messages: sanitised, hydrated?: true)}
  end

  def handle_event("hydrate", _params, socket), do: {:noreply, assign(socket, :hydrated?, true)}

  def handle_event("input-change", %{"prompt" => value}, socket) do
    trimmed = String.trim_leading(value)
    show_slash? = String.starts_with?(trimmed, "/")
    filter = if show_slash?, do: String.trim_leading(trimmed, "/"), else: ""

    {:noreply,
     assign(socket,
       pending_input: value,
       slash_open?: show_slash?,
       slash_filter: filter
     )}
  end

  def handle_event("slash-select", %{"command" => command}, socket) do
    {:noreply,
     assign(socket,
       pending_input: command,
       slash_open?: false,
       slash_filter: ""
     )}
  end

  def handle_event("ask", %{"prompt" => prompt}, socket) when is_binary(prompt) do
    prompt = String.trim(prompt)

    cond do
      prompt == "" ->
        {:noreply, socket}

      prompt == "/new" ->
        socket
        |> reset_conversation()
        |> then(&{:noreply, &1})

      socket.assigns.streaming? ->
        {:noreply, socket}

      true ->
        case rate_limit_check(socket) do
          :ok ->
            socket = ensure_live_agent(socket)

            if is_nil(socket.assigns.agent_pid) do
              {:noreply, replace_trailing_with_error(append_user_msg(socket, prompt))}
            else
              start_streaming(socket, prompt)
            end

          {:rate_limited, retry_in_seconds} ->
            socket =
              socket
              |> append_user_msg(prompt)
              |> update(:messages, fn messages ->
                messages ++
                  [
                    %{
                      role: :assistant,
                      content:
                        dgettext(
                          "docs",
                          "You're sending questions too quickly. Try again in %{seconds}s.",
                          seconds: retry_in_seconds
                        ),
                      status: :error
                    }
                  ]
              end)
              |> assign(pending_input: "", slash_open?: false, slash_filter: "")

            {:noreply, socket}
        end
    end
  end

  def handle_event("clear", _params, socket) do
    {:noreply, reset_conversation(socket)}
  end

  defp rate_limit_check(socket) do
    key =
      case socket.assigns.remote_ip do
        ip when is_binary(ip) and ip != "" -> "docs-ask:ip:#{ip}"
        _ -> "docs-ask:component:#{socket.assigns.id}"
      end

    case TuistWeb.RateLimit.InMemory.hit(key, @rate_limit_scale_ms, @rate_limit_per_minute) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:rate_limited, div(@rate_limit_scale_ms, 1_000)}
    end
  end

  defp start_streaming(socket, prompt) do
    socket = append_user_msg(socket, prompt)
    socket = update(socket, :messages, &(&1 ++ [%{role: :assistant, content: "", status: :thinking}]))

    socket =
      assign(socket,
        streaming?: true,
        pending_input: "",
        slash_open?: false,
        slash_filter: ""
      )

    parent_pid = self()
    component_id = socket.assigns.id
    agent_pid = socket.assigns.agent_pid

    Task.start(fn ->
      try do
        agent_pid
        |> Condukt.stream(prompt)
        |> Enum.each(fn event ->
          Phoenix.LiveView.send_update(parent_pid, __MODULE__,
            id: component_id,
            stream_event: event
          )
        end)

        Phoenix.LiveView.send_update(parent_pid, __MODULE__,
          id: component_id,
          stream_event: :stream_finished
        )
      catch
        kind, reason ->
          Phoenix.LiveView.send_update(parent_pid, __MODULE__,
            id: component_id,
            stream_event: {:error, {kind, reason}}
          )
      end
    end)

    {:noreply, socket}
  end

  defp reset_conversation(socket) do
    clear_agent_history(socket.assigns.agent_pid)

    socket
    |> assign(
      messages: [],
      pending_input: "",
      slash_open?: false,
      slash_filter: "",
      streaming?: false
    )
    |> push_event("docs-ask:clear", %{})
  end

  defp clear_agent_history(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      try do
        Condukt.clear(pid)
      catch
        _, _ -> :ok
      end
    end
  end

  defp clear_agent_history(_), do: :ok

  defp append_user_msg(socket, prompt) do
    update(socket, :messages, &(&1 ++ [%{role: :user, content: prompt, status: :complete}]))
  end

  defp ensure_live_agent(socket) do
    pid = socket.assigns.agent_pid

    if is_pid(pid) and Process.alive?(pid) do
      socket
    else
      case AskAgent.start_session() do
        {:ok, new_pid} -> assign(socket, :agent_pid, new_pid)
        {:error, _} -> assign(socket, :agent_pid, nil)
      end
    end
  end

  defp apply_stream_event(socket, {:text, chunk}) when is_binary(chunk) do
    update_trailing_message(socket, fn msg ->
      %{msg | content: msg.content <> chunk, status: :streaming}
    end)
  end

  defp apply_stream_event(socket, {:tool_call, _name, _id, _args}) do
    update_trailing_message(socket, fn msg ->
      if msg.content == "", do: %{msg | status: :thinking}, else: msg
    end)
  end

  defp apply_stream_event(socket, {:tool_result, _id, _result}), do: socket

  defp apply_stream_event(socket, :done) do
    socket
    |> finalise_trailing_message()
    |> push_save_event()
  end

  defp apply_stream_event(socket, :stream_finished) do
    socket
    |> assign(:streaming?, false)
    |> finalise_trailing_message()
    |> push_save_event()
  end

  defp apply_stream_event(socket, {:error, _}) do
    socket
    |> assign(:streaming?, false)
    |> replace_trailing_with_error()
  end

  defp apply_stream_event(socket, _), do: socket

  defp update_trailing_message(socket, fun) do
    update(socket, :messages, fn messages ->
      case List.pop_at(messages, -1) do
        {nil, _} -> messages
        {last, rest} -> rest ++ [fun.(last)]
      end
    end)
  end

  defp finalise_trailing_message(socket) do
    update_trailing_message(socket, fn msg -> %{msg | status: :complete} end)
  end

  defp replace_trailing_with_error(socket) do
    update_trailing_message(socket, fn _msg ->
      %{
        role: :assistant,
        content: dgettext("docs", "Something went wrong. Please try again."),
        status: :error
      }
    end)
  end

  defp push_save_event(socket) do
    push_event(socket, "docs-ask:save", %{messages: serialise_messages(socket.assigns.messages)})
  end

  defp sanitise_message(%{"role" => role, "content" => content}) when is_binary(content) do
    case role do
      "user" -> [%{role: :user, content: content, status: :complete}]
      "assistant" -> [%{role: :assistant, content: content, status: :complete}]
      _ -> []
    end
  end

  defp sanitise_message(_), do: []

  defp serialise_messages(messages) do
    Enum.map(messages, fn %{role: role, content: content} ->
      %{role: Atom.to_string(role), content: content}
    end)
  end

  @mdex_options [
    extension: [
      strikethrough: true,
      table: true,
      autolink: true,
      tasklist: true
    ],
    parse: [smart: false, relaxed_autolinks: true],
    render: [unsafe: false],
    syntax_highlight: [formatter: {:html_inline, theme: "github_light"}]
  ]

  defp render_markdown(""), do: ""

  defp render_markdown(content) when is_binary(content) do
    case MDEx.to_html(content, @mdex_options) do
      {:ok, html} -> HtmlSanitizeEx.html5(html)
      _ -> content |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
    end
  end

  defp filtered_slash_commands(filter) do
    if filter == "" do
      @slash_commands
    else
      Enum.filter(@slash_commands, fn cmd ->
        String.contains?(String.downcase(cmd.name), String.downcase(filter))
      end)
    end
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :slash_options, filtered_slash_commands(assigns.slash_filter))

    ~H"""
    <div id={@id} data-part="ask-panel" phx-hook="DocsAskPersist" phx-target={@myself}>
      <div :if={@messages == []} data-part="ask-empty">
        <p data-part="ask-empty-title">{dgettext("docs", "Ask the docs")}</p>
        <p data-part="ask-empty-hint">
          {dgettext(
            "docs",
            "Conversational answers grounded in the Tuist docs and source. Type / for commands."
          )}
        </p>
      </div>

      <ol :if={@messages != []} data-part="ask-messages">
        <li
          :for={{message, index} <- Enum.with_index(@messages)}
          data-part="ask-message"
          data-role={Atom.to_string(message.role)}
          data-status={Atom.to_string(message.status)}
          id={"#{@id}-message-#{index}"}
        >
          <div
            :if={message.role == :assistant && message.status == :thinking}
            data-part="ask-indicator"
          >
            <span data-part="ask-indicator-dot"></span>
            {dgettext("docs", "Searching the docs…")}
          </div>
          <div :if={message.role == :user && message.content != ""} data-part="ask-user-bubble">
            {message.content}
          </div>
          <div
            :if={message.role == :assistant && message.content != ""}
            data-part="ask-assistant-content"
            data-prose
          >
            {Phoenix.HTML.raw(render_markdown(message.content))}
          </div>
        </li>
      </ol>

      <form
        phx-change="input-change"
        phx-submit="ask"
        phx-target={@myself}
        data-part="ask-form"
      >
        <div data-part="ask-form-row">
          <div data-part="ask-form-input">
            <.text_input
              id="docs-ask-input"
              name="prompt"
              type="basic"
              value={@pending_input}
              placeholder={dgettext("docs", "Ask anything about Tuist…")}
              disabled={@streaming?}
              phx-debounce="50"
            />
            <div :if={@slash_open? && @slash_options != []} data-part="ask-slash-menu">
              <button
                :for={cmd <- @slash_options}
                type="button"
                data-part="ask-slash-item"
                phx-click="slash-select"
                phx-target={@myself}
                phx-value-command={cmd.name}
              >
                <span data-part="ask-slash-name">{cmd.name}</span>
                <span data-part="ask-slash-description">{cmd.description}</span>
              </button>
            </div>
          </div>
          <div data-part="ask-form-actions">
            <.button
              :if={@messages != []}
              type="button"
              variant="secondary"
              size="large"
              label={dgettext("docs", "New")}
              phx-click="clear"
              phx-target={@myself}
              disabled={@streaming?}
            />
            <.button
              type="submit"
              variant="primary"
              size="large"
              label={dgettext("docs", "Ask")}
              disabled={@streaming?}
            />
          </div>
        </div>
      </form>
    </div>
    """
  end
end
