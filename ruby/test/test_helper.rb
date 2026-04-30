require "jse"
require "minitest/autorun"

module JSE
  module TestHelper
    def engine_with_functors(*mods)
      env = Env.new
      mods.each { |m| env.load(m) }
      Engine.new(env)
    end

    def engine_with_sql
      engine_with_functors(JSE::Functors::SQL::SQL_FUNCTORS)
    end
  end
end
