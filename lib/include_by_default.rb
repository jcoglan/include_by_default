module ActiveRecord #:nodoc:
  class Base
    class << self
    
      # Specifies that certain associations should be eager loaded by default on all
      # +find+ operations. Takes its arguments in the same way as the <tt>:include</tt>
      # option for the +find+ method.
      def include_by_default(*args)
        write_inheritable_attribute("include_by_default", args || [])
      end
      
      # Returns the default set of <tt>:includes</tt> used for +find+ operations.
      def default_includes
        read_inheritable_attribute("include_by_default").to_a
      end
      
    private
      
      # Wrapper for +find_every+ - all other finders are routed through this method.
      def find_every_with_default_includes(options)
        add_default_includes(options)
        find_every_without_default_includes(options)
      rescue ActiveRecord::StatementInvalid
        convert_problematic_includes_to_joins(options)
        find_every_without_default_includes(options)
      end
      alias_method_chain(:find_every, :default_includes)
      
      # Adds the default includes onto the <tt>:options</tt> hash if no includes are specified
      def add_default_includes(options)
        return unless options[:include].nil? and !default_includes.blank?
        options[:include] = default_includes
      end
      
      # Wrapper for <tt>using_limitable_reflections?</tt>, so that it remembers the state of play before troublesome
      # includes are converted to join fragments. To get back correct result set sizes when using <tt>include</tt> with
      # <tt>:limit</tt>, you'll need to make sure you include at least one +has_many+ or +has_and_belongs_to_many+ association.
      # You'll only run into this bug when using +find+ scoped by a HABTM association with duplicate links in the DB.
      # See this Rails ticket: http://dev.rubyonrails.org/ticket/8947
      def using_limitable_reflections_with_duplicate_alias_exception_catching?(reflections)
        return @cached_using_limitable_reflections unless @cached_using_limitable_reflections.nil?
        @cached_using_limitable_reflections ||= using_limitable_reflections_without_duplicate_alias_exception_catching?(reflections)
      end
      alias_method(:using_limitable_reflections_without_duplicate_alias_exception_catching?, :using_limitable_reflections?)
      alias_method(:using_limitable_reflections?, :using_limitable_reflections_with_duplicate_alias_exception_catching?)
      
      # Deals with exceptions thrown by duplicate table names. Any includes that are
      # HABTM are stripped out and rewritten as joins with numeric table aliases
      def convert_problematic_includes_to_joins(options)
        includes, joins, i = [], [options[:joins].to_s], 0
        options[:include].to_a.each do |inc|
          if inc.is_a?(Hash)
            includes << inc
            next
          end
          association = reflect_on_association(inc)
          i += 1
          if association.macro == :has_and_belongs_to_many
            joins << join_fragment_for_has_and_belongs_to_many_association(association, i)
          elsif association.macro == :has_many and association.options[:through]
            joins << join_fragment_for_has_many_through_association(association, i)
          else
            includes << inc
          end
        end
        options[:include] = includes.blank? ? nil : includes
        options[:joins] = joins * ' '
      end
      
      # Returns a JOIN statement for a HABTM association, with the given numeric index used for table aliasing
      def join_fragment_for_has_and_belongs_to_many_association(association, i = 1)
        association = reflect_on_association(association) unless association.is_a?(ActiveRecord::Reflection::AssociationReflection)
        return nil unless association and association.macro == :has_and_belongs_to_many
        assoc_class = Kernel.const_get(association.class_name)
        opts = association.options
        sql = <<-end_of_sql
          LEFT OUTER JOIN #{opts[:join_table]} AS ibd_join_table_#{i}
          ON ibd_join_table_#{i}.#{opts[:foreign_key]} =
              #{table_name}.#{primary_key}
          LEFT OUTER JOIN #{assoc_class.table_name} AS ibd_assoc_table_#{i}
          ON ibd_assoc_table_#{i}.#{assoc_class.primary_key} =
              ibd_join_table_#{i}.#{opts[:association_foreign_key]}
        end_of_sql
        sql.gsub(/\n/, '').gsub(/\s+/, ' ')
      end
      
      # Returns a JOIN statement for a <tt>has_many :through</tt> association, with the given numeric index used for table aliasing
      def join_fragment_for_has_many_through_association(association, i = 1)
        association = reflect_on_association(association) unless association.is_a?(ActiveRecord::Reflection::AssociationReflection)
        return nil unless association and association.macro == :has_many and association.options[:through]
        through_assoc = reflect_on_association(association.options[:through])
        through_class = Kernel.const_get(through_assoc.class_name)
        source_assoc = through_class.reflect_on_association(association.name)
        source_assoc ||= through_class.reflect_on_association(association.name.to_s.singularize.to_sym)
        source_class = Kernel.const_get(source_assoc.class_name)
        sql = <<-end_of_sql
          LEFT OUTER JOIN #{through_class.table_name} AS ibd_join_table_#{i}
          ON ibd_join_table_#{i}.#{through_assoc.options[:foreign_key]} =
              #{table_name}.#{primary_key}
          LEFT OUTER JOIN #{source_class.table_name} AS ibd_assoc_table_#{i}
          ON ibd_assoc_table_#{i}.#{source_class.primary_key} =
              ibd_join_table_#{i}.#{source_assoc.options[:foreign_key]}
        end_of_sql
        sql.gsub(/\n/, '').gsub(/\s+/, ' ')
      end
      
      # Rewrite of the standard <tt>add_joins!</tt> method that adds support for
      # the <tt>:joins</tt> option on finds scoped by HABTM associations. Required
      # for +convert_problematic_includes_to_joins+ to work.
      def add_joins!(sql, options, scope = :auto)
        scope = scope(:find) if :auto == scope
        join = scope && scope[:joins]
        scope_tables = table_aliases_from_join_statement(join)
        if options[:joins]
          option_tables = table_aliases_from_join_statement(options[:joins])
          join = "#{join.to_s} #{options[:joins]}" unless option_tables.map { |t| scope_tables.include?(t) }.include?(true)
        end
        sql << " #{join} " if join
      end
      
      # Returns the table names/aliases used in a JOIN SQL fragment. For each table used,
      # this method returns its alias if it is given one using AS, and its real name otherwise.
      def table_aliases_from_join_statement(str)
        return [] if str.blank?
        return str.scan(/JOIN\s+(`[^`]`|\S+)(?:\s+AS\s+(`[^`]`|\S+))?/i).collect do |name|
          (name[1] || name[0]).gsub(/^`(.*)`$/, '\1')
        end
      end
    
    end
  end
end
