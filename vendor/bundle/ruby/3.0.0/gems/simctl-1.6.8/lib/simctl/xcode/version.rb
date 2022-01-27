module SimCtl
  module Xcode
    class Version
      class << self
        def gte?(version)
          @version ||= Gem::Version.new(`xcodebuild -version`.scan(/Xcode (\S+)/).flatten.first)

          @version >= Gem::Version.new(version)
        end
      end
    end
  end
end
