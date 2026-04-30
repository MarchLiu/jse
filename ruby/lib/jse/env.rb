module JSE
  class Env
    def initialize(parent: nil)
      @parent = parent
      @bindings = {}
      @current_meta = {}
    end

    attr_reader :parent

    def resolve(name)
      if @bindings.key?(name)
        @bindings[name]
      elsif @parent
        @parent.resolve(name)
      end
    end

    def register(name, value)
      if @bindings.key?(name)
        raise "Symbol '#{name}' already exists in current scope"
      end
      @bindings[name] = value
    end

    def set(name, value)
      @bindings[name] = value
    end

    def exists?(name)
      return true if @bindings.key?(name)
      return @parent.exists?(name) if @parent
      false
    end

    def load(mod)
      mod.each { |name, functor| register(name, functor) }
    end

    def eval(node)
      if node.respond_to?(:apply)
        node.apply(self)
      else
        node
      end
    end

    def set_meta(dict)
      @current_meta = dict
    end

    def get_meta
      @current_meta
    end

    def clear_meta
      @current_meta = {}
    end
  end
end
