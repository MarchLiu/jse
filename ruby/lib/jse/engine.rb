module JSE
  class Engine
    def initialize(env)
      @env = env
      @parser = Parser.new(env)
    end

    attr_reader :env

    def execute(expr)
      ast = @parser.parse(expr)
      @env.eval(ast)
    end

    def self.with_env
      new(Env.new)
    end
  end
end
