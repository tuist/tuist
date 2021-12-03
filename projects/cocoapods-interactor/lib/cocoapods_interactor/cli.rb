# frozen_string_literal: true

require "thor"

module CocoaPodsInteractor
  class CLI < Thor
    desc "install PATH", "Runs 'pod install' in the given directory. The directory must contain a Podfile."
    def install(path)
      Services::Install.call(path: path)
    end

    desc "update PATH", "Runs 'pod update' in the given directory. The directory must contain a Podfile."
    def update(path)
      Services::Update.call(path: path)
    end
  end
end
