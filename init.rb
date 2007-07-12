require File.dirname(__FILE__) + '/lib/class_methods'
require File.dirname(__FILE__) + '/lib/cascading'
require File.dirname(__FILE__) + '/lib/sql_fragments'
require File.dirname(__FILE__) + '/lib/join_dependency'

class ActiveRecord::Base
  extend IncludeByDefault::ClassMethods
  extend IncludeByDefault::Cascading
  extend IncludeByDefault::SqlFragments
  alias_method_chain(:find_every, :default_includes)
  alias_method_chain(:column_aliases, :eager_loading_from_joins)
  alias_method(:using_limitable_reflections_without_duplicate_alias_exception_catching?, :using_limitable_reflections?)
  alias_method(:using_limitable_reflections?, :using_limitable_reflections_with_duplicate_alias_exception_catching?)
end
