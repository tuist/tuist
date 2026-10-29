defmodule AtlasWeb.OrbitLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: []

  alias Atlas.Audit
  alias Atlas.CodingRepositories
  alias Atlas.Environments
  alias Atlas.Environments.Commands
  alias Atlas.Orbit
  alias Atlas.Orbit.Message
  alias AtlasWeb.Markdown

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Orbit.subscribe_list()
      Process.send_after(self(), :reconcile, 5_000)
    end

    {:ok,
     socket
     |> assign(
       page_title: "Orbit",
       thread: nil,
       active_run: nil,
       jobs: [],
       jobs_by_message: %{},
       off_page_jobs: [],
       environments: [],
       repositories: [],
       repositories_loaded: false,
       repositories_loading: false,
       repositories_error: nil,
       selecting_environment: false,
       page: 1,
       history_page: 1,
       thread_pages: 1,
       message_pages: 1,
       status: "active",
       create_id: Ecto.UUID.generate(),
       send_id: Ecto.UUID.generate(),
       send_body: nil,
       drafts: %{},
       messages_revision: nil,
       form: to_form(%{"body" => ""}, as: :message),
       repository_form: to_form(%{"repository" => "_none"}, as: :repository),
       selection_form: to_form(%{"project" => "_server"}, as: :selection)
     )
     |> stream(:threads, [])
     |> stream(:messages, [])}
  end

  def handle_params(params, _url, socket) do
    id = params["id"]
    old = socket.assigns.thread
    previous_id = old && old.id

    if connected?(socket) and previous_id != id do
      if previous_id, do: Phoenix.PubSub.unsubscribe(Atlas.PubSub, Orbit.topic(previous_id))
      if id, do: Orbit.subscribe(id)
    end

    drafts =
      if old,
        do: Map.put(socket.assigns.drafts, old.id, Map.take(socket.assigns, [:form, :send_id, :send_body])),
        else: socket.assigns.drafts

    draft =
      Map.get(drafts, id, %{form: to_form(%{"body" => ""}, as: :message), send_id: Ecto.UUID.generate(), send_body: nil})

    socket =
      socket
      |> assign(draft)
      |> assign(
        thread: nil,
        drafts: drafts,
        messages_revision: nil,
        history_page: 1,
        create_id: Ecto.UUID.generate()
      )
      |> load_threads()

    {:noreply, if(id, do: load_thread(socket, id), else: socket |> stream(:messages, [], reset: true))}
  end

  def handle_event("new", _params, socket) do
    case Orbit.create_private(socket.assigns.current_user, %{"request_id" => socket.assigns.create_id}) do
      {:ok, thread, _} -> {:noreply, push_patch(socket, to: ~p"/orbit/#{thread.id}")}
      _ -> {:noreply, put_flash(socket, :error, "Could not create a conversation. Retry keeps the same request.")}
    end
  end

  def handle_event("draft", %{"message" => params}, socket) do
    {:noreply, assign(socket, form: to_form(params, as: :message))}
  end

  def handle_event("send", %{"message" => %{"body" => body}}, %{assigns: %{thread: thread}} = socket)
      when not is_nil(thread) and not socket.assigns.selecting_environment do
    socket =
      if socket.assigns.send_body == body,
        do: socket,
        else: assign(socket, send_body: body, send_id: Ecto.UUID.generate())

    attrs = %{"body" => body, "client_id" => socket.assigns.send_id, "address_agent" => true}

    case Orbit.post_message(socket.assigns.current_user, thread, attrs) do
      {:ok, _message, _} ->
        {:noreply,
         socket
         |> assign(form: to_form(%{"body" => ""}, as: :message), send_body: nil, history_page: 1)
         |> load_threads()
         |> load_thread(thread.id)}

      _ ->
        {:noreply,
         socket
         |> assign(form: to_form(%{"body" => body}, as: :message))
         |> put_flash(:error, "Could not send. Your draft is preserved; retrying the same message is safe.")}
    end
  end

  def handle_event("select-project", %{"selection" => %{"project" => value}}, %{assigns: %{thread: thread}} = socket)
      when not is_nil(thread) do
    params =
      case String.split(value, ":") do
        [environment, project] -> %{"environment_id" => environment, "project_id" => project}
        _ -> %{"environment_id" => nil, "project_id" => nil}
      end

    {:noreply, select_environment(socket, Map.put(params, "repository", thread.repository))}
  end

  def handle_event("select-repository", %{"repository" => %{"repository" => name}}, socket) do
    {:noreply,
     select_environment(socket, %{
       "environment_id" => nil,
       "project_id" => nil,
       "repository" => if(name not in ["", "_none"], do: name)
     })}
  end

  def handle_event("refresh-repositories", _params, socket), do: {:noreply, load_repositories(socket)}

  def handle_event("refresh-environments", _params, socket), do: {:noreply, refresh(socket)}

  def handle_event("stop-run", _params, %{assigns: %{thread: thread, active_run: run}} = socket)
      when not is_nil(thread) and not is_nil(run) do
    case Orbit.cancel_run(socket.assigns.current_user, thread, run.id) do
      {:ok, _} -> {:noreply, refresh(socket)}
      _ -> {:noreply, put_flash(socket, :error, "Could not request cancellation. Refresh the response's state.")}
    end
  end

  def handle_event("stop-job", %{"id" => id, "digest" => digest}, %{assigns: %{thread: thread}} = socket)
      when not is_nil(thread) do
    case Commands.cancel(socket.assigns.current_user, thread.id, id, %{"digest" => digest}) do
      {:ok, _} -> {:noreply, refresh(socket)}
      _ -> {:noreply, put_flash(socket, :error, "Could not request cancellation. Refresh the command's actual state.")}
    end
  end

  def handle_event("thread-page", %{"direction" => direction}, socket) when direction in ~w(older newer) do
    page = socket.assigns.page + if(direction == "older", do: 1, else: -1)
    {:noreply, socket |> assign(:page, max(1, min(page, socket.assigns.thread_pages))) |> load_threads()}
  end

  def handle_event("history-page", %{"direction" => direction}, socket) when direction in ~w(older newer) do
    page = socket.assigns.history_page + if(direction == "older", do: 1, else: -1)
    {:noreply, socket |> assign(:history_page, max(1, min(page, socket.assigns.message_pages))) |> refresh()}
  end

  def handle_event("filter", %{"status" => status}, socket) when status in ~w(active archived),
    do: {:noreply, socket |> assign(status: status, page: 1) |> load_threads()}

  def handle_event(_event, _params, socket), do: {:noreply, socket}

  def handle_info(:orbit_changed, socket), do: {:noreply, socket |> load_threads() |> refresh()}
  def handle_info(:thread_changed, socket), do: {:noreply, refresh(socket)}

  def handle_info(:reconcile, socket) do
    Process.send_after(self(), :reconcile, 5_000)
    {:noreply, socket |> load_threads() |> refresh()}
  end

  def handle_async(:repositories, {:ok, {:ok, catalog}}, socket),
    do:
      {:noreply,
       assign(socket,
         repositories: catalog.repositories,
         repositories_loaded: true,
         repositories_loading: false,
         repositories_error: nil
       )}

  def handle_async(:repositories, result, socket) do
    reason =
      case result do
        {:ok, {:error, reason}} -> reason
        _ -> :github_catalog_unavailable
      end

    {:noreply,
     assign(socket,
       repositories: [],
       repositories_loaded: true,
       repositories_loading: false,
       repositories_error: CodingRepositories.error_message(reason)
     )}
  end

  def handle_async(:environment_selection, {:ok, {id, result}}, socket) do
    socket = assign(socket, selecting_environment: false)

    if socket.assigns.thread && socket.assigns.thread.id == id do
      case result do
        {:ok, _} -> {:noreply, load_thread(socket, id)}
        {:error, reason} -> {:noreply, socket |> load_thread(id) |> put_flash(:error, selection_error(reason))}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_async(:environment_selection, _result, socket),
    do:
      {:noreply,
       socket
       |> assign(selecting_environment: false)
       |> put_flash(:error, "Could not select that repository or environment. Refresh and try again.")}

  defp select_environment(%{assigns: %{thread: nil}} = socket, _params), do: socket
  defp select_environment(%{assigns: %{selecting_environment: true}} = socket, _params), do: socket

  defp select_environment(socket, params) do
    user = socket.assigns.current_user
    id = socket.assigns.thread.id

    socket
    |> assign(selecting_environment: true)
    |> start_async(:environment_selection, fn ->
      {id, Audit.with_context(%{actor: user, interface: "dashboard"}, fn -> Environments.select(user, id, params) end)}
    end)
  end

  defp selection_error(reason)
       when reason in [
              :repository_unavailable,
              :installation_unavailable,
              :github_connection_required,
              :github_catalog_unavailable
            ], do: CodingRepositories.error_message(reason)

  defp selection_error(_), do: "Could not select that project. Finish active work and refresh environments."

  defp load_repositories(socket) do
    if connected?(socket) do
      user = socket.assigns.current_user

      socket
      |> assign(repositories_loading: true)
      |> start_async(:repositories, fn ->
        Audit.with_context(%{actor: user, interface: "dashboard"}, fn -> CodingRepositories.catalog(user) end)
      end)
    else
      socket
    end
  end

  defp load_threads(socket) do
    {threads, meta} = Orbit.list_for_user(socket.assigns.current_user, socket.assigns.page, nil, socket.assigns.status)
    socket |> assign(page: meta.page, thread_pages: meta.total_pages) |> stream(:threads, threads, reset: true)
  end

  defp refresh(%{assigns: %{thread: nil}} = socket), do: socket
  defp refresh(socket), do: load_thread(socket, socket.assigns.thread.id)

  defp load_thread(socket, id) do
    user = socket.assigns.current_user

    case Orbit.fetch(user, id) do
      {:ok, thread} ->
        {messages, meta} = Orbit.list_messages(thread, socket.assigns.history_page, user)

        jobs =
          case Commands.list(user, id) do
            {:ok, %{commands: commands}} -> commands
            _ -> []
          end

        value =
          if thread.environment_id && thread.project_id,
            do: "#{thread.environment_id}:#{thread.project_id}",
            else: "_server"

        revision = {thread.id, thread.last_seq, meta.page, Enum.map(messages, &{&1.id, &1.updated_at})}
        jobs_by_message = Map.new(jobs, &{&1.message_id, &1})

        socket =
          if socket.assigns.messages_revision == revision do
            messages
            |> Enum.filter(&(socket.assigns.jobs_by_message[&1.id] != jobs_by_message[&1.id]))
            |> Enum.reduce(socket, &stream_insert(&2, :messages, &1))
          else
            stream(socket, :messages, messages, reset: true)
          end

        message_ids = MapSet.new(messages, & &1.id)

        socket
        |> assign(
          thread: thread,
          messages_revision: revision,
          page_title: thread.title,
          active_run: Orbit.active_run(thread),
          jobs: jobs,
          jobs_by_message: jobs_by_message,
          off_page_jobs: off_page_jobs(jobs, message_ids),
          environments: Environments.list(user).environments,
          history_page: meta.page,
          message_pages: meta.total_pages,
          repository_form: to_form(%{"repository" => thread.repository || "_none"}, as: :repository),
          selection_form: to_form(%{"project" => value}, as: :selection)
        )
        |> maybe_load_repositories(thread)

      _ ->
        socket
        |> assign(
          thread: nil,
          active_run: nil,
          jobs: [],
          jobs_by_message: %{},
          off_page_jobs: [],
          environments: [],
          drafts: Map.delete(socket.assigns.drafts, id),
          form: to_form(%{"body" => ""}, as: :message)
        )
        |> stream(:messages, [], reset: true)
        |> put_flash(:error, "Conversation unavailable.")
    end
  end

  defp off_page_jobs(jobs, message_ids) do
    Enum.filter(jobs, &(&1.status in ~w(queued claimed unknown) and not MapSet.member?(message_ids, &1.message_id)))
  end

  defp maybe_load_repositories(socket, %{kind: "private"}) do
    if socket.assigns.repositories_loaded or socket.assigns.repositories_loading,
      do: socket,
      else: load_repositories(socket)
  end

  defp maybe_load_repositories(socket, _thread), do: socket

  defp project_options(environments, repository) do
    [
      {"Atlas server only", "_server"}
      | for environment <- environments,
            environment.enabled,
            project <- environment.projects,
            is_nil(repository) or project["repository"] == repository do
          suffix = if environment.online, do: "", else: " · offline"
          mode = if project["coding"] == true and environment.terminal, do: " · isolated coding", else: ""
          {"#{environment.name} / #{project["name"]}#{mode}#{suffix}", "#{environment.id}:#{project["id"]}"}
        end
    ]
  end

  defp repository_options(repositories, selected) do
    names = Enum.map(repositories, & &1.full_name)
    unavailable = if selected && selected not in names, do: [{"#{selected} · not available", selected}], else: []
    [{"No GitHub repository", "_none"}] ++ unavailable ++ Enum.map(names, &{&1, &1})
  end

  defp command_status(job) do
    cond do
      job.cancel_requested and job.status in ~w(queued claimed) -> "Cancellation requested"
      job.status == "claimed" -> "Running"
      job.status == "settled" -> if(job.success, do: "Completed", else: "Failed")
      true -> String.capitalize(job.status)
    end
  end

  attr :message, :map, required: true
  attr :job, :map, default: nil

  defp tool_evidence(assigns) do
    ~H"""
    <div id={if @job, do: "job-#{@job.id}"} data-part="tool-evidence">
      <details data-part="tool-card">
        <summary>
          <.chevron_right />
          <span>{@message.tool_name}</span>
          <span data-part="evidence-status" role="status">
            {if @job,
              do: command_status(@job),
              else: String.capitalize(@message.tool_status || "pending")}
          </span>
        </summary>
        <div data-part="evidence">
          <%= if @job do %>
            <p>{@job.environment_name} / {@job.project_name}</p>
            <AtlasWeb.CodeBlock.code_block source={@job.command} language="bash" />
            <AtlasWeb.CodeBlock.code_block source={@job.output || ""} language="text" />
            <p :if={@job.status == "unknown"}>Outcome unknown. This command will not be retried.</p>
          <% else %>
            <h3>Input</h3>
            <AtlasWeb.CodeBlock.code_block source={Message.tool_input(@message)} language="json" />
            <h3>Output</h3>
            <AtlasWeb.CodeBlock.code_block source={Message.tool_output(@message)} language="text" />
          <% end %>
        </div>
      </details>
      <.neutral_button
        :if={@job && @job.status in ~w(queued claimed)}
        phx-click="stop-job"
        phx-value-id={@job.id}
        phx-value-digest={@job.digest}
        disabled={@job.cancel_requested}
        size="small"
        label={if @job.cancel_requested, do: "Requested", else: "Cancel"}
        aria-label="Cancel command"
      />
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <section id="orbit" data-part="orbit" data-conversation={to_string(@thread != nil)}>
        <header data-part="header">
          <div data-part="text">
            <h1 data-part="title">Orbit</h1>
            <p data-part="description">Work with Pip across Atlas and your code.</p>
          </div>
          <.button
            id="orbit-new"
            phx-click="new"
            label="New conversation"
            phx-disable-with="Creating…"
          >
            <:icon_left><.plus /></:icon_left>
          </.button>
        </header>
        <.card icon="message_circle" title="Conversations" data-part="orbit-card">
          <.card_section data-part="workspace">
            <aside data-part="inbox" aria-label="Conversations">
              <nav data-part="filters" aria-label="Conversation status">
                <.button_group size="small">
                  <.button_group_item
                    :for={status <- ~w(active archived)}
                    phx-click="filter"
                    phx-value-status={status}
                    data-selected={if @status == status, do: ""}
                    aria-pressed={@status == status}
                    label={String.capitalize(status)}
                  />
                </.button_group>
              </nav>
              <div id="orbit-threads" phx-update="stream" data-part="threads">
                <p id="orbit-threads-empty" data-part="stream-empty">No {@status} conversations.</p>
                <.link
                  :for={{id, thread} <- @streams.threads}
                  id={id}
                  patch={~p"/orbit/#{thread.id}"}
                  data-selected={if @thread && @thread.id == thread.id, do: "true"}
                  aria-current={if @thread && @thread.id == thread.id, do: "page"}
                  data-part="thread-row"
                >
                  <.message_circle />
                  <span data-part="thread-text">
                    <strong>{thread.title}</strong>
                    <span>
                      {String.capitalize(thread.kind)} · {Calendar.strftime(
                        thread.updated_at,
                        "%b %d, %H:%M"
                      )}
                    </span>
                  </span>
                </.link>
              </div>
              <nav :if={@thread_pages > 1} data-part="pagination" aria-label="Conversation pages">
                <.neutral_button
                  phx-click="thread-page"
                  phx-value-direction="newer"
                  disabled={@page <= 1}
                  aria-label="Newer conversations"
                >
                  <.chevron_left />
                </.neutral_button>
                <span>{@page} of {@thread_pages}</span>
                <.neutral_button
                  phx-click="thread-page"
                  phx-value-direction="older"
                  disabled={@page >= @thread_pages}
                  aria-label="Older conversations"
                >
                  <.chevron_right />
                </.neutral_button>
              </nav>
            </aside>
            <main data-part="conversation">
              <%= if @thread do %>
                <header data-part="conversation-header">
                  <.button
                    data-part="back"
                    patch={~p"/orbit"}
                    variant="secondary"
                    size="small"
                    label="Conversations"
                  >
                    <:icon_left><.chevron_left /></:icon_left>
                  </.button>
                  <div data-part="conversation-heading">
                    <h2>{@thread.title}</h2>
                    <.badge
                      label={String.capitalize(@thread.kind)}
                      color="neutral"
                      style="light-fill"
                    />
                  </div>
                </header>
                <section
                  :if={@thread.kind == "private"}
                  data-part="environment"
                  aria-label="Tool environment"
                >
                  <div data-part="repository-row">
                    <span data-part="environment-label"><.brand_github /> Repository</span>
                    <.form
                      for={@repository_form}
                      id="orbit-repository-form"
                      phx-change="select-repository"
                    >
                      <.select
                        field={@repository_form[:repository]}
                        id="orbit-repository"
                        label="Choose repository"
                        disabled={
                          @repositories_loading || @selecting_environment || @active_run != nil ||
                            @thread.status != "active"
                        }
                      >
                        <:item
                          :for={
                            {label, value} <- repository_options(@repositories, @thread.repository)
                          }
                          value={value}
                          label={label}
                        />
                      </.select>
                    </.form>
                    <.neutral_button
                      id="orbit-refresh-repositories"
                      phx-click="refresh-repositories"
                      disabled={@repositories_loading}
                      aria-label="Refresh repositories"
                      title="Refresh repositories"
                    >
                      <.reload />
                    </.neutral_button>
                    <.button
                      id="orbit-coding-settings"
                      navigate={~p"/settings/coding"}
                      label="Configure"
                      variant="secondary"
                      size="small"
                    />
                  </div>
                  <p
                    :if={@repositories_error}
                    id="orbit-repositories-error"
                    data-part="repository-note"
                    role="status"
                  >
                    {@repositories_error}
                  </p>
                  <p
                    :if={
                      @thread.repository &&
                        length(project_options(@environments, @thread.repository)) == 1
                    }
                    id="orbit-repository-unavailable"
                    data-part="repository-note"
                    role="status"
                  >
                    No enabled environment advertises this repository. Add the checkout in your environment settings; Atlas will not clone it or choose another machine.
                  </p>
                  <div data-part="environment-row">
                    <span data-part="environment-label"><.devices_code /> Tools run on</span>
                    <.form for={@selection_form} id="orbit-project-form" phx-change="select-project">
                      <.select
                        field={@selection_form[:project]}
                        id="orbit-project"
                        label="Choose environment"
                        disabled={
                          @selecting_environment || @active_run != nil || @thread.status != "active"
                        }
                      >
                        <:item
                          :for={{label, value} <- project_options(@environments, @thread.repository)}
                          value={value}
                          label={label}
                        />
                      </.select>
                    </.form>
                    <.neutral_button
                      id="orbit-refresh-environments"
                      phx-click="refresh-environments"
                      aria-label="Refresh environments"
                      title="Refresh environments"
                    >
                      <.reload />
                    </.neutral_button>
                    <.popover id="orbit-environment-help" placement="bottom-end">
                      <:trigger :let={attrs}>
                        <.neutral_button aria-label="About execution environments" {attrs}>
                          <.info_circle />
                        </.neutral_button>
                      </:trigger>
                      <div data-part="orbit-environment-help">
                        <strong>Tools run in the selected environment</strong>
                        <p>
                          Atlas keeps the conversation and AI session. Coding projects use an isolated worktree per conversation.
                        </p>
                        <p>
                          For a Mac, enable This Mac and terminal access in Atlas desktop Settings. Shell commands run as your macOS user without a folder sandbox.
                        </p>
                      </div>
                    </.popover>
                  </div>
                </section>
                <div
                  id={"orbit-timeline-#{@thread.id}-#{@history_page}"}
                  phx-hook=".Timeline"
                  data-part="timeline"
                  data-follow-latest={to_string(@history_page == 1)}
                >
                  <nav :if={@message_pages > 1} data-part="pagination" aria-label="Message pages">
                    <.button
                      id="orbit-older-messages"
                      phx-click="history-page"
                      phx-value-direction="older"
                      disabled={@history_page >= @message_pages}
                      variant="secondary"
                      size="small"
                      label="Older messages"
                    />
                    <span>Page {@history_page} of {@message_pages}</span>
                    <.button
                      phx-click="history-page"
                      phx-value-direction="newer"
                      disabled={@history_page <= 1}
                      variant="secondary"
                      size="small"
                      label="Newer messages"
                    />
                  </nav>
                  <div
                    id="orbit-messages"
                    phx-update="stream"
                    data-part="messages"
                    aria-label="Messages"
                  >
                    <div id="orbit-messages-empty" data-part="stream-empty">
                      <.message_circle />
                      <h3>
                        {if @thread.status == "active",
                          do: "What would you like to work on?",
                          else: "No messages in this conversation"}
                      </h3>
                      <p>
                        {if @thread.status == "active",
                          do:
                            "Ask Pip a question, or select a repository to investigate and change code.",
                          else: "Archived conversations are read-only."}
                      </p>
                    </div>
                    <article
                      :for={{id, message} <- @streams.messages}
                      id={id}
                      data-part="message"
                      data-kind={message.kind}
                    >
                      <%= if message.kind == "tool" do %>
                        <.avatar
                          id={"avatar-#{message.id}"}
                          name={Orbit.agent_name()}
                          color="purple"
                          size="small"
                        />
                        <div data-part="message-content">
                          <div data-part="message-heading"><strong>{Orbit.agent_name()}</strong></div>
                          <.tool_evidence message={message} job={@jobs_by_message[message.id]} />
                        </div>
                      <% else %>
                        <.avatar
                          id={"avatar-#{message.id}"}
                          name={
                            if message.kind == "agent",
                              do: Orbit.agent_name(),
                              else: message.author_name || "Atlas"
                          }
                          color={if message.kind == "agent", do: "purple", else: "azure"}
                          size="small"
                        />
                        <div data-part="message-content">
                          <div data-part="message-heading">
                            <strong>
                              {if message.kind == "agent",
                                do: Orbit.agent_name(),
                                else: message.author_name || "Atlas"}
                            </strong>
                            <time datetime={DateTime.to_iso8601(message.inserted_at)}>
                              {Calendar.strftime(message.inserted_at, "%H:%M")}
                            </time>
                          </div>
                          <Markdown.content id={"body-#{message.id}"} body={message.body || ""} />
                          <details :if={message.device_output} data-part="tool-card">
                            <summary><.chevron_right /><span>Confirmed command output</span></summary>
                            <div data-part="evidence">
                              <AtlasWeb.CodeBlock.code_block
                                source={message.device_output}
                                language="text"
                              />
                            </div>
                          </details>
                        </div>
                      <% end %>
                    </article>
                  </div>
                  <article :for={job <- @off_page_jobs} data-part="assistant-activity">
                    <.avatar
                      id={"off-page-avatar-#{job.id}"}
                      name={Orbit.agent_name()}
                      color="purple"
                      size="small"
                    />
                    <div data-part="message-content">
                      <div data-part="message-heading">
                        <strong>{Orbit.agent_name()}</strong><span>Command from another history page</span>
                      </div>
                      <.tool_evidence message={%{tool_name: "bash"}} job={job} />
                    </div>
                  </article>
                  <article
                    :if={@active_run}
                    id="orbit-activity"
                    data-part="assistant-activity"
                    role="status"
                  >
                    <.avatar
                      id="orbit-activity-avatar"
                      name={Orbit.agent_name()}
                      color="purple"
                      size="small"
                    />
                    <div data-part="message-content">
                      <div data-part="message-heading"><strong>{Orbit.agent_name()}</strong></div>
                      <div data-part="activity-actions">
                        <span>
                          <%= cond do %>
                            <% @active_run.cancel_requested_at -> %>
                              Cancellation requested
                            <% @active_run.status == "queued" -> %>
                              Waiting to respond…
                            <% true -> %>
                              Working…
                          <% end %>
                        </span>
                        <.neutral_button
                          :if={@current_user.id in [@thread.owner_id, @active_run.initiator_id]}
                          id="orbit-stop"
                          phx-click="stop-run"
                          size="small"
                          disabled={@active_run.cancel_requested_at != nil}
                          label={
                            if @active_run.cancel_requested_at,
                              do: "Requested",
                              else: "Cancel response"
                          }
                        />
                      </div>
                    </div>
                  </article>
                </div>
                <script :type={Phoenix.LiveView.ColocatedHook} name=".Timeline">
                  export default {
                    mounted() {
                      this.follow = this.el.dataset.followLatest === "true"
                      this.onScroll = () => {
                        this.follow = this.el.dataset.followLatest === "true" &&
                          this.el.scrollHeight - this.el.scrollTop - this.el.clientHeight < 48
                      }
                      this.el.addEventListener("scroll", this.onScroll)
                      this.resize = new ResizeObserver(() => {
                        if (this.follow) this.el.scrollTop = this.el.scrollHeight
                      })
                      this.resize.observe(this.el)
                      this.resize.observe(this.el.querySelector('[data-part="messages"]'))
                    },
                    destroyed() {
                      this.resize.disconnect()
                      this.el.removeEventListener("scroll", this.onScroll)
                    },
                  }
                </script>
                <footer data-part="conversation-footer">
                  <.form
                    :if={@thread.status == "active"}
                    for={@form}
                    id="orbit-composer"
                    phx-change="draft"
                    phx-submit="send"
                    data-part="composer"
                  >
                    <.text_area
                      field={@form[:body]}
                      id="orbit-body"
                      aria-label="Message Pip"
                      rows={2}
                      max_length={16000}
                      show_character_count={false}
                      resize="none"
                      required
                      placeholder="Message Pip…"
                    />
                    <div data-part="composer-actions">
                      <span>
                        {if @thread.kind == "private",
                          do: "Private conversation",
                          else: "Shared with participants"}
                      </span>
                      <.button
                        id="orbit-send"
                        type="submit"
                        size="small"
                        phx-disable-with="Sending…"
                        disabled={@selecting_environment}
                        label="Send"
                      >
                        <:icon_right><.arrow_right /></:icon_right>
                      </.button>
                    </div>
                  </.form>
                  <p :if={@thread.status != "active"} data-part="archived-note">
                    This conversation is archived.
                  </p>
                </footer>
              <% else %>
                <section id="orbit-welcome" data-part="welcome">
                  <span data-part="welcome-icon"><.message_circle /></span>
                  <h2>What would you like to work on?</h2>
                  <p>
                    Ask Pip about Atlas or work on a repository in your execution environment. Your conversation stays with you across the web and native apps.
                  </p>
                  <.button phx-click="new" label="New conversation" variant="secondary">
                    <:icon_left><.plus /></:icon_left>
                  </.button>
                </section>
              <% end %>
            </main>
          </.card_section>
        </.card>
      </section>
    </Layouts.app>
    """
  end
end
