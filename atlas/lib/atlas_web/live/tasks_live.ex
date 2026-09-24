defmodule AtlasWeb.TasksLive do
  use AtlasWeb, :live_view
  use Noora

  import AtlasWeb.CoreComponents, only: [input: 1]
  import Ecto.Query, only: [from: 2]
  import Noora.Filter

  alias Atlas.Accounts.Account
  alias Atlas.Repo
  alias Atlas.Tasks
  alias Atlas.Tasks.Task
  alias Atlas.Users
  alias Noora.Filter

  def mount(_params, _session, socket) do
    users = Users.list_users()
    accounts = account_options()

    {:ok,
     socket
     |> assign(:page_title, gettext("Tasks"))
     |> assign(:users, users)
     |> assign(:accounts, accounts)
     |> assign(:available_filters, define_filters(users, accounts))
     |> assign(:active_filters, [])
     |> assign(:query, "")
     |> assign(:uri, URI.parse("?"))
     |> assign(:search_form, search_form(""))
     |> assign(:editing_task, nil)
     |> assign(:form_reset, 0)
     |> assign(:remind_local_value, nil)
     |> assign_form(Tasks.change_task(%Task{assignee_id: socket.assigns.current_user.id}))}
  end

  def handle_params(params, uri, socket) do
    active_filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)
    query = String.trim(params["q"] || "")

    {:noreply,
     socket
     |> assign(:uri, URI.parse(uri))
     |> assign(:active_filters, active_filters)
     |> assign(:query, query)
     |> assign(:search_form, search_form(query))
     |> load_tasks()}
  end

  def handle_event("search", %{"search" => %{"query" => query}}, socket) do
    query = String.trim(query || "")
    params = current_query_params(socket)
    params = if query == "", do: Map.delete(params, "q"), else: Map.put(params, "q", query)

    {:noreply, push_patch(socket, to: ~p"/tasks?#{params}", replace: true)}
  end

  def handle_event("add_filter", %{"value" => filter_id}, socket) do
    params = Filter.Operations.add_filter_to_query(filter_id, socket, current_query_params(socket))

    {:noreply,
     socket
     |> push_patch(to: ~p"/tasks?#{params}")
     |> push_event("open-dropdown", %{id: "filter-#{filter_id}-value-dropdown"})
     |> push_event("open-popover", %{id: "filter-#{filter_id}-value-popover"})}
  end

  def handle_event("update_filter", params, socket) do
    updated_params = Filter.Operations.update_filters_in_query(params, socket, current_query_params(socket))

    {:noreply,
     socket
     |> push_patch(to: ~p"/tasks?#{updated_params}")
     |> push_event("close-dropdown", %{id: "all", all: true})
     |> push_event("close-popover", %{id: "all", all: true})}
  end

  def handle_event("new", _params, socket) do
    {:noreply, socket |> reset_form() |> push_event("open-modal", %{id: "task-modal"})}
  end

  def handle_event("edit", %{"id" => id}, socket) do
    case Tasks.get_task(id) do
      %Task{status: "open"} = task ->
        {:noreply,
         socket
         |> assign(:editing_task, task)
         |> assign(:remind_local_value, task.remind_at && DateTime.to_iso8601(task.remind_at))
         |> assign_form(Tasks.change_task(task))
         |> push_event("open-modal", %{id: "task-modal"})}

      _ ->
        {:noreply, put_flash(socket, :error, gettext("Task not found."))}
    end
  end

  def handle_event("close_task_modal", _params, socket) do
    {:noreply, socket |> reset_form() |> push_event("close-modal", %{id: "task-modal"})}
  end

  def handle_event("save", %{"task" => attrs}, socket) do
    attrs = Map.update(attrs, "account_id", nil, fn value -> if value != "_none", do: value end)

    result =
      case socket.assigns.editing_task do
        nil -> Tasks.create_task(attrs, socket.assigns.current_user)
        task -> Tasks.update_task(task, attrs, socket.assigns.current_user)
      end

    case result do
      {:ok, _task} ->
        {:noreply,
         socket
         |> reset_form()
         |> load_tasks()
         |> push_event("close-modal", %{id: "task-modal"})
         |> put_flash(:info, gettext("Task saved."))}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:remind_local_value, attrs["remind_at"])
         |> assign_form(changeset)}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, gettext("Could not save task."))}
    end
  end

  def handle_event("complete", %{"id" => id}, socket) do
    with %Task{} = task <- Tasks.get_task(id),
         {:ok, _task} <- Tasks.complete_task(task, socket.assigns.current_user) do
      {:noreply, socket |> load_tasks() |> put_flash(:info, gettext("Task completed."))}
    else
      _ -> {:noreply, put_flash(socket, :error, gettext("Could not complete task."))}
    end
  end

  def render(assigns) do
    ~H"""
    <section id="tasks-page" data-part="tasks-page">
      <div data-part="header">
        <div data-part="text">
          <h1 data-part="title">{gettext("Tasks")}</h1>
          <p data-part="description">
            {gettext("Track work for yourself or a teammate, with optional due dates and reminders.")}
          </p>
        </div>
        <div data-part="header-actions">
          <.modal
            id="task-modal"
            title={gettext("Task details")}
            description={gettext("Assign work, set a due date, and add a reminder when needed.")}
            header_type="icon"
            header_size="large"
            on_dismiss="close_task_modal"
            data-part="task-modal"
          >
            <:header_icon><.circle_check /></:header_icon>
            <:trigger :let={modal_attrs}>
              <.button
                id="add-task-button"
                label={gettext("Add task")}
                size="medium"
                type="button"
                phx-click="new"
                {modal_attrs}
              >
                <:icon_left><.circle_plus /></:icon_left>
              </.button>
            </:trigger>

            <div data-part="task-modal-content">
              <.form
                for={@form}
                id="task-form"
                data-part="task-form"
                phx-submit="save"
                phx-hook=".TaskReminder"
                data-reset={@form_reset}
              >
                <.text_input
                  id="task-title-input"
                  field={@form[:title]}
                  label={gettext("Task")}
                  required
                  show_required
                  show_suffix={false}
                />
                <.text_area
                  id="task-description-input"
                  field={@form[:description]}
                  label={gettext("Details")}
                  rows={3}
                  max_length={2000}
                />
                <div data-part="task-select">
                  <.label label={gettext("Assigned to")} required />
                  <.select
                    id="task-assignee-select"
                    name={@form[:assignee_id].name}
                    label={gettext("Choose a teammate")}
                    value={@form[:assignee_id].value}
                  >
                    <:item :for={user <- @users} value={user.id} label={user.name || user.email} />
                  </.select>
                </div>
                <div data-part="task-select">
                  <.label label={gettext("Account")} />
                  <.select
                    id="task-account-select"
                    name={@form[:account_id].name}
                    label={gettext("No account")}
                    value={@form[:account_id].value || "_none"}
                  >
                    <:item value="_none" label={gettext("No account")} />
                    <:item :for={{name, id} <- @accounts} value={id} label={name} />
                  </.select>
                </div>
                <.text_input
                  id="task-due-on-input"
                  field={@form[:due_on]}
                  input_type="date"
                  label={gettext("Due date")}
                  show_suffix={false}
                />
                <div data-part="reminder-field">
                  <.text_input
                    id="task-remind-local"
                    name="remind_local"
                    input_type="datetime-local"
                    label={gettext("Remind")}
                    sublabel={gettext("Optional")}
                    show_suffix={false}
                    data-utc={@remind_local_value}
                  />
                  <.input id="task-remind-at" type="hidden" name="task[remind_at]" value="" />
                </div>
              </.form>
            </div>

            <:footer>
              <.modal_footer>
                <:action>
                  <.button
                    label={gettext("Cancel")}
                    variant="secondary"
                    size="small"
                    type="button"
                    phx-click="close_task_modal"
                  />
                </:action>
                <:action>
                  <.button
                    id="task-submit"
                    label={if @editing_task, do: gettext("Save changes"), else: gettext("Add task")}
                    size="small"
                    type="submit"
                    form="task-form"
                  />
                </:action>
              </.modal_footer>
            </:footer>
          </.modal>
        </div>
      </div>

      <.card title={gettext("Open tasks")} icon="circle_check">
        <.card_section data-part="tasks-card-section">
          <div data-part="filters">
            <.filter_dropdown
              id="tasks-filters-dropdown"
              available_filters={@available_filters}
              active_filters={@active_filters}
            />
            <div data-part="search">
              <.form id="tasks-search-form" for={@search_form} phx-change="search" phx-submit="search">
                <.text_input
                  id="tasks-search"
                  field={@search_form[:query]}
                  type="search"
                  show_suffix={false}
                  placeholder={gettext("Search tasks or accounts...")}
                  aria-label={gettext("Search tasks")}
                  phx-debounce="300"
                />
              </.form>
            </div>
          </div>
          <div :if={@active_filters != []} id="tasks-active-filters" data-part="active-filters">
            <.active_filter :for={filter <- @active_filters} filter={filter} />
          </div>
          <.table :if={!@tasks_empty?} id="tasks-table" rows={@streams.tasks}>
            <:col :let={{_id, task}} label={gettext("Task")}>
              <.text_and_description_cell label={task.title} description={task.description} />
            </:col>
            <:col :let={{_id, task}} label={gettext("Account")}>
              <.text_cell label={if task.account, do: task.account.name, else: "—"} />
            </:col>
            <:col :let={{_id, task}} label={gettext("Assigned to")}>
              <.text_cell label={assignee_name(task)} />
            </:col>
            <:col :let={{_id, task}} label={gettext("Due date")}>
              <.text_cell label={format_due_on(task.due_on)} />
            </:col>
            <:col :let={{_id, task}} label={gettext("Reminder")}>
              <div data-part="task-reminder-cell">
                <time
                  :if={task.remind_at}
                  id={"task-reminder-#{task.id}-#{task.reminder_version}"}
                  phx-hook=".LocalReminderTime"
                  phx-update="ignore"
                  datetime={DateTime.to_iso8601(task.remind_at)}
                  data-utc={DateTime.to_iso8601(task.remind_at)}
                >
                  {format_reminder(task.remind_at)}
                </time>
                <span :if={!task.remind_at}>—</span>
              </div>
            </:col>
            <:col :let={{_id, task}} label={gettext("Actions")}>
              <.button_cell>
                <:button>
                  <.button_dropdown
                    id={"task-actions-#{task.id}"}
                    label={gettext("Edit")}
                    size="medium"
                    align="end"
                    phx-click="edit"
                    phx-value-id={task.id}
                  >
                    <.dropdown_item
                      id={"task-complete-#{task.id}"}
                      value={task.id}
                      label={gettext("Mark as done")}
                      on_click="complete"
                      phx-value-id={task.id}
                    >
                      <:left_icon><.circle_check /></:left_icon>
                    </.dropdown_item>
                  </.button_dropdown>
                </:button>
              </.button_cell>
            </:col>
          </.table>
          <.table :if={@tasks_empty?} id="tasks-empty" rows={[]}>
            <:col label={gettext("Task")} />
            <:col label={gettext("Account")} />
            <:col label={gettext("Assigned to")} />
            <:col label={gettext("Due date")} />
            <:col label={gettext("Reminder")} />
            <:col label={gettext("Actions")} />
            <:empty_state>
              <.table_empty_state
                icon="circle_check"
                title={gettext("No open tasks")}
                subtitle={gettext("Add a task to keep track of upcoming work.")}
              />
            </:empty_state>
          </.table>
        </.card_section>
      </.card>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".TaskReminder">
        export default {
          mounted() {
            this.local = this.el.querySelector("#task-remind-local")
            this.utc = this.el.querySelector("#task-remind-at")
            this.lastReset = this.el.dataset.reset
            this.handleEvent("reset-task-form", () => this.el.reset())
            this.setLocalFromUtc()
            this.el.addEventListener("submit", () => {
              this.utc.value = this.local.value ? new Date(this.local.value).toISOString() : ""
            })
          },
          updated() { this.setLocalFromUtc() },
          setLocalFromUtc() {
            if (this.el.dataset.reset !== this.lastReset) {
              this.local.value = ""
              this.lastReset = this.el.dataset.reset
            }
            const value = this.local.dataset.utc
            if (value && value !== this.lastUtc) {
              const date = new Date(value)
              const local = new Date(date.getTime() - date.getTimezoneOffset() * 60000)
              this.local.value = local.toISOString().slice(0, 16)
            } else if (!value && this.lastUtc) {
              this.local.value = ""
            }
            this.lastUtc = value
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".LocalReminderTime">
        export default {
          mounted() {
            this.el.textContent = new Intl.DateTimeFormat(undefined, {
              dateStyle: "medium",
              timeStyle: "short",
            }).format(new Date(this.el.dataset.utc))
          }
        }
      </script>
    </section>
    """
  end

  defp account_options do
    Repo.all(
      from(account in Account,
        where: is_nil(account.not_an_account_at),
        order_by: [asc: account.name],
        select: {account.name, account.id}
      )
    )
  end

  defp load_tasks(socket) do
    tasks =
      Tasks.list_tasks(
        status: "open",
        query: socket.assigns.query,
        assignee_id: active_filter_value(socket.assigns.active_filters, "assignee_id", :==),
        account_id: active_filter_value(socket.assigns.active_filters, "account_id", :==),
        exclude_assignee_id: active_filter_value(socket.assigns.active_filters, "assignee_id", :!=),
        exclude_account_id: active_filter_value(socket.assigns.active_filters, "account_id", :!=)
      )

    socket
    |> assign(:tasks_empty?, tasks == [])
    |> stream(:tasks, tasks, reset: true)
  end

  defp define_filters(users, accounts) do
    [
      %Filter.Filter{
        id: "assignee_id",
        field: :assignee_id,
        display_name: gettext("Assigned to"),
        type: :option,
        searchable: true,
        options: Enum.map(users, & &1.id),
        options_display_names: Map.new(users, fn user -> {user.id, user.name || user.email} end),
        operator: :==,
        value: nil
      },
      %Filter.Filter{
        id: "account_id",
        field: :account_id,
        display_name: gettext("Account"),
        type: :option,
        searchable: true,
        options: Enum.map(accounts, fn {_name, id} -> id end),
        options_display_names: Map.new(accounts, fn {name, id} -> {id, name} end),
        operator: :==,
        value: nil
      }
    ]
  end

  defp active_filter_value(filters, filter_id, operator) do
    case Enum.find(filters, &(&1.id == filter_id && &1.operator == operator)) do
      %{value: value} -> value
      _filter -> nil
    end
  end

  defp current_query_params(socket) do
    socket.assigns.uri.query
    |> Kernel.||("")
    |> URI.decode_query()
  end

  defp search_form(query), do: to_form(%{"query" => query}, as: :search)

  defp reset_form(socket) do
    socket
    |> assign(:editing_task, nil)
    |> update(:form_reset, &(&1 + 1))
    |> assign(:remind_local_value, nil)
    |> assign_form(Tasks.change_task(%Task{assignee_id: socket.assigns.current_user.id}))
    |> push_event("reset-task-form", %{})
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset, as: :task))

  defp format_reminder(date_time), do: Calendar.strftime(date_time, "%d %b %Y, %H:%M UTC")

  defp format_due_on(nil), do: "—"
  defp format_due_on(date), do: Calendar.strftime(date, "%b %-d, %Y")

  defp assignee_name(%Task{assignee: nil}), do: gettext("Unassigned")
  defp assignee_name(%Task{assignee: assignee}), do: assignee.name || assignee.email
end
