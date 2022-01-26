module SimCtl
  class Command
    module Privacy
      # Change privacy settings
      #
      # @param device [SimCtl::Device] the device
      # @param action [String] grant, revoke, reset
      # @param service [String] all, calendar, contacts-limited, contacts, location,
      #                location-always, photos-add, photos, media-library, microphone,
      #                motion, reminders, siri
      # @param bundle [String] bundle identifier
      # @return [void]
      def privacy(device, action, service, bundle)
        unless Xcode::Version.gte? '11.4'
          raise UnsupportedCommandError, 'Needs at least Xcode 11.4'
        end
        Executor.execute(command_for('privacy', device.udid, action, service, bundle))
      end
    end
  end
end
