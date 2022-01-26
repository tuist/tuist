module SimCtl
  module Xcode
    class Path
      class << self
        def home
          @home ||= `xcode-select -p`.chomp
        end

        def sdk_root
          File.join(home, 'Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk')
        end

        def runtime_profiles
          if Xcode::Version.gte? '11.0'
            File.join(home, 'Platforms/iPhoneOS.platform/Library/Developer/CoreSimulator/Profiles/Runtimes/')
          elsif Xcode::Version.gte? '9.0'
            File.join(home, 'Platforms/iPhoneOS.platform/Developer/Library/CoreSimulator/Profiles/Runtimes/')
          else
            File.join(home, 'Platforms/iPhoneSimulator.platform/Developer/Library/CoreSimulator/Profiles/Runtimes/')
          end
        end
      end
    end
  end
end
