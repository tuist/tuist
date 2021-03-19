# frozen_string_literal: true
module Fourier
  module Commands
    class Update < Base
      desc "swiftlint", "Update the vendored swiftlint binary"
      def swiftlint
        Services::Update::Swiftlint.call
      end

      desc "xcbeautify", "Update the vendored xcbeautify binary"
      def xcbeautify
        Services::Update::Xcbeautify.call
      end

      desc "swiftdoc", "Update the vendored swiftdoc binary"
      def swiftdoc
        Services::Update::Swiftdoc.call
      end
    end
  end
end
