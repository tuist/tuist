defmodule TuistWeb.Noora.Pages.Modal do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Modal",
    description: "Shows content in a dialog over the page that people must deal with before returning to it.",
    components: [{Noora.Modal, :modal}, {Noora.Modal, :modal_footer}],
    guidelines: [
      "Use a modal for a focused task or a confirmation, such as inviting a member or deleting a project. Keep longer flows on their own page.",
      "Spread the attributes from the `:trigger` slot onto the element that opens the modal: `<:trigger :let={attrs}>` and then `{attrs}` on the button.",
      "Close a modal from your own buttons with `JS.dispatch(\"phx:close-modal\", detail: %{id: id})`, or open one from anywhere with `phx:open-modal`. Escape, a click outside, and the dismiss icon also close it.",
      "The description only shows when `header_size` is `large`. Use `small` for short confirmations that need no explanation.",
      "Match `header_type` to the outcome: `success`, `info`, `warning`, and `error` add a status icon, and `icon` shows your own icon from the `:header_icon` slot.",
      "Put the actions in a `modal_footer`, with the main action last. Use `type=\"stretch\"` to make the actions fill the footer's width."
    ]

  alias Phoenix.LiveView.JS

  example "Default", description: "A title, a description, a body, and actions in the footer." do
    ~H"""
    <.modal
      id="modal-default"
      title="Invite member"
      description="They'll get an email with a link to join your organization."
    >
      <:trigger :let={attrs}>
        <.button label="Invite member" {attrs} />
      </:trigger>
      <.text_input
        id="modal-default-email"
        name="email"
        value=""
        type="email"
        label="Email"
        placeholder="hello@tuist.dev"
      />
      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label="Cancel"
              variant="secondary"
              phx-click={JS.dispatch("phx:close-modal", detail: %{id: "modal-default"})}
            />
          </:action>
          <:action>
            <.button label="Send invite" />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  example "Header types", description: "Status types add an icon that matches the outcome." do
    ~H"""
    <.modal
      id="modal-success"
      title="Cache warmed"
      description="128 targets were built and uploaded to the cache."
      header_type="success"
    >
      <:trigger :let={attrs}>
        <.button label="Success" variant="secondary" {attrs} />
      </:trigger>
    </.modal>
    <.modal
      id="modal-info"
      title="Selective testing is on"
      description="Tuist skips tests whose dependencies did not change."
      header_type="info"
    >
      <:trigger :let={attrs}>
        <.button label="Info" variant="secondary" {attrs} />
      </:trigger>
    </.modal>
    <.modal
      id="modal-warning"
      title="Build minutes almost used up"
      description="You've used 90% of this month's build minutes."
      header_type="warning"
    >
      <:trigger :let={attrs}>
        <.button label="Warning" variant="secondary" {attrs} />
      </:trigger>
    </.modal>
    <.modal
      id="modal-error"
      title="Preview upload failed"
      description="The upload timed out. Run tuist share again to retry."
      header_type="error"
    >
      <:trigger :let={attrs}>
        <.button label="Error" variant="secondary" {attrs} />
      </:trigger>
    </.modal>
    """
  end

  example "Custom icon", description: "The `icon` header type shows the icon from the `:header_icon` slot." do
    ~H"""
    <.modal id="modal-custom-icon" title="Remove member" header_type="icon" header_size="small">
      <:trigger :let={attrs}>
        <.button label="Remove member" variant="destructive" {attrs} />
      </:trigger>
      <:header_icon><.trash /></:header_icon>
      <p>Are you sure you want to remove ana from this organization?</p>
      <:footer>
        <.modal_footer>
          <:action>
            <.button
              label="Cancel"
              variant="secondary"
              phx-click={JS.dispatch("phx:close-modal", detail: %{id: "modal-custom-icon"})}
            />
          </:action>
          <:action>
            <.button label="Remove" variant="destructive" />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end

  example "Header sizes", description: "Large is the default and shows the description. Small shows only the title." do
    ~H"""
    <.modal
      id="modal-header-large"
      title="Rotate token"
      description="Clients that use the current token stop working."
    >
      <:trigger :let={attrs}>
        <.button label="Large header" variant="secondary" {attrs} />
      </:trigger>
    </.modal>
    <.modal id="modal-header-small" title="Rotate token" header_size="small">
      <:trigger :let={attrs}>
        <.button label="Small header" variant="secondary" {attrs} />
      </:trigger>
    </.modal>
    """
  end

  example "Footer types",
    description:
      "The default footer aligns actions to the end and renders its inner block at the start. Stretch makes the actions fill the width." do
    ~H"""
    <.modal id="modal-footer-default" title="Delete project" header_size="small">
      <:trigger :let={attrs}>
        <.button label="Default footer" variant="secondary" {attrs} />
      </:trigger>
      <p>This deletes the project's builds, test runs, and previews.</p>
      <:footer>
        <.modal_footer>
          <span>This can't be undone.</span>
          <:action>
            <.button
              label="Cancel"
              variant="secondary"
              phx-click={JS.dispatch("phx:close-modal", detail: %{id: "modal-footer-default"})}
            />
          </:action>
          <:action>
            <.button label="Delete project" variant="destructive" />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    <.modal id="modal-footer-stretch" title="Connect GitHub" header_size="small">
      <:trigger :let={attrs}>
        <.button label="Stretch footer" variant="secondary" {attrs} />
      </:trigger>
      <p>Install the Tuist GitHub app to get build and test summaries on pull requests.</p>
      <:footer>
        <.modal_footer type="stretch">
          <:action>
            <.button label="Install GitHub app" />
          </:action>
        </.modal_footer>
      </:footer>
    </.modal>
    """
  end
end
