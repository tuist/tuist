defmodule TuistWeb.Storybook.Card do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  alias Noora.Card

  def function, do: &Card.card/1
  def layout, do: :one_column

  def imports, do: [{Card, [card_section: 1]}, {Noora.Button, [button: 1]}]

  def variations do
    [
      %VariationGroup{
        id: :basic,
        description: "Basic card configurations with different content arrangements",
        variations: [
          %Variation{
            id: :simple,
            attributes: %{
              id: "card-simple",
              style: "width: 350px",
              icon: "dashboard",
              title: "Dashboard Overview"
            },
            slots: [
              """
              <.card_section>
                <p>This is a simple card with basic content. It contains a title, icon, and some descriptive text.</p>
              </.card_section>
              """
            ]
          },
          %Variation{
            id: :with_actions,
            attributes: %{
              id: "card-with-actions",
              style: "width: 350px",
              icon: "chart_arcs",
              title: "Recent Analytics"
            },
            slots: [
              """
              <:actions>
                <.button variant="secondary" label="View Details" size="medium" />
              </:actions>
              <.card_section>
                <p>This card includes action buttons in the header area. Users can interact with these actions to perform related tasks.</p>
              </.card_section>
              """
            ]
          },
          %Variation{
            id: :multiple_actions,
            attributes: %{
              id: "card-multiple-actions",
              style: "width: 400px",
              icon: "settings",
              title: "Project Settings"
            },
            slots: [
              """
              <:actions>
                <.button variant="secondary" label="Edit" size="medium" />
                <.button variant="primary" label="Save" size="medium" />
              </:actions>
              <.card_section>
                <p>Cards can contain multiple action buttons for different operations.</p>
              </.card_section>
              """
            ]
          }
        ]
      },
      %VariationGroup{
        id: :content_variations,
        description: "Cards with different content structures and multiple sections",
        variations: [
          %Variation{
            id: :multiple_sections,
            attributes: %{
              id: "card-multiple-sections",
              style: "width: 400px",
              icon: "folders",
              title: "Project Structure"
            },
            slots: [
              """
              <.card_section>
                <h4>Source Files</h4>
                <p>Contains all the main application source code and modules.</p>
              </.card_section>
              <.card_section>
                <h4>Test Files</h4>
                <p>Unit tests, integration tests, and test utilities.</p>
              </.card_section>
              <.card_section>
                <h4>Documentation</h4>
                <p>API documentation, guides, and project notes.</p>
              </.card_section>
              """
            ]
          },
          %Variation{
            id: :rich_content,
            attributes: %{
              id: "card-rich-content",
              style: "width: 450px",
              icon: "chart_donut_4",
              title: "Performance Metrics"
            },
            slots: [
              """
              <:actions>
                <.button variant="secondary" label="Export" size="medium" />
              </:actions>
              <.card_section>
                <div style="margin-bottom: 12px;">
                  <strong>Response Time:</strong> 245ms
                </div>
                <div style="margin-bottom: 12px;">
                  <strong>Throughput:</strong> 1,250 req/sec
                </div>
                <div style="margin-bottom: 12px;">
                  <strong>Error Rate:</strong> 0.12%
                </div>
              </.card_section>
              <.card_section>
                <em>Last updated: 2 minutes ago</em>
              </.card_section>
              """
            ]
          }
        ]
      },
      %VariationGroup{
        id: :different_icons,
        description: "Cards showcasing different icon types and purposes",
        variations: [
          %Variation{
            id: :database_card,
            attributes: %{
              id: "card-database",
              style: "width: 320px",
              icon: "database",
              title: "Database Status"
            },
            slots: [
              """
              <.card_section>
                <p>Current database health and connection status information.</p>
              </.card_section>
              """
            ]
          },
          %Variation{
            id: :user_card,
            attributes: %{
              id: "card-user",
              style: "width: 320px",
              icon: "user",
              title: "User Profile"
            },
            slots: [
              """
              <.card_section>
                <p>User account information and profile settings.</p>
              </.card_section>
              """
            ]
          },
          %Variation{
            id: :notification_card,
            attributes: %{
              id: "card-notification",
              style: "width: 320px",
              icon: "mail",
              title: "Notifications"
            },
            slots: [
              """
              <:actions>
                <.button variant="secondary" label="Mark All Read" size="medium" />
              </:actions>
              <.card_section>
                <p>Recent notifications and system alerts.</p>
              </.card_section>
              """
            ]
          }
        ]
      }
    ]
  end
end
