# frozen_string_literal: true
module Fourier
  module Services
    module Test
      module Tuist
        class Support < Base
          def call
            Dir.chdir(Constants::ROOT_DIRECTORY) do
              Utilities::System.tuist("test", "TuistSupport")
            end
          end
        end
      end
    end
  end
end
