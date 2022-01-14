# frozen_string_literal: true

module Fourier
  module Services
    module Build
      module Tuist
        class Support < Base
          attr_reader :source

          def initialize(source: false)
            @source = source
          end

          def call
            Utilities::System.tuist("build", "TuistSupport", source: source)
          end
        end
      end
    end
  end
end
