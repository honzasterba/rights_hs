module RightsHS

  def self.included(base)
    base.extend(ClassMethods)
    base.send(:include, InstanceMethods)
  end
  
  module ClassMethods
    def check(obj_name)
        Check.new(self, obj_name)
    end
    
    def define_check(check)
      self.ignore_method_added = true
      alias_method check.action_unchecked, check.action
      private check.action_unchecked
      define_method check.action do |*args|
        if check_rights(check)
          send(check.action_unchecked, *args)
        end
      end
      self.ignore_method_added = false
    end
    
    def define_global_check(check)
      public_instance_methods(false).each do |method|
        process_global_check(method, check)
      end
      add_global_check(check)
    end
    
    @@global_checks = {}
    @@ignore_method_added = []
    
    protected
    
      def global_checks
        @@global_checks[self] ||= []
      end
      
      def ignore_method_added
        @@ignore_method_added.rindex(self)
      end
      
      def ignore_method_added=(val)
        if !val
          @@ignore_method_added.delete(self)
        elsif !ignore_method_added
          @@ignore_method_added << self
        end
      end
        
      def add_global_check(check)
        global_checks << check
      end

      def process_global_check(method, check)
        method_check = check.clone
        method_check.action = method
        define_check(method_check)
      end

      def method_added(method)
        return if ignore_method_added
        return unless public_instance_methods(false).rindex(method.to_s)
        global_checks.each do |check|
          process_global_check(method, check)
        end
      end

  end
  
  module InstanceMethods
    
    private
      def check_rights(check)
        user = load_object(check.obj_name)
        scope = load_object(check.scope)
        check.roles.each do |role|
          res = check_by_method(user, role, scope) || check_by_permission(user, role, scope)
          if check.type == :one
            return true if res
          elsif check.type == :all
            raise RightsViolationError, "User does not have needed roles." unless res
          end
        end
        raise RightsViolationError, "User does not have required role."
      end
      
      def check_by_method(user, role, scope)
        if scope.nil?
          m = ("is_" + role.to_s).to_sym
        else
          m = ("is_" + role.to_s + "_of").to_sym
        end
        return user.send(m) if user.respond_to?(m) and scope == nil
        return user.send(m, scope) if user.respond_to?(m)
        return false
      end
      
      def check_by_permission(user, role, scope)
        return user.send(:has_permissions, role) if user.respond_to?(:has_permissions) and scope == nil
        return user.send(:has_permissions, role, scope) if user.respond_to?(:has_permissions)
        return false
      end
    
      def load_object(obj_name)
        return nil if obj_name.nil?
        if (respond_to?(obj_name, true))
          send(obj_name.to_sym)
        elsif (has_hash_and_value(:session, obj_name))
          load_from_hash(:session, obj_name)
        elsif (has_hash_and_value(:params, obj_name))
          load_from_hash(:params, obj_name)
        else
          raise RightsViolationError, "Not able to load #{obj_name} object!"
        end
      end
      
      def load_from_hash(hash_name, obj_name)
        val = has_hash_and_value(hash_name, obj_name)
        if (val.respond_to?(:to_i) and val.to_i == val)
          load_from_ar(obj_name, val)
        else
          val
        end
      end
      
      def load_from_ar(obj_name, val)
        klazz = obj_name.camelize.symbolize
        raise RightsViolationError, "Unable to find AR object class." unless klazz
        obj = klazz.find_by_id(val)
        raise RightsViolationError, "Unable to find AR object." unless obj
        obj
      end
      
      def has_hash_and_value(hash_name, obj_name)
        return false unless respond_to?(hash_name, true)
        send(hash_name)[obj_name] || send(hash_name)[obj_name.to_s + "_id"]
      end
  end

end

class RightsViolationError < Exception; end

class Check
  
  attr_reader :obj_name, :type, :roles, :action, :scope
  attr_writer :action
  
  def action_unchecked
    (@action.to_s + "_rights_unchecked_"+object_id.to_s).to_sym
  end  
  
  def initialize(source, obj_name)
    @source = source
    @obj_name = obj_name
  end
  
  def is(role_name)
    @type = :one
    @roles = [role_name]
    self
  end
  
  def is_one_of(*roles)
    @type = :one
    @roles = roles
    self
  end
  
  def is_all_of(*roles)
    @type = :all
    @roles = roles
    self
  end
  
  def of(scope)
    @scope = scope
    self
  end
  
  def on(action)
    @action = action
    finalize!
    nil
  end
  
  def everytime
    @action = nil
    finalize!
    nil
  end
  
  protected
    def finalize!
      if @action
        @source.define_check(self)
      else 
        @source.define_global_check(self)
      end
    end
end
