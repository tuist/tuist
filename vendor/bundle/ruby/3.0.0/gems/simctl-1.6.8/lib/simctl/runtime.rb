require 'naturally'
require 'simctl/object'

module SimCtl
  class Runtime < Object
    extend Gem::Deprecate

    attr_reader :buildversion, :identifier, :is_available, :name, :type, :version

    def initialize(args)
      args['is_available'] = args.delete('isAvailable')
      super
    end

    def availability
      is_available
    end
    deprecate :availability, :is_available, 2020, 8

    def type
      @type ||= name.split("\s").first.downcase.to_sym
    end

    def ==(other)
      return false if other.nil?
      return false unless other.is_a? Runtime
      other.identifier == identifier
    end

    # Returns the latest available runtime
    #
    # @param name [String] type (ios, watchos, tvos)
    # @return [SimCtl::Runtime] the latest available runtime
    def self.latest(type)
      Naturally.sort_by(SimCtl.list_runtimes.where(name: /#{type}/i), :version).last
    end
  end
end
