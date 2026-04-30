require "json"

module JSE
  module Functors
    module SQL
      QUERY_FIELDS = "subject, predicate, object, meta"

      # ============================================================
      # Subquery detection
      # ============================================================

      def self.subquery?(value)
        return false unless value.is_a?(Array) && !value.empty?
        value.all? { |item| item.is_a?(Array) && !item.empty? && item[0].is_a?(String) && item[0].start_with?("$") }
      end

      # ============================================================
      # String utilities
      # ============================================================

      def self.symbol_str?(s)
        return false if s == "$*"
        s.is_a?(String) && s.start_with?("$") && !s.start_with?("$$")
      end

      def self.escaped_str?(s)
        s.is_a?(String) && s.start_with?("$$")
      end

      def self.sql_quote(s)
        "'#{s.gsub("'", "''")}'"
      end

      def self.parenthesized?(s)
        return false unless s.start_with?("(")
        depth = 0
        s.each_char.with_index do |c, i|
          depth += 1 if c == "("
          depth -= 1 if c == ")"
          return i == s.length - 1 if depth == 0
        end
        false
      end

      # ============================================================
      # Expression renderer
      # ============================================================

      def self.render_expr(value)
        case value
        when nil then "null"
        when true then "true"
        when false then "false"
        when Integer, Float then value.to_s
        when String
          if escaped_str?(value)
            sql_quote("$#{value[2..]}")
          elsif symbol_str?(value)
            value[1..]
          else
            sql_quote(value)
          end
        when Array
          return "" if value.empty?
          if subquery?(value)
            render_subquery(value)
          elsif value[0].is_a?(String) && value[0].start_with?("$") && !value[0].start_with?("$$")
            render_list_expr(value)
          else
            value.map { |v| render_expr(v) }.join(", ")
          end
        when Hash
          render_dict(value)
        else
          value.to_s
        end
      end

      def self.render_dict(dict)
        return "" if dict.empty?
        op_keys = dict.keys.select { |k| symbol_str?(k) }
        if op_keys.empty? || op_keys.length > 1
          return dict.map { |k, v| "#{render_key(k)} = #{render_expr(v)}" }.join(", ")
        end
        op = op_keys.first
        return %("#{dict[op]}") if op == "$symbol"
        render_expr(dict[op])
      end

      def self.render_key(key)
        if escaped_str?(key)
          "$#{key[2..]}"
        elsif symbol_str?(key)
          key[1..]
        else
          key.to_s
        end
      end

      def self.render_list_expr(lst)
        return "" if lst.empty?
        op = lst[0]
        return lst.map { |v| render_expr(v) }.join(", ") unless op.is_a?(String)
        return lst.map { |v| render_expr(v) }.join(", ") if op.start_with?("$$")
        render_func(op, lst[1..])
      end

      # ============================================================
      # Function dispatch
      # ============================================================

      def self.render_func(op, args)
        case op
        when "$as"   then render_as(args)
        when "$count" then render_count(args)
        when "$sum"   then render_agg("sum", args)
        when "$avg"   then render_agg("avg", args)
        when "$max"   then render_agg("max", args)
        when "$min"   then render_agg("min", args)
        when "$eq"    then render_binary("=", args)
        when "$ne"    then render_binary("!=", args)
        when "$gt"    then render_binary(">", args)
        when "$gte"   then render_binary(">=", args)
        when "$lt"    then render_binary("<", args)
        when "$lte"   then render_binary("<=", args)
        when "$like"  then render_binary("like", args)
        when "$is"    then render_is(args)
        when "$is-not" then render_is_not(args)
        when "$and"   then render_logical("and", args)
        when "$or"    then render_logical("or", args)
        when "$in"    then render_in(args)
        when "$case"  then render_case(args)
        when "$excluded" then render_excluded(args)
        else
          "#{op[1..]}(#{args.map { |a| render_expr(a) }.join(", ")})"
        end
      end

      def self.render_as(args)
        return "" if args.length < 2
        expr = render_expr(args[0])
        als = render_expr(args[1])
        if args[0].is_a?(Array)
          "(#{expr}) as #{als}"
        elsif args[0].is_a?(String) && symbol_str?(args[0])
          "#{args[0][1..]} as #{als}"
        else
          "#{expr} as #{als}"
        end
      end

      def self.render_count(args)
        return "count(*)" if args.empty?
        return "count(*)" if args[0].is_a?(String) && args[0] == "$*"
        "count(#{render_expr(args[0])})"
      end

      def self.render_agg(fn, args)
        return "#{fn}(*)" if args.empty?
        "#{fn}(#{render_expr(args[0])})"
      end

      def self.render_binary(op, args)
        return "" if args.length < 2
        "#{render_expr(args[0])} #{op} #{render_expr(args[1])}"
      end

      def self.render_is(args)
        return "" if args.length < 2
        left = render_expr(args[0])
        return "#{left} is null" if args[1].nil?
        "#{left} is #{render_expr(args[1])}"
      end

      def self.render_is_not(args)
        return "" if args.length < 2
        left = render_expr(args[0])
        return "#{left} is not null" if args[1].nil?
        "#{left} is not #{render_expr(args[1])}"
      end

      def self.render_logical(op, args)
        return op == "and" ? "true" : "false" if args.empty?
        parts = args.map do |a|
          r = render_expr(a)
          parenthesized?(r) ? r : "(#{r})"
        end
        "(#{parts.join(" #{op} ")})"
      end

      def self.render_in(args)
        return "" if args.length < 2
        col = render_expr(args[0])
        val = args[1]
        if val.is_a?(Array)
          if subquery?(val)
            "#{col} in (#{render_subquery(val)})"
          else
            "#{col} in (#{val.map { |v| render_expr(v) }.join(", ")})"
          end
        else
          "#{col} in (#{render_expr(val)})"
        end
      end

      def self.render_case(args)
        parts = ["case"]
        else_val = nil
        args.each do |arg|
          if arg.is_a?(Array) && !arg.empty? && arg[0].is_a?(String)
            if arg[0] == "$when" && arg.length >= 3
              parts << "when #{render_expr(arg[1])} then #{render_expr(arg[2])}"
            elsif arg[0] == "$else" && arg.length >= 2
              else_val = render_expr(arg[1])
            end
          end
        end
        parts << "else #{else_val}" if else_val
        parts << "end"
        parts.join(" ")
      end

      def self.render_excluded(args)
        return "excluded" if args.empty?
        "excluded.#{render_expr(args[0])}"
      end

      # ============================================================
      # Subquery rendering
      # ============================================================

      def self.render_subquery(clauses)
        clauses.select { |c| c.is_a?(Array) }
               .map { |c| render_clause(c) }
               .reject(&:empty?)
               .join(" ")
      end

      # ============================================================
      # Clause renderer
      # ============================================================

      def self.render_clause(clause)
        return "" if clause.empty?
        kw = clause[0]
        return "" unless kw.is_a?(String) && kw.start_with?("$")
        args = clause[1..]

        case kw
        when "$select"
          "select #{args.map { |a| render_expr(a) }.join(", ")}"
        when "$from"
          "from #{render_table(args)}"
        when "$join"
          "join #{render_join(args)}"
        when "$left-join"
          "left join #{render_join(args)}"
        when "$right-join"
          "right join #{render_join(args)}"
        when "$full-join"
          "full join #{render_join(args)}"
        when "$cross-join"
          "cross join #{render_table(args)}"
        when "$where"
          args.empty? ? "" : "where #{render_expr(args[0])}"
        when "$group-by"
          args.empty? ? "" : "group by #{render_expr(args[0])}"
        when "$having"
          args.empty? ? "" : "having #{render_expr(args[0])}"
        when "$order-by"
          render_order_by(args)
        when "$limit"
          args.empty? ? "" : "limit #{render_expr(args[0])}"
        when "$offset"
          args.empty? ? "" : "offset #{render_expr(args[0])}"
        when "$with"
          render_with(args)
        when "$insert-into"
          render_insert_into(args)
        when "$values"
          "values (#{args.map { |a| render_expr(a) }.join(", ")})"
        when "$update"
          "update #{render_table(args)}"
        when "$set"
          render_set(args)
        when "$delete-from"
          "delete from #{render_table(args)}"
        when "$on-conflict"
          args.empty? ? "" : "on conflict (#{render_expr(args[0])})"
        when "$do-update"
          render_do_update(args)
        else
          kw[1..]
        end
      end

      def self.render_table(args)
        return "" if args.empty?
        first = args[0]
        if first.is_a?(Array) && !first.empty? && first[0] == "$as"
          render_list_expr(first)
        else
          render_expr(first)
        end
      end

      def self.render_join(args)
        return "" if args.empty?
        table = render_expr(args[0])
        return "#{table} on #{render_expr(args[1])}" if args.length >= 2
        table
      end

      def self.render_order_by(args)
        return "" if args.empty?
        col = render_expr(args[0])
        if args.length >= 2 && args[1].is_a?(String) && symbol_str?(args[1])
          dir = args[1][1..]
          return "order by #{col} #{dir}" if %w[desc asc].include?(dir)
        end
        return "order by #{col} #{render_expr(args[1])}" if args.length >= 2
        "order by #{col}"
      end

      def self.render_with(args)
        return "" if args.empty? || !args[0].is_a?(Hash)
        cte_defs = args[0]
        cte_parts = cte_defs.map do |cte_name_key, cte_clauses|
          cte_name = symbol_str?(cte_name_key) ? cte_name_key[1..] : cte_name_key
          next unless cte_clauses.is_a?(Array) && !cte_clauses.empty?
          inner = cte_clauses.map { |c| c.is_a?(Array) ? render_clause(c) : "" }.reject(&:empty?).join(" ")
          "#{cte_name} as (#{inner})"
        end.compact
        return "" if cte_parts.empty?
        "with #{cte_parts.join(",\n")}"
      end

      def self.render_insert_into(args)
        return "insert into" if args.empty?
        table = render_expr(args[0])
        if args.length > 1
          cols = args[1..].map { |a| render_expr(a) }.join(", ")
          "insert into #{table} (#{cols})"
        else
          "insert into #{table}"
        end
      end

      def self.render_set(args)
        return "" if args.empty? || !args[0].is_a?(Hash)
        parts = args[0].map { |col, val| "#{render_key(col)} = #{render_expr(val)}" }
        "set #{parts.join(", ")}"
      end

      def self.render_do_update(args)
        return "" if args.empty? || !args[0].is_a?(Hash)
        parts = args[0].map { |col, val| "#{render_key(col)} = #{render_expr(val)}" }
        "do update set #{parts.join(", ")}"
      end

      # ============================================================
      # $sql functor
      # ============================================================

      def self.sql_fn(env, *args)
        return "" if args.empty?
        data = args[0]
        return "" unless data.is_a?(Array) && !data.empty?

        parts = []
        pending_values = []

        flush_values = -> {
          unless pending_values.empty?
            rows = pending_values.map { |vlist|
              "(#{vlist.map { |v| render_expr(v) }.join(", ")})"
            }
            parts << "values #{rows.join(", ")}"
            pending_values.clear
          end
        }

        data.each do |item|
          next unless item.is_a?(Array) && !item.empty?
          if item[0] == "$values"
            pending_values << item[1..]
            next
          end
          flush_values.call
          rendered = render_clause(item)
          parts << rendered unless rendered.empty?
        end
        flush_values.call

        parts.join("\n")
      end

      # ============================================================
      # Legacy $query / $pattern (backward compatibility)
      # ============================================================

      def self.pattern_to_triple(subject, predicate, object)
        if subject == "$*" && object == "$*"
          [predicate]
        else
          [subject, predicate, object]
        end
      end

      def self.triple_to_sql_condition(triple)
        inner = triple.map { |s| %("#{s}") }.join(",")
        json = %({"triple":[#{inner}]})
        escaped = json.gsub("'", "''")
        "meta @> '#{escaped}'"
      end

      def self.pattern_fn(env, *args)
        raise "$pattern requires (subject, predicate, object)" if args.length < 3
        subj, pred, obj = args[0..2].map { |a| env.eval(a) }
        triple = pattern_to_triple(subj, pred, obj)
        triple_to_sql_condition(triple)
      end

      def self.legacy_and(env, *args)
        args.map { |a| env.eval(a).to_s }.join(" and ")
      end

      def self.wildcard_fn(_env, *_args)
        "*"
      end

      LOCAL_SQL_FUNCTORS = {
        "$pattern" => method(:pattern_fn),
        "$and"     => method(:legacy_and),
        "$*"       => method(:wildcard_fn),
      }.freeze

      def self.query_fn(env, *args)
        raise "$query expects a condition expression" if args.empty?
        local = Env.new(parent: env)
        local.load(LOCAL_SQL_FUNCTORS)
        parser = Parser.new(local)
        condition = parser.parse(args)
        where = condition.apply(local)
        where = where.is_a?(Array) ? where.first.to_s : where.to_s
        "select #{QUERY_FIELDS} \nfrom statement \nwhere \n    #{where} \noffset 0\nlimit 100 \n"
      end

      SQL_FUNCTORS = {
        "$sql"   => method(:sql_fn),
        "$query" => method(:query_fn),
      }.freeze
    end
  end
end
