# frozen_string_literal: true

require "thor"

module CocoaPodsInteractor
  module Services
    autoload :Base, "cocoapods_interactor/services/base"
    autoload :Install, "cocoapods_interactor/services/install"
    autoload :Update, "cocoapods_interactor/services/update"
  end
end
