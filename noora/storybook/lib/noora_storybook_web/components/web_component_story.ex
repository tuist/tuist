defmodule NooraStorybookWeb.WebComponentStory do
  @moduledoc false
  use Phoenix.Component

  alias Phoenix.HTML
  alias Phoenix.LiveView.JS
  alias PhoenixStorybook.Rendering.CodeRenderer

  @setup_code """
  import "@tuist/noora/tokens.css";
  import "@tuist/noora/web-components";
  """

  attr(:contract, :map, required: true)

  def web_component_story(assigns) do
    assigns = assign(assigns, :setup_code, @setup_code)

    ~H"""
    <div style="display: flex; max-width: 960px; flex-direction: column; gap: var(--noora-spacing-10); padding: var(--noora-spacing-6);">
      <div>
        <h1 style="margin: 0; font: var(--noora-font-weight-semibold) var(--noora-font-heading-large);">
          {@contract["name"]} web component
        </h1>
        <p style="margin: var(--noora-spacing-2) 0 0; color: var(--noora-surface-label-secondary); font: var(--noora-font-body-medium);">
          {@contract["description"]}
        </p>
      </div>

      <section style="display: flex; flex-direction: column; gap: var(--noora-spacing-4);">
        <h2 style="margin: 0; font: var(--noora-font-weight-medium) var(--noora-font-heading-small);">
          Setup
        </h2>
        <.copyable_code code={@setup_code} language={:text} />
      </section>

      <.component_example
        :for={example <- @contract["examples"]}
        title={example["title"]}
        description={example["description"]}
        code={example["markup"]}
      />

      <.attributes_table attributes={@contract["attributes"]} />
      <.named_items_table
        :if={@contract["slots"] != []}
        title="Slots"
        items={@contract["slots"]}
        default_name="default"
      />
      <.named_items_table
        :if={@contract["cssParts"] != []}
        title="Styling parts"
        items={@contract["cssParts"]}
      />

      <section
        :if={Map.get(@contract, "notes", []) != []}
        style="display: flex; flex-direction: column; gap: var(--noora-spacing-3);"
      >
        <h2 style="margin: 0; font: var(--noora-font-weight-medium) var(--noora-font-heading-small);">
          Behavior
        </h2>
        <p
          :for={note <- @contract["notes"]}
          style="margin: 0; color: var(--noora-surface-label-secondary); font: var(--noora-font-body-medium);"
        >
          {note}
        </p>
      </section>
    </div>
    """
  end

  attr(:code, :string, required: true)
  attr(:language, :atom, default: :heex)

  defp copyable_code(assigns) do
    ~H"""
    <div style="position: relative;">
      <button
        type="button"
        aria-label="Copy code"
        phx-click={JS.dispatch("psb:copy-code")}
        style="position: absolute; z-index: 1; top: var(--noora-spacing-2); right: var(--noora-spacing-2); cursor: pointer; border: 1px solid var(--noora-surface-border-primary); border-radius: var(--noora-radius-small); padding: var(--noora-spacing-1) var(--noora-spacing-3); background: var(--noora-surface-background-primary); color: var(--noora-surface-label-primary); font: var(--noora-font-body-small);"
      >
        Copy
      </button>
      <%= if @language == :heex do %>
        {CodeRenderer.render_code_block(@code, :heex)}
      <% else %>
        <pre class="psb highlight psb:p-2 psb:md:p-3 psb:border psb:border-slate-800 psb:text-xs psb:md:text-sm psb:rounded-md psb:bg-slate-800! psb:whitespace-pre-wrap psb:break-normal"><code>{@code}</code></pre>
      <% end %>
    </div>
    """
  end

  attr(:code, :string, required: true)
  attr(:description, :string, default: nil)
  attr(:title, :string, required: true)

  defp component_example(assigns) do
    ~H"""
    <section style="display: flex; flex-direction: column; gap: var(--noora-spacing-4);">
      <div>
        <h2 style="margin: 0; font: var(--noora-font-weight-medium) var(--noora-font-heading-small);">
          {@title}
        </h2>
        <p
          :if={@description}
          style="margin: var(--noora-spacing-2) 0 0; color: var(--noora-surface-label-secondary); font: var(--noora-font-body-medium);"
        >
          {@description}
        </p>
      </div>
      <div style="display: flex; flex-wrap: wrap; align-items: center; gap: var(--noora-spacing-4); border: 1px solid var(--noora-surface-border-primary); border-radius: var(--noora-radius-medium); padding: var(--noora-spacing-6); background: var(--noora-surface-background-primary);">
        {HTML.raw(@code)}
      </div>
      <.copyable_code code={@code} />
    </section>
    """
  end

  attr(:attributes, :list, required: true)

  defp attributes_table(assigns) do
    ~H"""
    <section style="display: flex; flex-direction: column; gap: var(--noora-spacing-4);">
      <h2 style="margin: 0; font: var(--noora-font-weight-medium) var(--noora-font-heading-small);">
        Attributes
      </h2>
      <div style="overflow-x: auto; border: 1px solid var(--noora-surface-border-primary); border-radius: var(--noora-radius-medium);">
        <table style="width: 100%; border-collapse: collapse; text-align: left;">
          <thead>
            <tr style="background: var(--noora-surface-background-secondary);">
              <.table_header>Attribute</.table_header>
              <.table_header>Type or allowed values</.table_header>
              <.table_header>Default</.table_header>
              <.table_header>Description</.table_header>
            </tr>
          </thead>
          <tbody>
            <tr :for={attribute <- @attributes}>
              <.table_cell><code>{attribute["name"]}</code></.table_cell>
              <.table_cell>{attribute_type(attribute)}</.table_cell>
              <.table_cell><code>{attribute_default(attribute)}</code></.table_cell>
              <.table_cell>{attribute["description"]}</.table_cell>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  attr(:default_name, :string, default: nil)
  attr(:items, :list, required: true)
  attr(:title, :string, required: true)

  defp named_items_table(assigns) do
    ~H"""
    <section style="display: flex; flex-direction: column; gap: var(--noora-spacing-4);">
      <h2 style="margin: 0; font: var(--noora-font-weight-medium) var(--noora-font-heading-small);">
        {@title}
      </h2>
      <div style="overflow-x: auto; border: 1px solid var(--noora-surface-border-primary); border-radius: var(--noora-radius-medium);">
        <table style="width: 100%; border-collapse: collapse; text-align: left;">
          <thead>
            <tr style="background: var(--noora-surface-background-secondary);">
              <.table_header>Name</.table_header>
              <.table_header>Description</.table_header>
            </tr>
          </thead>
          <tbody>
            <tr :for={item <- @items}>
              <.table_cell><code>{item_name(item, @default_name)}</code></.table_cell>
              <.table_cell>{item["description"]}</.table_cell>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  slot(:inner_block, required: true)

  defp table_header(assigns) do
    ~H"""
    <th style="border-bottom: 1px solid var(--noora-surface-border-primary); padding: var(--noora-spacing-3) var(--noora-spacing-4); font: var(--noora-font-weight-medium) var(--noora-font-body-small);">
      {render_slot(@inner_block)}
    </th>
    """
  end

  slot(:inner_block, required: true)

  defp table_cell(assigns) do
    ~H"""
    <td style="border-bottom: 1px solid var(--noora-surface-border-primary); padding: var(--noora-spacing-3) var(--noora-spacing-4); vertical-align: top; font: var(--noora-font-body-small);">
      {render_slot(@inner_block)}
    </td>
    """
  end

  defp attribute_type(%{"values" => values}), do: Enum.join(values, ", ")
  defp attribute_type(attribute), do: attribute["type"]

  defp item_name(%{"name" => name}, default_name) when name in [nil, ""], do: default_name
  defp item_name(%{"name" => name}, _default_name), do: name

  defp attribute_default(attribute) do
    if Map.has_key?(attribute, "default") do
      Jason.encode!(attribute["default"])
    else
      "None"
    end
  end
end
