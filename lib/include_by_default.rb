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
      
      # Wrapper for +find_initial+
      def find_initial_with_default_includes(options)
        add_default_includes(options)
        find_initial_without_default_includes(options)
      rescue ActiveRecord::StatementInvalid
        convert_problematic_includes_to_joins(options)
        find_initial_without_default_includes(options)
      end
      alias_method_chain(:find_initial, :default_includes)
      
      # Wrapper for +find_every+
      def find_every_with_default_includes(options)
        add_default_includes(options)
        find_every_without_default_includes(options)
      rescue ActiveRecord::StatementInvalid
        convert_problematic_includes_to_joins(options)
        find_every_without_default_includes(options)
      end
      alias_method_chain(:find_every, :default_includes)
      
      # Wrapper for +find_from_ids+
      def find_from_ids_with_default_includes(ids, options)
        add_default_includes(options)
        find_from_ids_without_default_includes(ids, options)
      rescue ActiveRecord::StatementInvalid
        convert_problematic_includes_to_joins(options)
        find_from_ids_without_default_includes(ids, options)
      end
      alias_method_chain(:find_from_ids, :default_includes)
      
      # Adds the default includes onto the <tt>:options</tt> hash if no includes are specified
      def add_default_includes(options)
        return unless options[:include].nil? and !default_includes.blank?
        options[:include] = default_includes
      end
      
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
          
          if association.macro.to_s == 'has_and_belongs_to_many'
            assoc_class = Kernel.const_get(association.class_name)
            opts = association.options
            joins << <<-end_of_sql
              LEFT OUTER JOIN #{opts[:join_table]} AS ibd_join_table_#{i}
              ON ibd_join_table_#{i}.#{opts[:foreign_key]} =
                  #{table_name}.#{primary_key}
              LEFT OUTER JOIN #{assoc_class.table_name} AS ibd_assoc_table_#{i}
              ON ibd_assoc_table_#{i}.#{assoc_class.primary_key} =
                  ibd_join_table_#{i}.#{opts[:association_foreign_key]}
            end_of_sql
          
          elsif association.macro.to_s == 'has_many' and association.options[:through]
            through_assoc = reflect_on_association(association.options[:through])
            through_class = Kernel.const_get(through_assoc.class_name)
            source_assoc = through_class.reflect_on_association(association.name)
            source_assoc ||= through_class.reflect_on_association(association.name.to_s.singularize.to_sym)
            source_class = Kernel.const_get(source_assoc.class_name)
            joins << <<-end_of_sql
              LEFT OUTER JOIN #{through_class.table_name} AS ibd_join_table_#{i}
              ON ibd_join_table_#{i}.#{through_assoc.options[:foreign_key]} =
                  #{table_name}.#{primary_key}
              LEFT OUTER JOIN #{source_class.table_name} AS ibd_assoc_table_#{i}
              ON ibd_assoc_table_#{i}.#{source_class.primary_key} =
                  ibd_join_table_#{i}.#{source_assoc.options[:foreign_key]}
            end_of_sql
          
          else
            includes << inc
          end
        end
        options[:include] = includes.blank? ? nil : includes
        options[:joins] = joins * ' '
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
