defmodule TuistWeb.Marketing.MarketingIcons do
  @moduledoc ~S"""
  A collection of components that are used from the layouts.
  """
  use TuistWeb, :live_component

  @default_icon_size 24

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""
  attr :rest, :global

  def share_icon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      {@rest}
      viewBox="0 0 10 10"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M9.5 3.5L9.5 0.5M9.5 0.5H6.5M9.5 0.5L5.5 4.5M4 1.5H2.9C2.05992 1.5 1.63988 1.5 1.31901 1.66349C1.03677 1.8073 0.8073 2.03677 0.66349 2.31901C0.5 2.63988 0.5 3.05992 0.5 3.9V7.1C0.5 7.94008 0.5 8.36012 0.66349 8.68099C0.8073 8.96323 1.03677 9.1927 1.31901 9.33651C1.63988 9.5 2.05992 9.5 2.9 9.5H6.1C6.94008 9.5 7.36012 9.5 7.68099 9.33651C7.96323 9.1927 8.1927 8.96323 8.33651 8.68099C8.5 8.36012 8.5 7.94008 8.5 7.1V6"
        stroke="currentColor"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""
  attr :rest, :global

  def shell_icon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      viewBox="0 0 29 30"
      class={@class}
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      {@rest}
    >
      <path
        d="M26.9939 20.792C25.5307 21.9125 23.9674 22.8859 22.3245 23.6482C24.8019 20.7295 26.7839 17.2209 28.2956 13.9682C27.8213 13.0046 27.2479 12.0999 26.5919 11.2637L26.5666 11.2519C25.0425 14.2454 23.2752 17.1471 21.1271 19.7102C20.867 20.0142 20.6017 20.3166 20.3307 20.6155C21.9596 15.786 22.9614 10.7848 23.7289 5.77727C22.9516 5.19353 22.1176 4.6805 21.2345 4.25005C20.4438 8.24643 19.4616 12.2057 18.2053 16.0348C17.6577 17.6937 17.0528 19.3288 16.3643 20.8947L15.8879 0.610303C15.4306 0.568497 14.9681 0.547852 14.5005 0.547852C14.0329 0.547852 13.5705 0.567981 13.1132 0.610303L12.6363 20.9009C11.9395 19.3226 11.3496 17.6839 10.7952 16.0353C9.53898 12.2057 8.55678 8.24643 7.76607 4.25056C6.88298 4.68101 6.04891 5.19405 5.27162 5.77779C6.03962 10.7889 7.04246 15.7943 8.67343 20.6268C8.40194 20.3269 8.1351 20.0219 7.87343 19.7107C5.72581 17.1476 3.95807 14.2459 2.43394 11.2524L2.40865 11.2642C1.7511 12.1019 1.17768 13.0082 0.703362 13.9724C1.20607 15.064 1.74285 16.1417 2.32143 17.2049C3.55394 19.384 4.98723 21.6405 6.68478 23.6534C5.03833 22.89 3.47239 21.9156 2.00659 20.7925C1.45691 21.5579 0.975362 22.3749 0.572266 23.2379C8.0262 31.5228 20.9723 31.5244 28.4277 23.2379C28.0241 22.3749 27.5431 21.5579 26.9934 20.7925L26.9939 20.792Z"
        fill="currentColor"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def file_download_02_icon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M20 12.5V6.8C20 5.11984 20 4.27976 19.673 3.63803C19.3854 3.07354 18.9265 2.6146 18.362 2.32698C17.7202 2 16.8802 2 15.2 2H8.8C7.11984 2 6.27976 2 5.63803 2.32698C5.07354 2.6146 4.6146 3.07354 4.32698 3.63803C4 4.27976 4 5.11984 4 6.8V17.2C4 18.8802 4 19.7202 4.32698 20.362C4.6146 20.9265 5.07354 21.3854 5.63803 21.673C6.27976 22 7.1198 22 8.79986 22H12.5M14 11H8M10 15H8M16 7H8M15 19L18 22M18 22L21 19M18 22V16"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def cube_outline_icon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      viewBox="0 0 20 22"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M7.75 19.75L9.22297 20.5683C9.50658 20.7259 9.64838 20.8047 9.79855 20.8355C9.93146 20.8629 10.0685 20.8629 10.2015 20.8355C10.3516 20.8047 10.4934 20.7259 10.777 20.5683L12.25 19.75M3.25 17.25L1.82297 16.4572C1.52346 16.2908 1.37368 16.2076 1.26463 16.0893C1.16816 15.9846 1.09515 15.8605 1.05048 15.7253C1 15.5725 1 15.4012 1 15.0586V13.5M1 8.5V6.94145C1 6.5988 1 6.42748 1.05048 6.27468C1.09515 6.13951 1.16816 6.01543 1.26463 5.91074C1.37368 5.7924 1.52345 5.7092 1.82297 5.5428L3.25 4.75M7.75 2.25L9.22297 1.43168C9.50658 1.27412 9.64838 1.19535 9.79855 1.16446C9.93146 1.13713 10.0685 1.13713 10.2015 1.16446C10.3516 1.19535 10.4934 1.27412 10.777 1.43168L12.25 2.25M16.75 4.75L18.177 5.54279C18.4766 5.7092 18.6263 5.7924 18.7354 5.91073C18.8318 6.01542 18.9049 6.13951 18.9495 6.27468C19 6.42748 19 6.5988 19 6.94145V8.5M19 13.5V15.0586C19 15.4012 19 15.5725 18.9495 15.7253C18.9049 15.8605 18.8318 15.9846 18.7354 16.0893C18.6263 16.2076 18.4766 16.2908 18.177 16.4572L16.75 17.25M7.75 9.75L10 11M10 11L12.25 9.75M10 11V13.5M1 6L3.25 7.25M16.75 7.25L19 6M10 18.5V21"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def face_smiles_icon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M8 14C8 14 9.5 16 12 16C14.5 16 16 14 16 14M15 9H15.01M9 9H9.01M22 12C22 17.5228 17.5228 22 12 22C6.47715 22 2 17.5228 2 12C2 6.47715 6.47715 2 12 2C17.5228 2 22 6.47715 22 12ZM15.5 9C15.5 9.27614 15.2761 9.5 15 9.5C14.7239 9.5 14.5 9.27614 14.5 9C14.5 8.72386 14.7239 8.5 15 8.5C15.2761 8.5 15.5 8.72386 15.5 9ZM9.5 9C9.5 9.27614 9.27614 9.5 9 9.5C8.72386 9.5 8.5 9.27614 8.5 9C8.5 8.72386 8.72386 8.5 9 8.5C9.27614 8.5 9.5 8.72386 9.5 9Z"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def git_merge_icon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      viewBox="0 0 20 20"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M13 16C13 17.6569 14.3431 19 16 19C17.6569 19 19 17.6569 19 16C19 14.3431 17.6569 13 16 13C14.3431 13 13 14.3431 13 16ZM13 16C10.6131 16 8.32387 15.0518 6.63604 13.364C4.94821 11.6761 4 9.38695 4 7M4 7C5.65685 7 7 5.65685 7 4C7 2.34315 5.65685 1 4 1C2.34315 1 1 2.34315 1 4C1 5.65685 2.34315 7 4 7ZM4 7V19"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def close_icon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M18 6L6 18M6 6L18 18"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def menu_icon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M3 12H15M3 6H21M3 18H21"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def plus_icon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M12 5V19M5 12H19"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def check_circle_icon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M7.5 12L10.5 15L16.5 9M22 12C22 17.5228 17.5228 22 12 22C6.47715 22 2 17.5228 2 12C2 6.47715 6.47715 2 12 2C17.5228 2 22 6.47715 22 12Z"
        stroke="currentColor"
        stroke-width="1.5"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def icon_arrow_narrow_right(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 18 14"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M1 7H17M17 7L11 1M17 7L11 13"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def icon_plus(assigns) do
    ~H"""
    <svg
      class={@class}
      width={@size}
      height={@size}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M12 5V19M5 12H19"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def icon_minus(assigns) do
    ~H"""
    <svg
      class={@class}
      width={@size}
      height={@size}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M5 12H19"
        stroke="currentColor"
        stroke-width="2"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  # Taken from: https://icon-sets.iconify.design/mdi/slack/
  def icon_slack(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        fill="currentColor"
        d="M6 15a2 2 0 0 1-2 2a2 2 0 0 1-2-2a2 2 0 0 1 2-2h2zm1 0a2 2 0 0 1 2-2a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2a2 2 0 0 1-2-2zm2-8a2 2 0 0 1-2-2a2 2 0 0 1 2-2a2 2 0 0 1 2 2v2zm0 1a2 2 0 0 1 2 2a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2a2 2 0 0 1 2-2zm8 2a2 2 0 0 1 2-2a2 2 0 0 1 2 2a2 2 0 0 1-2 2h-2zm-1 0a2 2 0 0 1-2 2a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2a2 2 0 0 1 2 2zm-2 8a2 2 0 0 1 2 2a2 2 0 0 1-2 2a2 2 0 0 1-2-2v-2zm0-1a2 2 0 0 1-2-2a2 2 0 0 1 2-2h5a2 2 0 0 1 2 2a2 2 0 0 1-2 2z"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  # Taken from: https://icon-sets.iconify.design/ri/bluesky-fill/
  def icon_bluesky(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        fill="currentColor"
        d="M12 10.8c-1.087-2.114-4.046-6.053-6.798-7.995C2.566.944 1.561 1.266.902 1.565C.139 1.908 0 3.08 0 3.768c0 .69.378 5.65.624 6.479c.815 2.736 3.713 3.66 6.383 3.364q.204-.03.415-.056q-.207.033-.415.056c-3.912.58-7.387 2.005-2.83 7.078c5.013 5.19 6.87-1.113 7.823-4.308c.953 3.195 2.05 9.271 7.733 4.308c4.267-4.308 1.172-6.498-2.74-7.078a9 9 0 0 1-.415-.056q.21.026.415.056c2.67.297 5.568-.628 6.383-3.364c.246-.828.624-5.79.624-6.478c0-.69-.139-1.861-.902-2.206c-.659-.298-1.664-.62-4.3 1.24C16.046 4.748 13.087 8.687 12 10.8"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  # Taken from: https://icon-sets.iconify.design/mdi/github/
  def icon_github(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        fill="currentColor"
        d="M12 2A10 10 0 0 0 2 12c0 4.42 2.87 8.17 6.84 9.5c.5.08.66-.23.66-.5v-1.69c-2.77.6-3.36-1.34-3.36-1.34c-.46-1.16-1.11-1.47-1.11-1.47c-.91-.62.07-.6.07-.6c1 .07 1.53 1.03 1.53 1.03c.87 1.52 2.34 1.07 2.91.83c.09-.65.35-1.09.63-1.34c-2.22-.25-4.55-1.11-4.55-4.92c0-1.11.38-2 1.03-2.71c-.1-.25-.45-1.29.1-2.64c0 0 .84-.27 2.75 1.02c.79-.22 1.65-.33 2.5-.33s1.71.11 2.5.33c1.91-1.29 2.75-1.02 2.75-1.02c.55 1.35.2 2.39.1 2.64c.65.71 1.03 1.6 1.03 2.71c0 3.82-2.34 4.66-4.57 4.91c.36.31.69.92.69 1.85V21c0 .27.16.59.67.5C19.14 20.16 22 16.42 22 12A10 10 0 0 0 12 2"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  # Taken from: https://icon-sets.iconify.design/mdi/mastodon/
  def icon_mastodon(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        fill="currentColor"
        d="M20.94 14c-.28 1.41-2.44 2.96-4.97 3.26c-1.31.15-2.6.3-3.97.24c-2.25-.11-4-.54-4-.54v.62c.32 2.22 2.22 2.35 4.03 2.42c1.82.05 3.44-.46 3.44-.46l.08 1.65s-1.28.68-3.55.81c-1.25.07-2.81-.03-4.62-.5c-3.92-1.05-4.6-5.24-4.7-9.5l-.01-3.43c0-4.34 2.83-5.61 2.83-5.61C6.95 2.3 9.41 2 11.97 2h.06c2.56 0 5.02.3 6.47.96c0 0 2.83 1.27 2.83 5.61c0 0 .04 3.21-.39 5.43M18 8.91c0-1.08-.3-1.91-.85-2.56c-.56-.63-1.3-.96-2.23-.96c-1.06 0-1.87.41-2.42 1.23l-.5.88l-.5-.88c-.56-.82-1.36-1.23-2.43-1.23c-.92 0-1.66.33-2.23.96C6.29 7 6 7.83 6 8.91v5.26h2.1V9.06c0-1.06.45-1.62 1.36-1.62c1 0 1.5.65 1.5 1.93v2.79h2.07V9.37c0-1.28.5-1.93 1.51-1.93c.9 0 1.35.56 1.35 1.62v5.11H18z"
      />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def icon_peertube(assigns) do
    ~H"""
    <svg
      viewBox="0 0 24 24"
      width={@size}
      height={@size}
      class={@class}
      xmlns="http://www.w3.org/2000/svg"
    >
      <path fill="currentColor" d="m3 0v12l9-6zm0 12v12l9-6zm9-6v12l9-6z" />
    </svg>
    """
  end

  attr :size, :integer, default: @default_icon_size
  attr :class, :string, default: ""

  def icon_linkedin(assigns) do
    ~H"""
    <svg
      width={@size}
      height={@size}
      class={@class}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M20.47 1.9999H3.53C3.33958 1.99725 3.1505 2.03214 2.97356 2.10258C2.79663 2.17302 2.6353 2.27762 2.4988 2.41041C2.36229 2.5432 2.25328 2.70158 2.17799 2.87651C2.1027 3.05143 2.06261 3.23947 2.06 3.4299V20.5699C2.06261 20.7603 2.1027 20.9484 2.17799 21.1233C2.25328 21.2982 2.36229 21.4566 2.4988 21.5894C2.6353 21.7222 2.79663 21.8268 2.97356 21.8972C3.1505 21.9676 3.33958 22.0025 3.53 21.9999H20.47C20.6604 22.0025 20.8495 21.9676 21.0264 21.8972C21.2034 21.8268 21.3647 21.7222 21.5012 21.5894C21.6377 21.4566 21.7467 21.2982 21.822 21.1233C21.8973 20.9484 21.9374 20.7603 21.94 20.5699V3.4299C21.9374 3.23947 21.8973 3.05143 21.822 2.87651C21.7467 2.70158 21.6377 2.5432 21.5012 2.41041C21.3647 2.27762 21.2034 2.17302 21.0264 2.10258C20.8495 2.03214 20.6604 1.99725 20.47 1.9999ZM8.09 18.7399H5.09V9.7399H8.09V18.7399ZM6.59 8.4799C6.17626 8.4799 5.77947 8.31554 5.48691 8.02298C5.19435 7.73043 5.03 7.33363 5.03 6.9199C5.03 6.50616 5.19435 6.10937 5.48691 5.81681C5.77947 5.52425 6.17626 5.3599 6.59 5.3599C6.80969 5.33498 7.03217 5.35675 7.24287 5.42378C7.45357 5.49081 7.64774 5.60159 7.81265 5.74886C7.97757 5.89613 8.10952 6.07657 8.19987 6.27838C8.29021 6.48018 8.33692 6.69879 8.33692 6.9199C8.33692 7.141 8.29021 7.35961 8.19987 7.56141C8.10952 7.76322 7.97757 7.94366 7.81265 8.09093C7.64774 8.23821 7.45357 8.34898 7.24287 8.41601C7.03217 8.48304 6.80969 8.50481 6.59 8.4799ZM18.91 18.7399H15.91V13.9099C15.91 12.6999 15.48 11.9099 14.39 11.9099C14.0527 11.9124 13.7242 12.0182 13.4488 12.2131C13.1735 12.408 12.9645 12.6826 12.85 12.9999C12.7717 13.2349 12.7378 13.4825 12.75 13.7299V18.7299H9.75C9.75 18.7299 9.75 10.5499 9.75 9.7299H12.75V10.9999C13.0225 10.527 13.4189 10.1374 13.8964 9.8731C14.374 9.60878 14.9146 9.47975 15.46 9.4999C17.46 9.4999 18.91 10.7899 18.91 13.5599V18.7399Z"
        fill="currentColor"
      />
    </svg>
    """
  end
end
