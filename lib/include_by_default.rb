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
          unless association.macro.to_s == 'has_and_belongs_to_many'
            includes << inc
            next
          end
          i += 1
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
        end
        options[:include] = includes.blank? ? nil : includes
        options[:joins] = joins * ' '
      end
      
      # Rewrite of the standard <tt>add_joins!</tt> method that adds support for
      # the <tt>:joins</tt> option on finds scoped by HABTM associations. Required
      # for +convert_problematic_includes_to_joins+ to work.
      def add_joins!(sql, options, scope = :auto)
        scope = scope(:find) if :auto == scope
        join = [(scope && scope[:joins]), options[:joins]].uniq * " "
        sql << " #{join} " if join
      end
    
    end
  end
end
