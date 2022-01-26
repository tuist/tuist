require 'cfpropertylist'

module SimCtl
  class DeviceSettings
    attr_reader :path

    def initialize(path)
      @path = path
    end

    # Disables the keyboard helpers
    #
    # @return [void]
    def disable_keyboard_helpers
      edit_plist(path.preferences_plist) do |plist|
        plist['DidShowContinuousPathIntroduction'] = true
        %w[
          KeyboardAllowPaddle
          KeyboardAssistant
          KeyboardAutocapitalization
          KeyboardAutocorrection
          KeyboardCapsLock
          KeyboardCheckSpelling
          KeyboardPeriodShortcut
          KeyboardPrediction
          KeyboardShowPredictionBar
        ].each do |key|
          plist[key] = false
        end
      end
    end

    # Updates hardware keyboard settings
    #
    # @param enabled value to replace
    # @return [vod]
    def update_hardware_keyboard(enabled)
      edit_plist(path.preferences_plist) do |plist|
        plist['AutomaticMinimizationEnabled'] = enabled
      end
    end

    def edit_plist(path)
      plist = File.exist?(path) ? CFPropertyList::List.new(file: path) : CFPropertyList::List.new
      content = CFPropertyList.native_types(plist.value) || {}
      yield content
      plist.value = CFPropertyList.guess(content)
      plist.save(path, CFPropertyList::List::FORMAT_BINARY)
    end

    # Sets the device language
    #
    # @return [void]
    def set_language(language)
      edit_plist(path.global_preferences_plist) do |plist|
        key = 'AppleLanguages'
        plist[key] = [] unless plist.key?(key)
        plist[key].unshift(language).uniq!
      end
    end

    # Sets the device locale
    #
    # @return [void]
    def set_locale(locale)
      edit_plist(path.global_preferences_plist) do |plist|
        plist['AppleLocale'] = locale
      end
    end
  end
end
