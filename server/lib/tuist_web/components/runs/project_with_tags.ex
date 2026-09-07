defmodule TuistWeb.Runs.ProjectWithTags do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  attr :label, :string, required: true
  attr :tags, :list, default: []

  def project_with_tags_cell(assigns) do
    ~H"""
    <div data-part="cell" data-type="text">
      <div data-part="project-with-tags" class="tuist-project-with-tags">
        <span data-part="label">{@label}</span>
        <.run_tags tags={@tags} collapse />
      </div>
    </div>
    """
  end

  attr :tags, :list, default: []
  attr :collapse, :boolean, default: false

  def run_tags(assigns) do
    ~H"""
    <.badge
      :if={@tags != []}
      label={List.first(@tags)}
      color="success"
      style="light-fill"
      size="large"
    />
    <%= if @collapse and length(@tags) > 2 do %>
      <.badge label={"+#{length(@tags) - 1}"} color="information" style="light-fill" size="large" />
    <% else %>
      <.badge
        :for={tag <- Enum.drop(@tags, 1)}
        label={tag}
        color="information"
        style="light-fill"
        size="large"
      />
    <% end %>
    """
  end
end
