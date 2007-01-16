#
#  $Id$
#
#  Copyright (c) 2001 FUJIMOTO Hisakuni
#

require 'osx/objc/oc_wrapper'

module OSX

  FRAMEWORK_PATHS = [
    '/System/Library/Frameworks',
    '/Library/Frameworks'
  ]

  SIGN_PATHS = [
    '/System/Library/BridgeSupport', 
    '/Library/BridgeSupport'
  ]

  PRE_SIGN_PATHS = 
    if path = ENV['BRIDGE_SUPPORT_PATH']
      path.split(':')
    else
      []
    end

  if path = ENV['HOME']
    FRAMEWORK_PATHS << File.join(ENV['HOME'], 'Library', 'Frameworks')
    SIGN_PATHS << File.join(ENV['HOME'], 'Library', 'BridgeSupport')
  end

  # A name-to-path cache for the frameworks we support that are buried into umbrella frameworks.
  QUICK_FRAMEWORKS = {
    'CoreGraphics' => '/System/Library/Frameworks/ApplicationServices.framework/Frameworks/CoreGraphics.framework',
    'PDFKit' => '/System/Library/Frameworks/Quartz.framework/Frameworks/PDFKit.framework',
    'ImageKit' => '/System/Library/Frameworks/Quartz.framework/Frameworks/ImageKit.framework'
  }

  def _bundle_path_for_framework(framework)
    if framework[0] == ?/
      [OSX::NSBundle.bundleWithPath(framework), framework]
    elsif path = QUICK_FRAMEWORKS[framework]
      [OSX::NSBundle.bundleWithPath(path), path]
    else
      path = FRAMEWORK_PATHS.map { |dir| 
        File.join(dir, "#{framework}.framework") 
      }.find { |path| 
        File.exist?(path) 
      }
      if path
        [OSX::NSBundle.bundleWithPath(path), path]
      end
    end
  end
  module_function :_bundle_path_for_framework

  def require_framework(framework)
    bundle, path = _bundle_path_for_framework(framework)
    unless bundle.nil?
      return false if bundle.isLoaded
      if bundle.oc_load
        load_bridge_support_signatures(path)
        return true
      end
    end
    raise LoadError, "Can't locate framework '#{framework}'"
  end
  module_function :require_framework

  def framework_loaded?(framework)
    bundle, path = _bundle_path_for_framework(framework)
    unless bundle.nil?
      loaded = bundle.isLoaded
      unless loaded
        # CoreFoundation/Foundation are linked at built-time.
        id = bundle.bundleIdentifier
        loaded = (id.isEqualToString('com.apple.CoreFoundation') or 
                  id.isEqualToString('com.apple.Foundation'))
      end
      loaded
    else
      raise ArgumentError, "Can't locate framework '#{framework}'"
    end
  end
  module_function :framework_loaded?

  def load_bridge_support_signatures(framework)
    # First, look into the pre paths.  
    framework_name = framework[0] == ?/ ? File.basename(framework, '.framework') : framework
    PRE_SIGN_PATHS.each do |dir|
      path = File.join(dir, framework_name + '.xml')
      if File.exist?(path)
        load_bridge_support_file(path)
        return true
      end
    end

    # A path to a framework, let's search for BridgeSupport.xml inside the Resources folder.
    if framework[0] == ?/
      path = File.join(framework, 'Resources', 'BridgeSupport.xml')
      if File.exist?(path)
        load_bridge_support_file(path)
        return true
      end
      framework = framework_name
    end
    
    # Let's try to localize the framework and see if it contains the metadata.
    FRAMEWORK_PATHS.each do |dir|
      path = File.join(dir, "#{framework}.framework")
      if File.exist?(path)
        path = File.join(path, 'Resources', 'BridgeSupport.xml')
        if File.exist?(path)
          load_bridge_support_file(path)
          return true
        end
        break
      end
    end
 
    # We can still look into the general metadata directories. 
    SIGN_PATHS.each do |dir|
      path = File.join(dir, "#{framework}.xml")
      if File.exist?(path)
        load_bridge_support_file(path)
        return true
      end
    end

    # Damnit!
    STDERR.puts "Can't find signatures file for #{framework}" if $VERBOSE
    return false
  end
  module_function :load_bridge_support_signatures

  # Load C constants/classes lazily.
  def self.const_missing(c)
    begin
      OSX::import_c_constant(c)
    rescue LoadError
      (OSX::ns_import(c) or raise NameError, "uninitialized constant #{c}")
    end
  end

  def self.included(m)
    if m.respond_to? :const_missing
      m.module_eval <<-EOC,__FILE__,__LINE__+1
        class <<self
          alias_method :_osx_const_missing_prev, :const_missing
          def const_missing(c)
            begin
              OSX.const_missing(c)
            rescue NameError
              _osx_const_missing_prev(c)
            end
          end
	    end
      EOC
    else
      m.module_eval <<-EOC,__FILE__,__LINE__+1
        def self.const_missing(c)
          OSX.const_missing(c)
        end
      EOC
    end
  end
  
  # Load the foundation frameworks.
  OSX.load_bridge_support_signatures('CoreFoundation')
  OSX.load_bridge_support_signatures('Foundation')

  # create Ruby's class for Cocoa class,
  # then define Constant under module 'OSX'.
  def ns_import(sym)
    if not OSX.const_defined?(sym)
      NSLog("importing #{sym}...") if $DEBUG
      klass = if clsobj = NSClassFromString(sym)
        if rbcls = class_new_for_occlass(clsobj)
          OSX.const_set(sym, rbcls)
        end
      end
      NSLog("importing #{sym}... done (#{klass.ancestors.join(' -> ')})") if (klass and $DEBUG)
      return klass
    end
  end
  module_function :ns_import

  # create Ruby's class for Cocoa class
  def class_new_for_occlass(occls)
    superclass = _objc_lookup_superclass(occls)
    klass = Class.new(superclass)
    klass.class_eval <<-EOE_CLASS_NEW_FOR_OCCLASS,__FILE__,__LINE__+1
      if superclass == OSX::ObjcID
        include OCObjWrapper 
        self.extend OCClsWrapper
      end
      @ocid = #{occls.__ocid__}
    EOE_CLASS_NEW_FOR_OCCLASS
    if superclass == OSX::ObjcID
      def klass.__ocid__() @ocid end
      def klass.to_s() name end
      def klass.inherited(subklass) subklass.ns_inherited() end
    end
    return klass
  end
  module_function :class_new_for_occlass 
 
  def _objc_lookup_superclass(occls)
    occls_superclass = occls.oc_superclass
    if occls_superclass.nil?
      OSX::ObjcID
    else
      begin
        OSX.const_get("#{occls_superclass}".to_sym) 
        rescue NameError
        # some ObjC internal class cannot become Ruby constant
        # because of prefix '%' or '_'
        if occls.__ocid__ != occls_superclass.__ocid__
          OSX._objc_lookup_superclass(occls_superclass)
        else
          OSX::ObjcID # root class of ObjC
        end
      end
    end
  end
  module_function :_objc_lookup_superclass

  module NSBehaviorAttachment

    ERRMSG_FOR_RESTRICT_NEW = "use 'alloc.initXXX' to instantiate Cocoa Object"

    # restrict creating an instance by Class#new of NSObject gruop.
    def new
      raise ERRMSG_FOR_RESTRICT_NEW
    end

    # initializer for definition of a derived class of a class on
    # Objective-C World.
    def ns_inherited()
      return if ns_inherited?
      spr_name = superclass.name.split('::')[-1]
      kls_name = self.name.split('::')[-1]
      occls = OSX.objc_derived_class_new(self, kls_name, spr_name)
      self.instance_eval "@ocid = #{occls.__ocid__}",__FILE__,__LINE__+1
      @inherited = true
    end

    def ns_inherited?
      return defined?(@inherited) && @inherited
    end

    # declare to override instance methods of super class which is
    # defined by Objective-C.
    def ns_overrides(*args)
      # insert specified selectors to Objective-C method table.
      args.each do |name|
	      name = name.to_s.gsub('_',':')
	      OSX.objc_class_method_add(self, name)
      end
    end

    # declare write-only attribute accessors which are named IBOutlet
    # in the Objective-C world.
    def ns_outlets(*args)
      attr_writer(*args)
    end

    # for look and feel
    alias_method :ns_override,  :ns_overrides
    alias_method :ib_override,  :ns_overrides
    alias_method :ib_overrides, :ns_overrides
    alias_method :ns_outlet,  :ns_outlets
    alias_method :ib_outlet,  :ns_outlets
    alias_method :ib_outlets, :ns_outlets

    def _ns_behavior_method_added(sym, class_method)
      sel = sym.to_s.gsub(/([^_])_/, '\1:')
      m = class_method ? method(sym) : instance_method(sym)
      sel << ':' if m.arity > 0 and /[^:]\z/ =~ sel
      return unless _ns_enable_override?(sel, class_method)
      OSX.objc_class_method_add(self, sel, class_method)
    end

    def _ns_enable_override?(sel, class_method)
      ns_inherited? and (class_method ? self.objc_method_type(sel) : self.objc_instance_method_type(sel))
    end

    def objc_export(name, types)
      typefmt = _types_to_typefmt(types)
      name = name.to_s
      name = name[0].chr << name[1..-1].gsub(/_/, ':')
      name << ':' if name[-1] != ?: and typefmt[-1] != ?:
      self.addRubyMethod_withType(name, typefmt)
    end

    # TODO: support more types such as pointers...
    OCTYPES = {
      :id      => '@',
      :class   => '#',
      :char    => 'c',
      :uchar   => 'C',
      :short   => 's',
      :ushort  => 'S',
      :int     => 'i',
      :uint    => 'I',
      :long    => 'l',
      :ulong   => 'L',
      :float   => 'f',
      :double  => 'd',
      :bool    => 'B',
      :void    => 'v'
    }
    def _types_to_typefmt(types)
      return types.strip if types.is_a?(String)
      raise ArgumentError, "Array or String (as type format) expected (got #{types.klass} instead)" unless types.is_a?(Array)
      raise ArgumentError, "Given types array should have at least an element" unless types.size > 0
      octypes = types.map do |type|
        if type.is_a?(Class) and type.ancestors.include?(OSX::Boxed)
          type.instance_variable_get :@__encoding__
        else
          type = type.strip.intern unless type.is_a?(Symbol)
          octype = OCTYPES[type]
          raise "Invalid type (got '#{type}', expected one of : #{OCTYPES.keys.join(', ')}, or a boxed class)" if octype.nil?
          octype
        end
      end
      octypes[0] + '@:' + octypes[1..-1].join
    end

  end				# module OSX::NSBehaviorAttachment

  module NSKVCAccessorUtil
    private

    def kvc_internal_setter(key)
      return '_kvc_internal_' + key.to_s + '=' 
    end

    def kvc_setter_wrapper(key)
      return '_kvc_wrapper_' + key.to_s + '=' 
    end
  end				# module OSX::NSKVCAccessorUtil

  module NSKeyValueCodingAttachment
    include NSKVCAccessorUtil

    # invoked from valueForUndefinedKey: of a Cocoa object
    def rbValueForKey(key)
      if m = kvc_getter_method(key.to_s)
	return send(m)
      else
	kvc_accessor_notfound(key)
      end
    end

    # invoked from setValue:forUndefinedKey: of a Cocoa object
    def rbSetValue_forKey(value, key)
      if m = kvc_setter_method(key.to_s)
	willChangeValueForKey(key)
	send(m, value)
	didChangeValueForKey(key)
      else
	kvc_accessor_notfound(key)
      end
    end

    private
    
    # find accesor for key-value coding
    # "key" must be a ruby string

    def kvc_getter_method(key)
      [key, key + '?'].each do |m|
	return m if respond_to? m
      end
      return nil # accessor not found
    end
 
    def kvc_setter_method(key)
      [kvc_internal_setter(key), key + '='].each do |m|
	return m if respond_to? m
      end
      return nil
    end

    def kvc_accessor_notfound(key)
      fmt = '%s: this class is not key value coding-compliant for the key "%s"'
      raise sprintf(fmt, self.class, key.to_s)
    end

  end				# module OSX::NSKeyValueCodingAttachment

  module NSKVCBehaviorAttachment
    include NSKVCAccessorUtil

    def kvc_reader(*args)
      attr_reader(*args)
    end

    def kvc_writer(*args)
      args.flatten.each do |key|
	setter = key.to_s + '='
	attr_writer(key) unless method_defined?(setter)
	alias_method kvc_internal_setter(key), setter
	self.class_eval <<-EOE_KVC_WRITER,__FILE__,__LINE__+1
	  def #{kvc_setter_wrapper(key)}(value)
	    willChangeValueForKey('#{key.to_s}')
	    send('#{kvc_internal_setter(key)}', value)
	    didChangeValueForKey('#{key.to_s}')
	  end
	EOE_KVC_WRITER
	alias_method setter, kvc_setter_wrapper(key)
      end
    end

    def kvc_accessor(*args)
      kvc_reader(*args)
      kvc_writer(*args)
    end

    def kvc_depends_on(keys, *dependencies)
      dependencies.flatten.each do |dependentKey|
        setKeys_triggerChangeNotificationsForDependentKey(Array(keys), dependentKey)
      end
    end
 
    # define accesor for keys defined in Cocoa, 
    # such as NSUserDefaultsController and NSManagedObject
    def kvc_wrapper(*keys)
      kvc_wrapper_reader(*keys)
      kvc_wrapper_writer(*keys)
    end

    def kvc_wrapper_reader(*keys)
      keys.flatten.compact.each do |key|
        class_eval <<-EOE_KVC_WRAPPER,__FILE__,__LINE__+1
    	def #{key}
  	  valueForKey("#{key}")
	end
  	EOE_KVC_WRAPPER
      end
    end

    def kvc_wrapper_writer(*keys)
      keys.flatten.compact.each do |key|
        class_eval <<-EOE_KVC_WRAPPER,__FILE__,__LINE__+1
	def #{key}=(val)
	  setValue_forKey(val, "#{key}")
	end
  	EOE_KVC_WRAPPER
      end
    end

    # Define accessors that send change notifications for an array.
    # The array instance variable must respond to the following methods:
    #
    #  length
    #  [index]
    #  [index]=
    #  insert(index,obj)
    #  delete_at(index)
    #
    # Notifications are only sent for accesses through the Cocoa methods:
    #  countOfKey, objectInKeyAtIndex_, insertObject_inKeyAtIndex_,
    #  removeObjectFromKeyAtIndex_, replaceObjectInKeyAtIndex_withObject_
    #
    def kvc_array_accessor(*args)
      args.each do |key|
	keyname = key.to_s
	keyname[0..0] = keyname[0..0].upcase
	self.addRubyMethod_withType("countOf#{keyname}".to_sym, "i4@8:12")
	self.addRubyMethod_withType("objectIn#{keyname}AtIndex:".to_sym, "@4@8:12i16")
	self.addRubyMethod_withType("insertObject:in#{keyname}AtIndex:".to_sym, "@4@8:12@16i20")
	self.addRubyMethod_withType("removeObjectFrom#{keyname}AtIndex:".to_sym, "@4@8:12i16")
	self.addRubyMethod_withType("replaceObjectIn#{keyname}AtIndex:withObject:".to_sym, "@4@8:12i16@20")
	# get%s:range: - unimplemented. You can implement this method for performance improvements.
	self.class_eval <<-EOT,__FILE__,__LINE__+1
	  def countOf#{keyname}()
	    return @#{key.to_s}.length
	  end

	  def objectIn#{keyname}AtIndex(index)
	    return @#{key.to_s}[index]
	  end

	  def insertObject_in#{keyname}AtIndex(obj, index)
	    indexes = OSX::NSIndexSet.indexSetWithIndex(index)
	    willChange_valuesAtIndexes_forKey(OSX::NSKeyValueChangeInsertion, indexes, #{key.inspect})
	    @#{key.to_s}.insert(index, obj)
	    didChange_valuesAtIndexes_forKey(OSX::NSKeyValueChangeInsertion, indexes, #{key.inspect})
	    nil
	  end

	  def removeObjectFrom#{keyname}AtIndex(index)
	    indexes = OSX::NSIndexSet.indexSetWithIndex(index)
	    willChange_valuesAtIndexes_forKey(OSX::NSKeyValueChangeRemoval, indexes, #{key.inspect})
	    @#{key.to_s}.delete_at(index)
	    didChange_valuesAtIndexes_forKey(OSX::NSKeyValueChangeRemoval, indexes, #{key.inspect})
	    nil
	  end

	  def replaceObjectIn#{keyname}AtIndex_withObject(index, obj)
	    indexes = OSX::NSIndexSet.indexSetWithIndex(index)
	    willChange_valuesAtIndexes_forKey(OSX::NSKeyValueChangeReplacement, indexes, #{key.inspect})
	    @#{key.to_s}[index] = obj
	    didChange_valuesAtIndexes_forKey(OSX::NSKeyValueChangeReplacement, indexes, #{key.inspect})
	    nil
	  end
	EOT
      end
    end

    # re-wrap at overriding setter method
    def _kvc_behavior_method_added(sym)
      return unless sym.to_s =~ /\A([^=]+)=\z/
      key = $1
      setter = kvc_internal_setter(key)
      wrapper = kvc_setter_wrapper(key)
      return unless method_defined?(setter) && method_defined?(wrapper)
      return if instance_method(wrapper) == instance_method(sym)
      alias_method setter, sym
      alias_method sym, wrapper
    end

  end				# module OSX::NSKVCBehaviorAttachment

  module OCObjWrapper

    include NSKeyValueCodingAttachment
  
  end

  module OCClsWrapper

    include OCObjWrapper
    include NSBehaviorAttachment
    include NSKVCBehaviorAttachment

    def singleton_method_added(sym)
      _ns_behavior_method_added(sym, true)
    end 
 
    def method_added(sym)
      _ns_behavior_method_added(sym, false)
      _kvc_behavior_method_added(sym)
    end

  end

end				# module OSX

# The following code defines a new subclass of Object (Ruby's).
# 
#    module OSX 
#      class NSCocoaClass end 
#    end
#
# This Object.inherited() replaces the subclass of Object class by 
# a Cocoa class from # OSX.ns_import.
#
class Object
  class <<self
    def _real_class_and_mod(klass)
      unless klass.ancestors.include?(OSX::Boxed)
        klassname = klass.name
        unless klassname.empty?
          if Object.included_modules.include?(OSX) and /::/.match(klassname).nil?
            [klassname, Object]
          elsif klassname[0..4] == 'OSX::' and (tokens = klassname.split(/::/)).size == 2 and klass.superclass != OSX::Boxed
            [tokens[1], OSX]
          end
        end
      end
    end

    alias _before_osx_inherited inherited
    def inherited(subklass)
      nsklassname, mod = _real_class_and_mod(subklass) 
      if nsklassname
        # remove Ruby's class
        mod.instance_eval { remove_const nsklassname.intern }
        begin
          klass = OSX.ns_import nsklassname.intern
          raise NameError if klass.nil?
          subklass = klass
        rescue NameError
          # redefine subclass (looks not a Cocoa class)
          mod.const_set(nsklassname, subklass)
        end
      end
      _before_osx_inherited(subklass)
    end

    def _register_method(sym, class_method)
      if self != Object
        nsklassname, mod = _real_class_and_mod(self)
        if nsklassname
          begin
            nsklass = OSX.const_get(nsklassname)
            raise NameError unless nsklass.ancestors.include?(OSX::NSObject)
            if class_method
              method = self.method(sym).unbind
              OSX.__rebind_umethod__(nsklass.class, method)
              nsklass.module_eval do 
                (class << self; self; end).instance_eval do 
                  if RUBY_VERSION >= "1.8.5"
                    define_method(sym, method)
                  else
                    define_method(sym) { method.bind(self).call }
                  end
                end
              end
            else
              method = self.instance_method(sym)
              OSX.__rebind_umethod__(nsklass, method)
              nsklass.module_eval do
                if RUBY_VERSION >= "1.8.5"
                  define_method(sym, method)
                else
                  define_method(sym) { method.bind(self).call }
                end
              end
            end
          rescue NameError
          end
        end
      end
    end

    alias _before_method_added method_added
    def method_added(sym)
      _register_method(sym, false)
      _before_method_added(sym)
    end

    alias _before_singleton_method_added singleton_method_added
    def singleton_method_added(sym)
      _register_method(sym, true)
      _before_singleton_method_added(sym)
    end
  end
end
