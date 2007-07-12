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
      
      # When +convert_problematic_includes_to_joins+ is used, the column names for the JOIN will not
      # be writtten out in SQL so the JOINed tables data is not actually loaded. This wrapper adds
      # column aliases for the JOINed tables so their data is present in the result set.
      def column_aliases_with_eager_loading_from_joins(join_dependency)
        sql = column_aliases_without_eager_loading_from_joins(join_dependency)
        final_column_alias = sql.scan(/t(\d+)_r(\d+)/).last.map(&:to_i)
        @join_table_aliases_for_eager_loading.to_a.each_with_index do |join_table, i|
          join_columns = []
          Kernel.const_get(join_table[:class_name]).column_names.each_with_index do |column_name, j|
            column_alias = "t#{final_column_alias[0] + i + 1}_r#{j}"
            @join_table_aliases_for_eager_loading[i][:first_column] ||= column_alias
            join_columns << "#{join_table[:table_alias]}.#{connection.quote_column_name column_name} AS #{column_alias}"
          end
          sql = ([sql] + join_columns) * ', '
        end
        sql
      end
      alias_method_chain(:column_aliases, :eager_loading_from_joins)
      
      # Overwrite that passes the information about associations that were converted to JOIN fragments
      # on to the join dependency object so it can eager load the data successfully. Anything removed from
      # the <tt>:includes</tt> option will not be present in the join dependency object's associations and
      # will therefore not be eager loaded unless we manually force the association back in.
      def find_with_associations(options = {})
        catch :invalid_query do
          join_dependency = JoinDependency.new(self, merge_includes(scope(:find, :include), options[:include]), options[:joins])
          rows = select_all_rows(options, join_dependency)
          return join_dependency.instantiate(rows, @join_table_aliases_for_eager_loading)
        end
        []
      end
      
      # Deals with exceptions thrown by duplicate table names. Any includes that are HABTM are stripped out
      # and rewritten as joins with numeric table aliases. Information about the join tables is kept around in an
      # instance variable so it can be passed on when constructing SQL statements and convering these to objects.
      def convert_problematic_includes_to_joins(options)
        includes, joins, i = [], [options[:joins].to_s], 0
        @join_table_aliases_for_eager_loading ||= []
        options[:include].to_a.each do |inc|
          if inc.is_a?(Hash)
            includes << inc
            next
          end
          association = reflect_on_association(inc)
          i += 1
          
          if association.macro == :has_and_belongs_to_many
            fragment = join_fragment_for_has_and_belongs_to_many_association(association, i)
          elsif association.macro == :has_many and association.options[:through]
            fragment = join_fragment_for_has_many_through_association(association, i)
          else
            includes << inc
          end
          
          if fragment
            joins << fragment.first
            @join_table_aliases_for_eager_loading << { :class_name => fragment[1],
                :table_alias => fragment[2], :association => association.name }
          end
        end
        options[:include] = includes.blank? ? nil : includes
        options[:joins] = joins * ' '
      end
      
      # Returns a JOIN statement for a HABTM association, with the given numeric index used for table aliasing,
      # and the class name and table alias used for the association - this is used to manually load column names for eager loading
      def join_fragment_for_has_and_belongs_to_many_association(association, i = 1)
        association = reflect_on_association(association) unless association.is_a?(ActiveRecord::Reflection::AssociationReflection)
        return nil unless association and association.macro == :has_and_belongs_to_many
        
        assoc_class = Kernel.const_get(association.class_name)
        opts = association.options
        
        join_table = opts[:join_table]
        join_table_alias = "ibd_join_table_#{i}"
        join_foreign_key = opts[:foreign_key]
        assoc_table = assoc_class.table_name
        assoc_table_alias = "ibd_assoc_table_#{i}"
        assoc_primary_key = assoc_class.primary_key
        assoc_foreign_key = opts[:association_foreign_key]
        
        sql = <<-end_of_sql
          LEFT OUTER JOIN #{join_table} AS #{join_table_alias}
          ON #{join_table_alias}.#{join_foreign_key} = #{table_name}.#{primary_key}
          LEFT OUTER JOIN #{assoc_table} AS #{assoc_table_alias}
          ON #{assoc_table_alias}.#{assoc_primary_key} = #{join_table_alias}.#{assoc_foreign_key}
        end_of_sql
        [sql.gsub(/\n/, '').gsub(/\s+/, ' '), association.class_name, assoc_table_alias]
      end
      
      # Returns a JOIN statement for a <tt>has_many :through</tt> association, with the given numeric index used for table aliasing,
      # and the class name and table alias used for the association - this is used to manually load column names for eager loading
      def join_fragment_for_has_many_through_association(association, i = 1)
        association = reflect_on_association(association) unless association.is_a?(ActiveRecord::Reflection::AssociationReflection)
        return nil unless association and association.macro == :has_many and association.options[:through]
        
        through_assoc = reflect_on_association(association.options[:through])
        through_class = Kernel.const_get(through_assoc.class_name)
        source_assoc = through_class.reflect_on_association(association.name)
        source_assoc ||= through_class.reflect_on_association(association.name.to_s.singularize.intern)
        source_class = Kernel.const_get(source_assoc.class_name)
        
        join_table = through_class.table_name
        join_table_alias = "ibd_join_table_#{i}"
        join_foreign_key = through_assoc.options[:foreign_key]
        assoc_table = source_class.table_name
        assoc_table_alias = "ibd_assoc_table_#{i}"
        assoc_primary_key = source_class.primary_key
        assoc_foreign_key = source_assoc.options[:foreign_key]
        
        sql = <<-end_of_sql
          LEFT OUTER JOIN #{join_table} AS #{join_table_alias}
          ON #{join_table_alias}.#{join_foreign_key} = #{table_name}.#{primary_key}
          LEFT OUTER JOIN #{assoc_table} AS #{assoc_table_alias}
          ON #{assoc_table_alias}.#{assoc_primary_key} = #{join_table_alias}.#{assoc_foreign_key}
        end_of_sql
        [sql.gsub(/\n/, '').gsub(/\s+/, ' '), source_assoc.class_name, assoc_table_alias]
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
  
  module Associations #:nodoc:
    module ClassMethods #:nodoc:
      class JoinDependency
      
        # Wrapper for +instantiate+, which accepts a set of join table information and adds
        # it into the JoinDependency's properties so that the join table data gets eager loaded.
        def instantiate_with_reloading_dropped_associations(rows, join_tables = nil)
          join_tables.to_a.each do |join_table|
            next unless rows.first and rows.first.keys.include?(join_table[:first_column])
            @associations << join_table[:association]
            reflection = join_base.reflections[join_table[:association]]
            @reflections << reflection
            @joins << JoinAssociation.new(reflection, self, join_base)
          end
          instantiate_without_reloading_dropped_associations(rows)
        end
        alias_method_chain(:instantiate, :reloading_dropped_associations)
      
      end
    end
  end
end
