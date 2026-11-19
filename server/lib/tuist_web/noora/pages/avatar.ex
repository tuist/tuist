defmodule TuistWeb.Noora.Pages.Avatar do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Avatar",
    description: "Represents a person or an account with their picture, or with their initials when there is no picture.",
    components: [{Noora.Avatar, :avatar}],
    guidelines: [
      "Always pass the account's `name`. It produces the initials and stays the fallback when the image is missing or fails to load.",
      "Initials come from the first letters of the first two words of the name, split on spaces, hyphens, underscores, and commas. The `2xsmall` size shows one initial.",
      "Keep the `color` stable for each account. The dashboard derives it from the account name with `Accounts.avatar_color/1`, so the same account always gets the same color.",
      "Give every avatar a unique `id`. The `NooraAvatar` hook that swaps between the image and the fallback needs it.",
      "Pass `image_alt=\"\"` when the name is already written next to the avatar, so screen readers do not announce it twice."
    ]

  example "Initials and image",
    description: "Initials are the default. With `image_href`, the picture replaces them once it loads." do
    ~H"""
    <.avatar id="avatar-initials" name="Marek Fořt" color="blue" />
    <.avatar
      id="avatar-image"
      name="Pedro Piñera"
      image_href="/marketing/images/noora/pedro.png"
      image_alt="Pedro Piñera"
    />
    """
  end

  example "Sizes",
    description: "Medium is the default. Use the smaller sizes in tables and menus, and the larger ones on profile pages." do
    ~H"""
    <.avatar id="avatar-size-2xsmall" name="Asmit Malakannawar" size="2xsmall" color="purple" />
    <.avatar id="avatar-size-small" name="Asmit Malakannawar" size="small" color="purple" />
    <.avatar id="avatar-size-medium" name="Asmit Malakannawar" size="medium" color="purple" />
    <.avatar id="avatar-size-large" name="Asmit Malakannawar" size="large" color="purple" />
    <.avatar id="avatar-size-xlarge" name="Asmit Malakannawar" size="xlarge" color="purple" />
    <.avatar id="avatar-size-2xlarge" name="Asmit Malakannawar" size="2xlarge" color="purple" />
    """
  end

  example "Colors", description: "Purple is the default. Each color helps tell accounts apart in a list." do
    ~H"""
    <.avatar id="avatar-color-gray" name="Tuist" color="gray" />
    <.avatar id="avatar-color-red" name="Rover Labs" color="red" />
    <.avatar id="avatar-color-orange" name="Orbit Mobile" color="orange" />
    <.avatar id="avatar-color-yellow" name="Yellow Pages" color="yellow" />
    <.avatar id="avatar-color-green" name="Green Ledger" color="green" />
    <.avatar id="avatar-color-azure" name="Azure Apps" color="azure" />
    <.avatar id="avatar-color-blue" name="Blue Harbor" color="blue" />
    <.avatar id="avatar-color-purple" name="Purple Studio" color="purple" />
    <.avatar id="avatar-color-pink" name="Pink Pixel" color="pink" />
    """
  end

  example "Name formats", description: "Single words give one initial. Handles split on hyphens and underscores." do
    ~H"""
    <.avatar id="avatar-name-single" name="tuist" color="gray" />
    <.avatar id="avatar-name-hyphen" name="ios-platform-team" color="azure" />
    <.avatar id="avatar-name-underscore" name="release_bot" color="orange" />
    <.avatar id="avatar-name-three-words" name="Mobile Developer Experience" color="green" />
    """
  end

  example "Placeholder",
    description: "With `fallback=\"placeholder\"`, an animated dither texture replaces the initials." do
    ~H"""
    <.avatar id="avatar-placeholder-small" name="Unknown author" fallback="placeholder" size="small" />
    <.avatar id="avatar-placeholder-medium" name="Unknown author" fallback="placeholder" />
    <.avatar id="avatar-placeholder-large" name="Unknown author" fallback="placeholder" size="large" />
    """
  end
end
