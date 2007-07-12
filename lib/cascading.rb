module ActiveRecord #:nodoc:
  class Base
    class << self
    
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
    
    end
  end
end
