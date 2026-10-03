defmodule AtlasWeb.SupportChatLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Support
  alias Atlas.Support.Thread
  alias AtlasWeb.ClientIP
  alias AtlasWeb.SupportChatEmbed
  alias AtlasWeb.SupportChatRateLimit

  @token_salt "support-chat-conversation"
  @token_max_age 30 * 24 * 60 * 60

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, gettext("Support"))
     |> assign(:thread, nil)
     |> assign(:source_url, nil)
     |> assign(:parent_origin, nil)
     |> assign(:subscribed_thread_id, nil)
     |> assign(:form_error, nil)
     |> assign(:email_error, nil)
     |> assign(:retry_seconds, nil)
     |> assign(:client_ip, client_ip(socket))
     |> assign(:messages_empty?, true)
     |> assign(:form, chat_form(nil, nil))
     |> stream(:messages, [])}
  end

  def handle_params(params, _uri, socket) do
    source_url = params["source"]
    parent_origin = SupportChatEmbed.parent_origin(params["parent_origin"])
    socket = assign(socket, :parent_origin, parent_origin)

    case chat_thread(params["conversation"]) do
      {:ok, thread} ->
        {:noreply, assign_thread(socket, thread, source_url)}

      :error ->
        {:noreply,
         socket
         |> assign(:thread, nil)
         |> assign(:source_url, source_url)
         |> assign(:form_error, if(params["conversation"], do: gettext("This chat session has expired.")))
         |> assign(:email_error, nil)
         |> assign(:retry_seconds, nil)
         |> assign(:form, chat_form(nil, source_url))
         |> assign(:messages_empty?, true)
         |> stream(:messages, [], reset: true)}
    end
  end

  def handle_event("validate", %{"_target" => ["chat", "email"]}, socket) do
    {:noreply, assign(socket, :email_error, nil)}
  end

  def handle_event("validate", _params, socket), do: {:noreply, socket}

  def handle_event("send", %{"chat" => params}, socket) do
    email = params["email"]

    with :ok <- SupportChatRateLimit.check(socket.assigns.client_ip, email),
         {:ok, %{thread: thread}} <- receive_chat(socket.assigns.thread, params) do
      conversation = sign_chat_thread(thread)

      {:noreply,
       socket
       |> assign_thread(thread, socket.assigns.source_url)
       |> assign(:form_error, nil)
       |> assign(:email_error, nil)
       |> assign(:retry_seconds, nil)
       |> push_event("support-chat-composer-clear", %{})
       |> push_event("support-chat-session", %{conversation: conversation})
       |> push_patch(to: chat_path(conversation, socket.assigns.source_url, socket.assigns.parent_origin))}
    else
      {:error, retry_after} when is_integer(retry_after) ->
        {:noreply,
         socket
         |> assign(:email_error, nil)
         |> assign(:form_error, nil)
         |> assign(:retry_seconds, retry_after)}

      {:error, reason} when reason in [:email_required, :email_invalid] ->
        {:noreply,
         socket
         |> assign(:form_error, nil)
         |> assign(:retry_seconds, nil)
         |> assign(:email_error, chat_error(reason))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:email_error, nil)
         |> assign(:retry_seconds, nil)
         |> assign(:form_error, chat_error(reason))}
    end
  end

  def handle_info({:support_thread_updated, thread_id}, %{assigns: %{thread: %{id: thread_id}}} = socket) do
    case Support.get_thread(thread_id) do
      %Thread{} = thread -> {:noreply, assign_thread(socket, thread, socket.assigns.source_url)}
      nil -> {:noreply, socket}
    end
  end

  def handle_info(_message, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <div id="support-chat" data-part="support-chat">
      <header data-part="header">
        <div data-part="heading">
          <h1 data-part="title">{gettext("How can we help you?")}</h1>
          <p data-part="response-time">{gettext("Typically replies in one business day")}</p>
        </div>
        <.neutral_button
          id="support-chat-close"
          size="large"
          phx-hook=".CloseSupportChat"
          data-part="close"
          data-parent-origin={@parent_origin}
          aria-label={gettext("Close support chat")}
        >
          <.icon name="close" />
        </.neutral_button>
      </header>

      <div
        id="support-chat-session"
        data-parent-origin={@parent_origin}
        phx-hook=".SupportChatSession"
      >
      </div>
      <div
        id="support-chat-resize"
        data-parent-origin={@parent_origin}
        phx-hook=".SupportChatResize"
      >
      </div>
      <div
        id="support-chat-theme"
        data-parent-origin={@parent_origin}
        phx-hook=".SupportChatTheme"
      >
      </div>

      <section :if={@thread} data-part="conversation">
        <.alert
          :if={unverified_chat?(@thread)}
          id="support-chat-email-verification"
          type="secondary"
          status="warning"
          size="small"
          title={
            gettext(
              "Confirm your email to receive replies when you are away. Until then, replies appear only in this chat."
            )
          }
          data-part="email-verification"
        />
        <div
          id="support-chat-messages"
          phx-update="stream"
          phx-hook=".SupportChatMessages"
          data-part="message-list"
        >
          <p :if={@messages_empty?} data-part="empty-state">
            {gettext("Start the conversation below.")}
          </p>
          <article
            :for={{dom_id, message} <- @streams.messages}
            id={dom_id}
            data-part="message"
            data-kind={message.kind}
          >
            <p data-part="message-body">{message.body}</p>
            <time data-part="time">{format_time(message.occurred_at)}</time>
          </article>
        </div>
      </section>

      <.form
        id="support-chat-form"
        for={@form}
        phx-change="validate"
        phx-submit="send"
        data-part="form"
      >
        <p :if={@form_error} id="support-chat-error" data-part="form-error" role="alert">
          {@form_error}
        </p>
        <p
          :if={@retry_seconds}
          id="support-chat-retry-error"
          data-part="form-error"
          role="alert"
          phx-hook=".SupportChatRetry"
          data-seconds={@retry_seconds}
          data-template={
            gettext("Please wait %{seconds} seconds before sending another message.",
              seconds: "@seconds@"
            )
          }
        >
          {gettext("Please wait %{seconds} seconds before sending another message.",
            seconds: @retry_seconds
          )}
        </p>

        <div :if={!@thread} data-part="identity-fields">
          <.text_input
            id="support-chat-name"
            field={@form[:name]}
            type="basic"
            label={gettext("Name")}
            sublabel={gettext("(Optional)")}
            placeholder={gettext("How should we address you?")}
            show_suffix={false}
            data-part="identity-input"
          />
          <.text_input
            id="support-chat-email"
            field={@form[:email]}
            type="basic"
            label={gettext("Email")}
            placeholder="you@example.com"
            required
            error={@email_error}
            show_suffix={false}
            data-part="identity-input"
          />
        </div>

        <.text_area
          :if={!@thread}
          id="support-chat-body"
          field={@form[:body]}
          label={gettext("Message")}
          phx-hook=".SupportChatComposer"
          placeholder={gettext("Type a message")}
          resize="none"
          rows={6}
          max_length={10_000}
          required
          autofocus
          show_character_count={false}
          data-part="message-input"
        />

        <div :if={@thread} data-part="composer">
          <.text_area
            id="support-chat-composer-body"
            field={@form[:body]}
            placeholder={gettext("Type a message")}
            phx-hook=".SupportChatComposer"
            resize="none"
            rows={1}
            max_length={10_000}
            required
            autofocus
            show_character_count={false}
            data-part="composer-input"
          />
          <.button
            id="support-chat-send"
            type="submit"
            variant="primary"
            size="medium"
            icon_only
            aria-label={gettext("Send message")}
            data-part="composer-submit"
          >
            <.icon name="arrow_right" />
          </.button>
        </div>

        <input :if={@thread} type="hidden" name={@form[:name].name} value={@form[:name].value} />
        <input :if={@thread} type="hidden" name={@form[:email].name} value={@form[:email].value} />
        <input type="hidden" name={@form[:source_url].name} value={@form[:source_url].value} />

        <.button
          :if={!@thread}
          id="support-chat-submit"
          label={gettext("Send message")}
          type="submit"
          data-part="submit"
        />
      </.form>
    </div>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SupportChatRetry">
      export default {
        // Live countdown for the rate-limit notice; dismisses itself at zero.
        mounted() {
          this.start()
        },
        updated() {
          this.start()
        },
        destroyed() {
          clearInterval(this.timer)
        },
        start() {
          clearInterval(this.timer)
          this.seconds = parseInt(this.el.dataset.seconds, 10)
          this.el.hidden = false
          this.timer = setInterval(() => {
            this.seconds -= 1

            if (this.seconds <= 0) {
              clearInterval(this.timer)
              this.el.hidden = true
            } else {
              this.el.textContent = this.el.dataset.template.replaceAll("@seconds@", this.seconds)
            }
          }, 1000)
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SupportChatMessages">
      export default {
        // Marks only genuinely new messages for the send animation: the server
        // re-streams the whole list on updates, so DOM insertion alone cannot
        // distinguish a new bubble from a re-rendered one.
        mounted() {
          this.seen = new Set(this.messageIds())
          // Ids currently animating in. Sending patches the list twice in
          // quick succession (event render, then push_patch), replacing the
          // marked node with an unmarked clone — so the marker must be
          // re-applied for the animation's lifetime, not set only once.
          this.entering = new Set()
          // The scrollbar thumb only shows once overflow persists after the
          // panel's growth animation settles — while the panel can still
          // grow, transient overflow stays thumbless.
          this.syncScrollable = () => {
            clearTimeout(this.scrollableTimer)
            this.scrollableTimer = setTimeout(() => {
              if (this.el.scrollHeight > this.el.clientHeight + 1) {
                this.el.dataset.scrollable = ""
              } else {
                delete this.el.dataset.scrollable
              }
            }, 350)
          }
          this.sizeObserver = new ResizeObserver(this.syncScrollable)
          this.sizeObserver.observe(this.el)
          this.syncScrollable()
          this.scrollToBottom()
        },
        destroyed() {
          this.sizeObserver.disconnect()
          clearTimeout(this.scrollableTimer)
        },
        updated() {
          for (const el of this.el.querySelectorAll('[data-part="message"]')) {
            if (!this.seen.has(el.id)) {
              this.seen.add(el.id)
              this.entering.add(el.id)
              setTimeout(() => {
                this.entering.delete(el.id)
                // Strip the marker once the animation is over: a lingering
                // attribute would replay the spring whenever the hidden
                // panel is reopened (display: none restarts CSS animations).
                const current = document.getElementById(el.id)
                if (current) delete current.dataset.entering
              }, 400)
            }

            if (this.entering.has(el.id)) el.dataset.entering = ""
          }
          this.syncScrollable()
          this.scrollToBottom()
          // New messages change the list's content height without resizing the
          // clamped page root; nudge the resize hook to re-report.
          window.dispatchEvent(new Event("support-chat:content-changed"))
        },
        messageIds() {
          return [...this.el.querySelectorAll('[data-part="message"]')].map((el) => el.id)
        },
        scrollToBottom() {
          this.el.scrollTop = this.el.scrollHeight
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SupportChatComposer">
      export default {
        // LiveView never patches the focused input, so the composer keeps its
        // text after a successful send; clear it explicitly from the server.
        // The chat composer also grows with its content instead of offering a
        // drag handle.
        mounted() {
          this.autoGrow = () => {
            this.el.style.height = "auto"
            this.el.style.height = `${this.el.scrollHeight}px`
          }
          // The send button — icon-only in the chat, "Send message" in the
          // first-contact form — only becomes clickable once there is
          // something to send.
          this.syncSubmit = () => {
            const submit =
              document.getElementById("support-chat-send") ||
              document.getElementById("support-chat-submit")
            if (submit) submit.disabled = this.el.value.trim() === ""
          }
          this.onInput = () => {
            this.autoGrow()
            this.syncSubmit()
          }
          // Chat convention in both composers: Enter sends, Shift+Enter
          // inserts a newline.
          this.onKeydown = (event) => {
            if (event.key !== "Enter" || event.shiftKey) return

            event.preventDefault()
            if (this.el.value.trim() !== "") this.el.form.requestSubmit()
          }
          this.el.addEventListener("input", this.onInput)
          this.el.addEventListener("keydown", this.onKeydown)
          this.syncSubmit()
          this.handleEvent("support-chat-composer-clear", () => {
            this.el.value = ""
            this.autoGrow()
            this.syncSubmit()
          })
        },
        destroyed() {
          this.el.removeEventListener("input", this.onInput)
          this.el.removeEventListener("keydown", this.onKeydown)
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SupportChatTheme">
      export default {
        // Noora's dark shadow tokens only activate under :root[data-theme="dark"];
        // color tokens flip via light-dark() on the resolved color scheme. Mirror
        // the resolved scheme onto the root element so both layers agree. Inside
        // the embed iframe the media query reflects the scheme the browser
        // inherits from the embedding page.
        mounted() {
          // The embed resolves the theme on the host page and passes it along;
          // it wins over the media query, which can disagree with the host in
          // browsers without embedder color-scheme inheritance (Safari).
          this.forced = new URLSearchParams(window.location.search).get("theme")
          this.parentOrigin = this.el.dataset.parentOrigin
          this.media = window.matchMedia("(prefers-color-scheme: dark)")
          this.applyTheme = () => {
            const dark = this.forced ? this.forced === "dark" : this.media.matches
            document.documentElement.dataset.theme = dark ? "dark" : "light"
          }
          // The embed pushes theme flips into the open frame, so switching the
          // system theme re-themes the chat without a reload.
          this.onMessage = (event) => {
            if (!this.parentOrigin || event.origin !== this.parentOrigin) return
            if (event.data?.type !== "atlas-support-chat-theme") return
            if (event.data.theme !== "dark" && event.data.theme !== "light") return

            this.forced = event.data.theme
            this.applyTheme()
          }
          window.addEventListener("message", this.onMessage)
          this.applyTheme()
          this.media.addEventListener("change", this.applyTheme)
        },
        destroyed() {
          this.media.removeEventListener("change", this.applyTheme)
          window.removeEventListener("message", this.onMessage)
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SupportChatSession">
      export default {
        mounted() {
          const parentOrigin = this.el.dataset.parentOrigin

          this.handleEvent("support-chat-session", ({conversation}) => {
            if (parentOrigin && window.parent !== window) {
              window.parent.postMessage({type: "atlas-support-chat-session", conversation}, parentOrigin)
            }
          })
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".CloseSupportChat">
      export default {
        mounted() {
          const parentOrigin = this.el.dataset.parentOrigin

          this.el.addEventListener("click", () => {
            if (parentOrigin && window.parent !== window) {
              window.parent.postMessage({type: "atlas-support-chat-close"}, parentOrigin)
            }
          })
        }
      }
    </script>

    <script :type={Phoenix.LiveView.ColocatedHook} name=".SupportChatResize">
      export default {
        mounted() {
          this.root = document.getElementById("support-chat")
          this.parentOrigin = this.el.dataset.parentOrigin
          this.notify = () => this.notifyParent()
          this.resizeObserver = new ResizeObserver(this.notify)
          this.resizeObserver.observe(this.root)
          // The root is viewport-clamped, so content growing past the clamp
          // (a validation error, a taller composer) never resizes it; the form
          // is unclamped and does resize, making it the growth signal.
          const form = document.getElementById("support-chat-form")
          if (form) this.resizeObserver.observe(form)
          window.addEventListener("support-chat:content-changed", this.notify)
          this.notifyParent()
        },
        updated() {
          this.notifyParent()
        },
        destroyed() {
          this.resizeObserver.disconnect()
          window.removeEventListener("support-chat:content-changed", this.notify)
        },
        notifyParent() {
          if (!this.parentOrigin || window.parent === window) return

          // The root is clamped to the iframe viewport, so its own height can
          // never ask the embed for more room. Report the desired height: the
          // clamped height plus whatever overflows it — the message list's
          // internal scroll, and any unclamped content past the root's box.
          const rootHeight = Math.ceil(this.root.getBoundingClientRect().height)
          // The embed hides the iframe when the panel closes; a zero-height
          // measurement is that hidden state, not a real size.
          if (rootHeight === 0) return

          const rootOverflow = Math.max(0, this.root.scrollHeight - this.root.clientHeight)
          const list = document.getElementById("support-chat-messages")
          const listOverflow = list ? Math.max(0, list.scrollHeight - list.clientHeight) : 0
          const height = rootHeight + rootOverflow + listOverflow

          window.parent.postMessage({type: "atlas-support-chat-resize", height}, this.parentOrigin)
        }
      }
    </script>
    """
  end

  defp receive_chat(nil, params), do: Support.receive_chat(params)
  defp receive_chat(thread, params), do: Support.receive_chat(thread, params)

  defp assign_thread(socket, thread, source_url) do
    socket = subscribe_to_thread(socket, thread.id)

    messages = public_messages(thread)

    socket
    |> assign(:thread, thread)
    |> assign(:source_url, source_url)
    |> assign(:form, chat_form(thread, source_url))
    |> assign(:messages_empty?, messages == [])
    |> stream(:messages, messages, reset: true)
  end

  defp subscribe_to_thread(socket, thread_id) do
    current_thread_id = socket.assigns.subscribed_thread_id

    cond do
      !connected?(socket) ->
        socket

      current_thread_id == thread_id ->
        socket

      true ->
        if current_thread_id do
          Phoenix.PubSub.unsubscribe(Atlas.PubSub, "support:thread:#{current_thread_id}")
        end

        Phoenix.PubSub.subscribe(Atlas.PubSub, "support:thread:#{thread_id}")
        assign(socket, :subscribed_thread_id, thread_id)
    end
  end

  defp chat_thread(token) when is_binary(token) do
    with {:ok, %{"thread_id" => thread_id, "email" => email}} <-
           Phoenix.Token.verify(AtlasWeb.Endpoint, @token_salt, token, max_age: @token_max_age),
         %Thread{} = thread <- Support.get_thread(thread_id),
         true <- thread.customer_email == email,
         "chat" <- Map.get(thread.metadata, "channel") do
      {:ok, thread}
    else
      _error -> :error
    end
  end

  defp chat_thread(_token), do: :error

  defp sign_chat_thread(thread) do
    Phoenix.Token.sign(AtlasWeb.Endpoint, @token_salt, %{"thread_id" => thread.id, "email" => thread.customer_email})
  end

  defp chat_form(thread, source_url) do
    to_form(
      %{
        "name" => (thread && thread.customer_name) || "",
        "email" => (thread && thread.customer_email) || "",
        "body" => "",
        "source_url" => source_url || ""
      },
      as: :chat
    )
  end

  defp chat_path(conversation, source_url, parent_origin) do
    params =
      %{"conversation" => conversation}
      |> maybe_put("source", source_url)
      |> maybe_put("parent_origin", parent_origin)

    ~p"/support/chat?#{params}"
  end

  defp public_messages(thread), do: Enum.reject(thread.messages, &(&1.kind == "note"))

  defp unverified_chat?(thread), do: Map.get(thread.metadata || %{}, "email_verified") != true

  defp format_time(time), do: Calendar.strftime(time, "%b %-d · %-I:%M %p")

  defp client_ip(socket) do
    ClientIP.from_connect_info(%{
      x_headers: get_connect_info(socket, :x_headers),
      peer_data: get_connect_info(socket, :peer_data)
    })
  end

  defp chat_error(:email_required), do: gettext("Enter your email so we can get back to you.")
  defp chat_error(:email_invalid), do: gettext("Enter a valid email address.")
  defp chat_error(:body_required), do: gettext("Write a message before sending.")
  defp chat_error(:body_too_long), do: gettext("Messages cannot exceed 10,000 characters.")
  defp chat_error(:name_too_long), do: gettext("Your name is too long.")
  defp chat_error(:customer_mismatch), do: gettext("This chat belongs to a different email address.")
  defp chat_error(_reason), do: gettext("We could not send your message. Please try again.")

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
