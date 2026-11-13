defmodule TuistWeb.Components.UserSecurity do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  attr :passkeys, :list, required: true
  attr :editable, :boolean, default: true

  def passkeys(assigns) do
    ~H"""
    <.table :if={@passkeys != []} id="passkey-list" rows={@passkeys}>
      <:col :let={passkey} label={dgettext("dashboard_auth", "Name")}>
        <.text_cell label={passkey.name} title={passkey.name} />
      </:col>
      <:col :let={passkey} label={dgettext("dashboard_auth", "Created")}>
        <.text_cell label={Calendar.strftime(passkey.inserted_at, "%Y-%m-%d")} />
      </:col>
      <:col :let={passkey} label={dgettext("dashboard_auth", "Last used")}>
        <.text_cell
          label={
            if passkey.last_used_at,
              do: Tuist.Utilities.DateFormatter.from_now(passkey.last_used_at),
              else: dgettext("dashboard_auth", "Never used")
          }
          title={
            passkey.last_used_at && Calendar.strftime(passkey.last_used_at, "%Y-%m-%d %H:%M UTC")
          }
        />
      </:col>
      <:col :let={passkey} label="">
        <.button_cell :if={@editable}>
          <:button>
            <.dropdown
              id={"passkey-actions-#{passkey.id}"}
              icon_only
              aria-label={dgettext("dashboard_auth", "Actions")}
            >
              <:icon><.dots_vertical /></:icon>
              <.dropdown_item
                label={dgettext("dashboard_auth", "Rename")}
                value="rename"
                on_click="open-security-modal"
                phx-value-id={"rename-passkey-#{passkey.id}"}
              >
                <:left_icon><.pencil /></:left_icon>
              </.dropdown_item>
              <.dropdown_item
                label={dgettext("dashboard_auth", "Remove")}
                value="remove"
                on_click="open-security-modal"
                phx-value-id={"remove-passkey-#{passkey.id}"}
              >
                <:left_icon><.trash /></:left_icon>
              </.dropdown_item>
            </.dropdown>
            <.modal
              id={"rename-passkey-#{passkey.id}"}
              data-security-modal="rename"
              title={dgettext("dashboard_auth", "Rename passkey")}
            >
              <:trigger :let={attrs}>
                <button type="button" hidden {attrs}></button>
              </:trigger>
              <form
                id={"rename-passkey-form-#{passkey.id}"}
                method="post"
                action={~p"/users/settings/passkeys/#{passkey.id}/rename"}
                data-part="security-action"
              >
                <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
                <.text_input
                  id={"passkey-name-#{passkey.id}"}
                  name="name"
                  value={passkey.name}
                  label={dgettext("dashboard_auth", "Passkey name")}
                  autocomplete="off"
                  data-1p-ignore
                  show_prefix={false}
                />
              </form>
              <:footer>
                <.modal_footer>
                  <:action>
                    <.button
                      variant="secondary"
                      label={dgettext("dashboard_auth", "Cancel")}
                      phx-click="close-security-modal"
                      phx-value-id={"rename-passkey-#{passkey.id}"}
                    />
                    <.button
                      type="submit"
                      form={"rename-passkey-form-#{passkey.id}"}
                      variant="primary"
                      label={dgettext("dashboard_auth", "Save")}
                    />
                  </:action>
                </.modal_footer>
              </:footer>
            </.modal>
            <.modal
              id={"remove-passkey-#{passkey.id}"}
              title={dgettext("dashboard_auth", "Remove passkey?")}
              description={
                dgettext("dashboard_auth", "Remove %{name} from your Tuist account.",
                  name: passkey.name
                )
              }
            >
              <:trigger :let={attrs}>
                <button type="button" hidden {attrs}></button>
              </:trigger>
              <form
                id={"remove-passkey-form-#{passkey.id}"}
                method="post"
                action={~p"/users/settings/passkeys/#{passkey.id}/delete"}
                data-part="security-action"
              >
                <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
                <input type="hidden" name="confirm" value="true" />
                <p>
                  {dgettext("dashboard_auth", "Your other sessions will be signed out")}. {dgettext(
                    "dashboard_auth",
                    "This browser stays signed in."
                  )}
                </p>
                <p>
                  {dgettext(
                    "dashboard_auth",
                    "The saved credential will remain in your password manager or on your security key."
                  )}
                </p>
                <p :if={length(@passkeys) == 1}>
                  {dgettext(
                    "dashboard_auth",
                    "This is your last passkey. Make sure you can sign in another way, or set a password using password reset first."
                  )}
                </p>
              </form>
              <:footer>
                <.modal_footer>
                  <:action>
                    <.button
                      variant="secondary"
                      label={dgettext("dashboard_auth", "Cancel")}
                      phx-click="close-security-modal"
                      phx-value-id={"remove-passkey-#{passkey.id}"}
                    />
                    <.button
                      type="submit"
                      form={"remove-passkey-form-#{passkey.id}"}
                      variant="destructive"
                      label={dgettext("dashboard_auth", "Remove passkey")}
                    />
                  </:action>
                </.modal_footer>
              </:footer>
            </.modal>
          </:button>
        </.button_cell>
      </:col>
    </.table>
    """
  end

  attr :recovery_modal, :string, default: nil

  def mfa_controls(assigns) do
    ~H"""
    <div data-part="recovery-controls">
      <div data-part="row-actions">
        <.button_dropdown
          id="mfa-actions"
          label={dgettext("dashboard_auth", "Regenerate")}
          size="medium"
          align="end"
          phx-click="open-security-modal"
          phx-value-id="regenerate-recovery-modal"
        >
          <.dropdown_item
            label={dgettext("dashboard_auth", "Disable")}
            value="disable"
            on_click="open-security-modal"
            phx-value-id="disable-mfa-modal"
          />
        </.button_dropdown>
        <.modal
          id="regenerate-recovery-modal"
          title={dgettext("dashboard_auth", "Regenerate recovery codes")}
          description={
            dgettext(
              "dashboard_auth",
              "Your old codes will stop working and other sessions will be signed out."
            )
          }
        >
          <:trigger :let={attrs}>
            <button type="button" hidden {attrs}></button>
          </:trigger>
          <form
            id="mfa-regenerate"
            method="post"
            action={~p"/users/settings/mfa/recovery"}
            data-part="security-action"
            data-recovery-modal={@recovery_modal}
            data-source-modal="regenerate-recovery-modal"
            data-error={dgettext("dashboard_auth", "Something went wrong. Please try again.")}
          >
            <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
            <.text_input
              id="mfa-recovery-code"
              name="mfa_code"
              value=""
              label={dgettext("dashboard_auth", "Authentication or recovery code")}
              show_prefix={false}
              autocomplete="one-time-code"
              required
            />
            <span data-enrollment-status role="alert"></span>
          </form>
          <:footer>
            <.modal_footer>
              <:action>
                <.button
                  variant="secondary"
                  label={dgettext("dashboard_auth", "Cancel")}
                  phx-click="close-security-modal"
                  phx-value-id="regenerate-recovery-modal"
                />
                <.button
                  type="submit"
                  form="mfa-regenerate"
                  variant="primary"
                  label={dgettext("dashboard_auth", "Generate")}
                />
              </:action>
            </.modal_footer>
          </:footer>
        </.modal>
        <.modal
          id="disable-mfa-modal"
          title={dgettext("dashboard_auth", "Disable two-factor authentication")}
        >
          <:trigger :let={attrs}>
            <button type="button" hidden {attrs}></button>
          </:trigger>
          <form
            id="mfa-disable"
            method="post"
            action={~p"/users/settings/mfa/disable"}
            data-part="security-action"
            data-recovery-modal={@recovery_modal}
            data-source-modal="disable-mfa-modal"
            data-error={dgettext("dashboard_auth", "Something went wrong. Please try again.")}
          >
            <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
            <p>
              {dgettext(
                "dashboard_auth",
                "Your account will no longer require an authenticator code at sign-in."
              )}
            </p>
            <.text_input
              id="mfa-code"
              name="mfa_code"
              value=""
              label={dgettext("dashboard_auth", "Authentication or recovery code")}
              show_prefix={false}
              autocomplete="one-time-code"
              required
            />
            <span data-enrollment-status role="alert"></span>
          </form>
          <:footer>
            <.modal_footer>
              <:action>
                <.button
                  variant="secondary"
                  label={dgettext("dashboard_auth", "Cancel")}
                  phx-click="close-security-modal"
                  phx-value-id="disable-mfa-modal"
                />
                <.button
                  type="submit"
                  form="mfa-disable"
                  variant="destructive"
                  label={dgettext("dashboard_auth", "Disable two-factor authentication")}
                />
              </:action>
            </.modal_footer>
          </:footer>
        </.modal>
      </div>
    </div>
    """
  end
end
