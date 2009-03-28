require 'test/unit'
require File.dirname(__FILE__) + '/../lib/rights_hs'

class RightsHSTest < Test::Unit::TestCase
  
  def setup
    @obj = RightsTestable.new
    assert session
  end
  
  def session
    @obj.send(:session)
  end
  
  def params
    @obj.send(:params)
  end
  
  def called(method)
    @obj.send(:observer).called?(method)
  end

  def test_no_object
    assert_raise(RightsViolationError, "No object accessible, rights check must fail.") { 
      @obj.action1
    }
    assert !called(:action1), "The original action method should not get called."
  end
  
  def test_object_in_method
    assert_raise(RightsViolationError, "No object accessible, rights check must fail.") { 
      @obj.action2
    }
    assert !called(:action2), "Action2 should not be called"
    assert called(:user2), "User2 should be called as part of the checking process"
  end
  
  def test_object_in_session_and_params
    assert_raise(RightsViolationError, "No object accessible, rights check must fail.") { 
      @obj.action3
    }
    assert session.key_accessed?(:user3), "Should try to look for :user3 in session"
    assert session.key_accessed?(:user3_id), "Should try to look for :user3_id in session"
    assert params.key_accessed?(:user3), "Should try to look for :user3 in params"
    assert params.key_accessed?(:user3_id), "Should try to look for :user3_id in params"
    assert !called(:action3), "Action3 should not be called"
  end
  
  
  def test_object_validate_by_method_fail
    session[:regular_user1] = User1.new(false)
    assert_raise(RightsViolationError, "Regular user not admin, rights check must fail.") { 
      @obj.action4
    }    
    assert !called(:action4)
  end
  
  def test_object_validate_by_method_succeed
    session[:admin_user1] = User1.new(true)
    @obj.action5
    assert called(:action5)
  end

  def test_object_validate_by_permission_fail
    session[:admin_user2] = User2.new()
    assert_raise(RightsViolationError, "Regular user not admin, rights check must fail.") { 
      @obj.action6
    }    
    assert !called(:action6)
  end
  
  def test_object_validate_by_method_succeed
    u = User2.new()    
    u.permissions << :admin
    session[:admin_user2] = u
    @obj.action7
    assert called(:action7)
  end
  
  def test_object_with_scope_param_fail
    session[:user_with_scope] = User3.new()
    session[:scope] = false
    assert_raise(RightsViolationError, "Regular user not admin with context, rights check must fail.") { 
      @obj.action8
    }    
    assert !called(:action8)
  end

  def test_object_with_scope_param_succeed
    session[:user_with_scope] = User3.new()
    session[:scope] = true
    @obj.action9
    assert called(:action9)
  end
  
  def test_global_rights_fail
    @obj = GlobalRightsTestable.new
    session[:user] = User1.new(false)
    assert_raise(RightsViolationError, "Regular user not admin for action1, rights check must fail.") { 
      @obj.action1
    }
    assert !called(:action1)
    assert_raise(RightsViolationError, "Regular user not admin for action2, rights check must fail.") { 
      @obj.action2
    }
    assert !called(:action2)
  end

  def test_global_rights_succeed
    @obj = GlobalRightsTestable.new
    user = User1.new(true)
    session[:user] = user
    @obj.action1
    assert user.admin_called, "Did not check rights with user"
    assert called(:action1), "Action1 should be called user is admin"
    @obj.action2
    assert called(:action2), "Action2 should be called user is admin"
  end
  
  def test_global_scoped_rights_fail
    @obj = GlobalScopedRightsTestable.new
    session[:user] = User3.new
    session[:scope]= false
    assert_raise(RightsViolationError, "Regular user not admin for action1, rights check must fail.") { 
      @obj.action1
    }
    assert !called(:action1)
    assert_raise(RightsViolationError, "Regular user not admin for action2, rights check must fail.") { 
      @obj.action2
    }
    assert !called(:action2)
  end
  
  
  def test_global_scoped_rights_succeed
    @obj = GlobalScopedRightsTestable.new
    user = User3.new
    session[:user] = user
    session[:scope]= true
    @obj.action1
    assert user.checked_on(true), "Did not check rights with user"
    assert called(:action1)
    @obj.action2
    assert called(:action2)
  end

end

class WatchableHash < Hash 
  
  def key_accessed?(key) 
    @keys_accessed ||= []
    @keys_accessed.rindex(key)
  end
  
  def [](key)
    @keys_accessed ||= []
    @keys_accessed << key.to_sym
    super
  end
  
end

class User1
  
  def initialize(admin)
    @admin = admin
  end
  
  def admin_called
    @called
  end
  
  def is_admin
    @called = true
    return @admin
  end
end

class User2
  
  attr_accessor :permissions
  
  def initialize
    @permissions = []
  end
  
  def has_permissions(name)
    return @permissions.rindex(name)
  end
end

class User3
  
  def checked_on(obj)
    return @checked == obj
  end
  
  def is_admin_of(obj) 
    @checked = obj
    obj == true
  end
  
end

class Testable
  
  include RightsHS
     
  def initialize
    @params = WatchableHash.new
    @session = WatchableHash.new      
    @observer = CallObserver.new
  end
  
  protected
  
    def session
      @session
    end

    def params
      @params
    end
    
    def observer
      @observer
    end
    
end

class CallObserver
  
  def initialize
    @calls = []
  end
  
  def called?(name)
    @calls.rindex name.to_sym
  end
  
  def called(name)
    @calls << name.to_sym
    nil
  end
  
end

class RightsTestable < Testable
  
  def action1
    observer.called :action1
  end
  check(:user1).is(:admin).on(:action1)

  def action2
    observer.called :action2
  end
  check(:user2).is(:admin).on(:action2)
  
  def user2
    observer.called :user2
  end
  private :user2
    
  def action3
    observer.called :action3
  end
  check(:user3).is(:admin).on(:action3)
  
  def action4
    observer.called :action4
  end
  check(:regular_user1).is(:admin).on(:action4)

  def action5
    observer.called :action5
  end
  check(:admin_user1).is(:admin).on(:action5)

  def action6
    observer.called :action6
  end
  check(:regular_user2).is(:admin).on(:action6)

  def action7
    observer.called :action7
  end
  check(:admin_user2).is(:admin).on(:action7)  

  def action8
    observer.called :action8
  end
  check(:user_with_scope).is(:admin).of(:scope).on(:action8)  

  def action9
    observer.called :action9
  end
  check(:user_with_scope).is(:admin).of(:scope).on(:action9)  

end

class GlobalRightsTestable < Testable
  
  check(:user).is(:admin).everytime  
    
  def action1
    observer.called :action1
  end
  
  def action2
    observer.called :action2
  end
  
end

class GlobalScopedRightsTestable < Testable
  
  check(:user).is(:admin).of(:scope).everytime
  
  def action1
    observer.called :action1
  end
  
  def action2
    observer.called :action2
  end

end