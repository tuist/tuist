require '__app__'

module __App__
  module EntryPoint
    def self.call(args)
      cmd, command_name, args = __App__::Resolver.call(args)
      __App__::Executor.call(cmd, command_name, args)
    end
  end
end
