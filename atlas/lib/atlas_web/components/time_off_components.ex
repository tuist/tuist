defmodule AtlasWeb.TimeOffComponents do
  use AtlasWeb, :html
  use Noora

  import AtlasWeb.CoreComponents, only: [translate_error: 1]

  attr :form, :any, required: true
  attr :editing, :any, required: true
  attr :version, :integer, required: true

  def request_modal(assigns) do
    assigns = assign(assigns, :period, request_period(assigns.form))

    ~H"""
    <.modal
      id="holiday-request-modal"
      title={gettext("Holiday request")}
      description={gettext("Choose the first and last day you will be away.")}
      header_type="icon"
      header_size="large"
      on_dismiss="close_request_modal"
    >
      <:header_icon><.calendar_week /></:header_icon>
      <:trigger :let={modal_attrs}>
        <.button
          id="request-holiday-button"
          type="button"
          label={gettext("Request holiday")}
          phx-click="new_request"
          {modal_attrs}
        >
          <:icon_left><.plus /></:icon_left>
        </.button>
      </:trigger>
      <div id={"holiday-request-content-#{@version}"} data-part="holiday-request-modal-content">
        <p id="time-off-calendar-location">
          {gettext("Public holidays follow the Berlin calendar.")}
        </p>
        <p>
          {gettext(
            "Dates are inclusive. Working-day counts exclude weekends and configured public holidays."
          )}
        </p>
        <p :if={@editing} id="holiday-edit-approval-notice">
          {gettext("Changing the dates sends this request back for approval.")}
        </p>
        <.form
          for={@form}
          id="time-off-booking-form"
          phx-submit="report"
          data-part="holiday-request-form"
        >
          <input
            type="hidden"
            data-part="range-start-input"
            name={@form[:starts_on].name}
            value={date_value(@form[:starts_on].value)}
          />
          <input
            type="hidden"
            data-part="range-end-input"
            name={@form[:ends_on].name}
            value={date_value(@form[:ends_on].value)}
          />
          <.date_picker
            id={"holiday-date-picker-#{@version}"}
            data-part="holiday-range-picker"
            data-date-only="true"
            label={gettext("Choose holiday dates")}
            presets={[]}
            selected_preset="custom"
            period={@period}
            start_of_week={1}
            min={~D[2000-01-01]}
            max={~D[2100-12-31]}
            on_period_change="holiday_dates_changed"
          >
            <:actions>
              <.button
                type="button"
                label={gettext("Cancel")}
                variant="secondary"
                phx-click={
                  JS.dispatch("phx:date-picker-cancel",
                    detail: %{id: "holiday-date-picker-#{@version}"}
                  )
                }
              />
              <.button
                type="button"
                label={gettext("Apply dates")}
                phx-click={
                  JS.dispatch("phx:date-picker-apply",
                    detail: %{id: "holiday-date-picker-#{@version}"}
                  )
                }
              />
            </:actions>
          </.date_picker>
          <p :for={error <- @form[:starts_on].errors} data-part="range-error" role="alert">
            {gettext("First day away")}: {translate_error(error)}
          </p>
          <p :for={error <- @form[:ends_on].errors} data-part="range-error" role="alert">
            {gettext("Last day away")}: {translate_error(error)}
          </p>
        </.form>
      </div>
      <:footer>
        <.modal_footer>
          <:action>
            <.button
              type="button"
              variant="secondary"
              label={gettext("Cancel")}
              phx-click="close_request_modal"
            />
          </:action>
          <:action>
            <.button
              id="report-holiday"
              type="submit"
              form="time-off-booking-form"
              label={if @editing, do: gettext("Save changes"), else: gettext("Request holiday")}
            />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  defp request_period(form) do
    with {:ok, first} <- Date.from_iso8601(date_value(form[:starts_on].value)),
         {:ok, last} <- Date.from_iso8601(date_value(form[:ends_on].value)),
         true <- Date.compare(first, last) != :gt do
      {DateTime.new!(first, ~T[00:00:00], "Etc/UTC"), DateTime.new!(last, ~T[00:00:00], "Etc/UTC")}
    else
      _ -> nil
    end
  end

  defp date_value(%Date{} = date), do: Date.to_iso8601(date)
  defp date_value(value) when is_binary(value), do: value
  defp date_value(_value), do: ""

  attr :streams, :map, required: true
  attr :upcoming_meta, :any, required: true
  attr :mine_meta, :any, required: true
  attr :holidays_meta, :any, required: true
  attr :current_user, :any, required: true
  attr :approver?, :boolean, required: true
  attr :query_params, :map, required: true

  def overview(assigns) do
    ~H"""
    <div id="time-off-overview" data-part="time-off-overview">
      <.card title={gettext("Upcoming time off")} icon="calendar_week">
        <.card_section>
          <.table
            id="time-off-upcoming"
            rows={@streams.upcoming}
          >
            <:col :let={{_id, booking}} label={gettext("Person")}>
              <.text_cell label={booking.name} />
            </:col>
            <:col :let={{_id, booking}} label={gettext("Dates")}>
              <.text_cell label={format_dates(booking)} />
            </:col>
            <:col :let={{_id, booking}} label={gettext("Status")}>
              <.request_status booking={booking} prefix="upcoming" />
            </:col>
            <:col :let={{_id, booking}} label={gettext("Working days")}>
              <.day_count booking={booking} />
            </:col>
            <:col :let={{_id, booking}} :if={@approver?} label={gettext("Actions")}>
              <.approval_actions
                booking={booking}
                allowed={@approver? && booking.user_id != @current_user.id}
              />
            </:col>
          </.table>
          <div :if={@upcoming_meta.total_count == 0} id="time-off-upcoming-empty">
            <.table_empty_state
              icon="calendar_week"
              title={gettext("No upcoming time off")}
              subtitle={gettext("Upcoming holiday requests will appear here.")}
            />
          </div>
          <.pagination_group
            :if={@upcoming_meta.total_pages > 1}
            id="time-off-upcoming-pagination"
            current_page={@upcoming_meta.current_page}
            number_of_pages={@upcoming_meta.total_pages}
            page_patch={fn page -> page_link(@query_params, "upcoming_page", page) end}
          />
        </.card_section>
      </.card>

      <.card title={gettext("My requests")} icon="calendar_week">
        <.card_section>
          <.table
            id="time-off-my-requests"
            rows={@streams.mine}
          >
            <:col :let={{_id, booking}} label={gettext("Dates")}>
              <.text_cell label={format_dates(booking)} />
            </:col>
            <:col :let={{_id, booking}} label={gettext("Status")}>
              <.request_status booking={booking} prefix="mine" />
            </:col>
            <:col :let={{_id, booking}} label={gettext("Working days")}>
              <.day_count booking={booking} />
            </:col>
            <:col :let={{_id, booking}} label={gettext("Actions")}>
              <.own_actions booking={booking} />
            </:col>
          </.table>
          <div :if={@mine_meta.total_count == 0} id="time-off-my-empty">
            <.table_empty_state
              icon="calendar_week"
              title={gettext("No holiday requests yet")}
              subtitle={gettext("Request a holiday to start planning your time off.")}
            />
          </div>
          <.pagination_group
            :if={@mine_meta.total_pages > 1}
            id="time-off-my-pagination"
            current_page={@mine_meta.current_page}
            number_of_pages={@mine_meta.total_pages}
            page_patch={fn page -> page_link(@query_params, "requests_page", page) end}
          />
        </.card_section>
      </.card>

      <.card title={gettext("Upcoming public holidays")} icon="calendar_week">
        <.card_section>
          <p>{gettext("Berlin public holidays are automatically synced from Nager.Date.")}</p>
          <.table
            id="time-off-upcoming-public-holidays"
            rows={@streams.upcoming_holidays}
          >
            <:col :let={{_id, holiday}} label={gettext("Holiday name")}>
              <.text_cell label={holiday.name} />
            </:col>
            <:col :let={{_id, holiday}} label={gettext("Date")}>
              <.text_cell label={Calendar.strftime(holiday.date, "%d %b %Y")} />
            </:col>
          </.table>
          <.table_empty_state
            :if={@holidays_meta.total_count == 0}
            icon="calendar_week"
            title={gettext("No upcoming public holidays configured")}
            subtitle={
              gettext("Public holidays will appear after the automatic calendar sync completes.")
            }
          />
          <.pagination_group
            :if={@holidays_meta.total_pages > 1}
            id="time-off-holidays-pagination"
            current_page={@holidays_meta.current_page}
            number_of_pages={@holidays_meta.total_pages}
            page_patch={fn page -> page_link(@query_params, "holidays_page", page) end}
          />
        </.card_section>
      </.card>
    </div>
    """
  end

  attr :booking, :map, required: true
  attr :prefix, :string, required: true

  def request_status(assigns) do
    ~H"""
    <.badge
      id={"#{@prefix}-status-#{@booking.id}"}
      label={status_label(@booking.status)}
      color={status_color(@booking.status)}
      style="light-fill"
      data-status={@booking.status}
    />
    """
  end

  attr :booking, :map, required: true
  attr :allowed, :boolean, required: true

  def approval_actions(assigns) do
    ~H"""
    <.button_dropdown
      :if={@allowed && @booking.status == "pending"}
      id={"approve-holiday-#{@booking.id}"}
      label={gettext("Approve")}
      size="medium"
      align="end"
      phx-click="review"
      phx-value-id={@booking.id}
      phx-value-decision="approved"
    >
      <.dropdown_item
        id={"reject-holiday-#{@booking.id}"}
        value="reject"
        label={gettext("Reject")}
        phx-click="review"
        phx-value-id={@booking.id}
        phx-value-decision="rejected"
        data-confirm={gettext("Reject this holiday request?")}
      />
    </.button_dropdown>
    """
  end

  attr :booking, :map, required: true

  def own_actions(assigns) do
    ~H"""
    <.button_dropdown
      :if={@booking.status in ["pending", "approved"]}
      id={"edit-holiday-#{@booking.id}"}
      label={gettext("Edit request")}
      size="medium"
      align="end"
      phx-click="edit_request"
      phx-value-id={@booking.id}
    >
      <.dropdown_item
        id={"cancel-holiday-#{@booking.id}"}
        value="cancel"
        label={gettext("Cancel holiday")}
        phx-click="cancel"
        phx-value-id={@booking.id}
        data-confirm={gettext("Cancel this holiday?")}
      />
    </.button_dropdown>
    <.button
      :if={@booking.status == "rejected"}
      id={"edit-holiday-#{@booking.id}-button"}
      type="button"
      variant="secondary"
      label={gettext("Edit request")}
      phx-click="edit_request"
      phx-value-id={@booking.id}
    />
    """
  end

  defp status_color("pending"), do: "warning"
  defp status_color("approved"), do: "success"
  defp status_color("rejected"), do: "destructive"
  defp status_color("cancelled"), do: "neutral"

  attr :booking, :map, required: true

  defp day_count(assigns) do
    ~H"""
    <div data-part="day-count">
      <span>{@booking.working_days}</span><span
        :if={@booking.missing_years != []}
        data-part="coverage-note"
      >{gettext("Public holiday calendar incomplete")}</span>
    </div>
    """
  end

  defp format_dates(booking),
    do: Calendar.strftime(booking.starts_on, "%d %b %Y") <> " – " <> Calendar.strftime(booking.ends_on, "%d %b %Y")

  defp page_link(params, key, page), do: ~p"/people/time-off?#{Map.put(params, key, page)}"
  defp status_label("pending"), do: gettext("Pending holiday")
  defp status_label("approved"), do: gettext("Approved holiday")
  defp status_label("rejected"), do: gettext("Rejected")
  defp status_label("cancelled"), do: gettext("Cancelled")
end
