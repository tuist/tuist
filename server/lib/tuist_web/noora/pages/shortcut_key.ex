defmodule TuistWeb.Noora.Pages.ShortcutKey do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Shortcut key",
    description: "Shows a key on the keyboard, for hints about keyboard shortcuts.",
    components: [{Noora.ShortcutKey, :shortcut_key}],
    guidelines: [
      "Put one key in each shortcut key and place them side by side for combinations.",
      "Use `small` next to body text, such as in a modal footer. `large` is the default and suits standalone hints.",
      "Each key renders a `<kbd>` element around its content. Use symbols such as ⌘ and ↵, or short names such as esc.",
      "Pair the keys with the action they trigger, such as Close or Search, instead of showing them alone."
    ]

  example "Sizes", description: "Large is the default. Small fits next to body text." do
    ~H"""
    <.shortcut_key>esc</.shortcut_key>
    <.shortcut_key size="small">esc</.shortcut_key>
    """
  end

  example "Combinations", description: "One key per element, placed side by side." do
    ~H"""
    <.shortcut_key>⌘</.shortcut_key>
    <.shortcut_key>K</.shortcut_key>
    """
  end

  example "With an action", description: "A small key next to the action it triggers." do
    ~H"""
    <span>
      <.shortcut_key size="small">↵</.shortcut_key>
      Open
    </span>
    <span>
      <.shortcut_key size="small">esc</.shortcut_key>
      Close
    </span>
    """
  end
end
