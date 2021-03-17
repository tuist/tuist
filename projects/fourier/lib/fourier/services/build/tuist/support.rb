# frozen_string_literal: true
module Fourier
  module Services
    module Build
      module Tuist
        class Support < Base
          def call
            Dir.chdir(Constants::ROOT_DIRECTORY) do
              Utilities::System.tuist("build", "TuistSupport")
            end
          end
        end
      end
    end
  end
end
