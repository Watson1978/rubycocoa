# Copyright (c) 2006-2007, The RubyCocoa Project.
# Copyright (c) 2001-2006, FUJIMOTO Hisakuni.
# All Rights Reserved.
#
# RubyCocoa is free software, covered under either the Ruby's license or the 
# LGPL. See the COPYRIGHT file for more information.

require 'osx/objc/oc_wrapper'

module OSX

  # NSString additions
  class NSString
    include OSX::OCObjWrapper

    def dup
      mutableCopy
    end
    
    def clone
      obj = dup
      obj.freeze if frozen?
      obj.taint if tainted?
      obj
    end
    
    # enable to treat as String
    def to_str
      self.to_s
    end

    # comparison between Ruby String and Cocoa NSString
    def ==(other)
      if other.is_a? OSX::NSString
        isEqualToString?(other)
      elsif other.respond_to? :to_str
        self.to_s == other.to_str
      else
        false
      end
    end

    def <=>(other)
      if other.respond_to? :to_str
        self.to_str <=> other.to_str
      else
        nil
      end
    end

    # responds to Ruby String methods
    alias_method :_rbobj_respond_to?, :respond_to?
    def respond_to?(mname, private = false)
      String.public_method_defined?(mname) or _rbobj_respond_to?(mname, private)
    end

    alias_method :objc_method_missing, :method_missing
    def method_missing(mname, *args, &block)
      ## TODO: should test "respondsToSelector:"
      if String.public_method_defined?(mname) && (mname != :length)
        # call as Ruby string
        rcv = self.to_s
        org_val = rcv.dup
        result = rcv.send(mname, *args, &block)
        # bang methods modify receiver itself, need to set the new value.
        # if the receiver is immutable, NSInvalidArgumentException raises.
        if rcv != org_val
          self.setString(rcv)
        end
      else
        # call as objc string
        result = objc_method_missing(mname, *args)
      end
      result
    end
  end

  # For NSArray duck typing
  module NSArrayAttachment
    include Enumerable

    def each
      iter = objectEnumerator
      while obj = iter.nextObject
        yield(obj)
      end
      self
    end
    
    def reverse_each
      iter = reverseObjectEnumerator
      while obj = iter.nextObject
        yield(obj)
      end
      self
    end

    def [](*args)
      _read_impl(:[], args)
    end

    def []=(*args)
      count = self.count
      case args.length
      when 2
        case args.first
        when Numeric
          index, value = args
          unless index.is_a? Numeric
            raise TypeError, "can't convert #{index.class} into Integer"
          end
          if value == nil
            raise ArgumentError, "attempt insert nil to NSDictionary"
          end
          index = index.to_i
          index += count if index < 0
          if 0 <= index && index < count
            replaceObjectAtIndex_withObject(index, value)
          elsif index == count
            addObject(value)
          else
            raise IndexError, "index #{args[0]} out of array"
          end
          value
        when Range
          range, value = args
          nsrange = OSX::NSRange.new(range, count)
          loc = nsrange.location
          if 0 <= loc && loc < count
            if nsrange.length > 0
              removeObjectsInRange(nsrange)
            end
            value = value.to_a if value.is_a? OSX::NSArray
            if value != nil && value != []
              if value.is_a? Array
                indexes = OSX::NSIndexSet.indexSetWithIndexesInRange(NSRange.new(loc, value.length))
                insertObjects_atIndexes(value, indexes)
              else
                insertObject_atIndex(value, loc)
              end
            end
          elsif loc == count
            value = value.to_a if value.is_a? OSX::NSArray
            if value != nil && value != []
              if value.is_a? Array
                addObjectsFromArray(value)
              else
                addObject(value)
              end
            end
          else
            raise IndexError, "index #{loc} out of array"
          end
          value
        else
          raise ArgumentError, "wrong number of arguments (#{args.length}) for 3)"
        end
      when 3
        start, len, value = args
        unless start.is_a? Numeric
          raise TypeError, "can't convert #{start.class} into Integer"
        end
        unless len.is_a? Numeric
          raise TypeError, "can't convert #{len.class} into Integer"
        end
        start = start.to_i
        len = len.to_i
        if len < 0
          raise IndexError, "negative length (#{len})"
        else
          range = start...(start + len)
          self[range] = value
          value
        end
      else
        raise ArgumentError, "wrong number of arguments (#{args.length}) for 3)"
      end
    end
    
    def <<(obj)
      addObject(obj)
      self
    end
    
    def &(other)
      ary = other
      unless ary.is_a? Array
        if ary.respond_to?(:to_ary)
          ary = ary.to_ary
          unless ary.is_a? Array
            raise TypeError, "can't convert #{other.class} into Array"
          end
        else
          raise TypeError, "can't convert #{other.class} into Array"
        end
      end
      result = []
      dic = OSX::NSMutableDictionary.alloc.init
      each {|i| dic.setObject_forKey(i, i) }
      ary.each do |i|
        if dic.objectForKey(i)
          result << i
          dic.removeObjectForKey(i)
        end
      end
      result
    end
    
    def |(other)
      ary = other
      unless ary.is_a? Array
        if ary.respond_to?(:to_ary)
          ary = ary.to_ary
          unless ary.is_a? Array
            raise TypeError, "can't convert #{other.class} into Array"
          end
        else
          raise TypeError, "can't convert #{other.class} into Array"
        end
      end
      result = []
      dic = OSX::NSMutableDictionary.alloc.init
      [self, ary].each do |obj|
        obj.each do |i|
          unless dic.objectForKey(i)
            dic.setObject_forKey(i, i)
            result << i
          end
        end
      end
      result
    end
    
    def *(arg)
      case arg
      when Numeric
        to_a * arg
      when String
        join(arg)
      else
        raise TypeError, "can't convert #{arg.class} into Integer"
      end
    end
    
    def +(other)
      ary = other
      unless ary.is_a? Array
        if ary.respond_to?(:to_ary)
          ary = ary.to_ary
          unless ary.is_a? Array
            raise TypeError, "can't convert #{other.class} into Array"
          end
        else
          raise TypeError, "can't convert #{other.class} into Array"
        end
      end
      to_a.concat(ary)
    end
    
    def -(other)
      ary = other
      unless ary.is_a? Array
        if ary.respond_to?(:to_ary)
          ary = ary.to_ary
          unless ary.is_a? Array
            raise TypeError, "can't convert #{other.class} into Array"
          end
        else
          raise TypeError, "can't convert #{other.class} into Array"
        end
      end
      result = []
      dic = OSX::NSMutableDictionary.alloc.init
      ary.each {|i| dic.setObject_forKey(i, i) }
      each {|i| result << i unless dic.objectForKey(i) }
      result
    end
    
    def assoc(key)
      each do |i|
        if i.is_a? OSX::NSArray
          unless i.empty?
            return i.to_a if i.first.isEqual(key)
          end
        end
      end
      nil
    end
    
    def at(pos)
      self[pos]
    end
    
    def clear
      removeAllObjects
      self
    end
    
    def collect!
      each_with_index {|i,n| replaceObjectAtIndex_withObject(n, yield(i)) }
      self
    end
    alias_method :map!, :collect!
    
    # does nothing because NSArray cannot have nil
    def compact; to_a; end
    def compact!; nil; end
    
    def concat(other)
      addObjectsFromArray(other)
      self
    end
    
    def delete(val)
      indexes = OSX::NSMutableIndexSet.alloc.init
      each_with_index {|i,n| indexes.addIndex(n) if i.isEqual(val) }
      removeObjectsAtIndexes(indexes) if indexes.count > 0
      if block_given?
        yield
      elsif indexes.count > 0
        val
      else
        nil
      end
    end
    
    def delete_at(pos)
      unless pos.is_a? Numeric
        raise TypeError, "can't convert #{pos.class} into Integer"
      end
      count = self.count
      pos = pos.to_i
      pos += count if pos < 0
      if 0 <= pos && pos < count
        result = self[pos]
        removeObjectAtIndex(pos)
        result
      else
        nil
      end
    end
    
    def delete_if(&block)
      reject!(&block)
      self
    end
    
    def reject!
      indexes = OSX::NSMutableIndexSet.alloc.init
      each_with_index {|i,n| indexes.addIndex(n) if yield(i) }
      if indexes.count > 0
        removeObjectsAtIndexes(indexes)
        self
      else
        nil
      end
    end
    
    def each_index
      each_with_index {|i,n| yield(n) }
    end
    
    def empty?
      count == 0
    end
    
    def fetch(*args)
      count = self.count
      len = args.length
      if len == 0 || len > 2
        raise ArgumentError, "wrong number of arguments (#{len}) for 2)"
      end
      index = args.first
      unless index.is_a? Numeric
        raise TypeError, "can't convert #{index.class} into Integer"
      end
      index = index.to_i
      index += count if index < 0
      if 0 <= index && index < count
        objectAtIndex(index)
      else
        if len == 2
          args[1]
        elsif block_given?
          yield
        else
          raise IndexError, "index #{args.first} out of array"
        end
      end
    end
    
    def fill(*args)
      count = self.count
      len = args.length
      len -= 1 unless block_given?
      case len
      when 0
        val = args.first
        n = -1
        map! do |i|
          n += 1
          block_given? ? yield(n) : val
        end
      when 1
        if block_given?
          first = args.first
        else
          val, first = args
        end
        case first
        when Numeric
          start = first.to_i
          start += count if start < 0
          n = -1
          map! do |i|
            n += 1
            if start <= n
              block_given? ? yield(n) : val
            else
              i
            end
          end
        when Range
          range = first
          left = range.first
          right = range.last
          left += count if left < 0
          right += count if right < 0
          right += range.exclude_end? ? 0 : 1
          if left < 0 || count < left
            raise RangeError, "#{range} out of range"
          end
          ary = []
          n = -1
          map! do |i|
            n += 1
            if left <= n && n < right
              block_given? ? yield(n) : val
            else
              i
            end
          end
          (n+1).upto(right-1) do |i|
            n += 1
            addObject(block_given? ? yield(n) : val)
          end
          self
        else
          raise TypeError, "can't convert #{first.class} into Integer"
        end
      when 2
        if block_given?
          first, len = args
        else
          val, first, len = args
        end
        start = first
        unless start.is_a? Numeric
          raise TypeError, "can't convert #{start.class} into Integer"
        end
        unless len.is_a? Numeric
          raise TypeError, "can't convert #{len.class} into Integer"
        end
        start = start.to_i
        len = len.to_i
        start += count if start < 0
        if start < 0 || count < start
          raise IndexError, "index #{first} out of array"
        end
        len = 0 if len < 0
        last = start + len
        n = -1
        map! do |i|
          n += 1
          if start <= n && n < last
            block_given? ? yield(n) : val
          else
            i
          end
        end
        (n+1).upto(last-1) do |i|
          n += 1
          addObject(block_given? ? yield(i) : val)
        end
        self
      else
        raise ArgumentError, "wrong number of arguments (#{args.length}) for 2)"
      end
    end
    
    def first(n=nil)
      if n
        if n.is_a? Numeric
          len = n.to_i
          if len < 0
            raise ArgumentError, "negative array size (or size too big)"
          end
          self[0...n]
        else
          raise TypeError, "can't convert #{n.class} into Integer"
        end
      else
        self[0]
      end
    end
    
    def flatten
      result = []
      each do |i|
        if i.is_a? OSX::NSArray
          result.concat(i.flatten)
        else
          result << i
        end
      end
      result
    end
    
    def flatten!
      flat = true
      result = NSMutableArray.alloc.init
      each do |i|
        if i.is_a? OSX::NSArray
          flat = false
          result.addObjectsFromArray(i.flatten)
        else
          result.addObject(i)
        end
      end
      if flat
        nil
      else
        setArray(result)
        self
      end
    end
    
    def include?(val)
      index(val) != nil
    end
    
    def index(*args)
      if block_given?
        each_with_index {|i,n| return n if yield(i) }
      elsif args.length == 1
        val = args.first
        each_with_index {|i,n| return n if i.isEqual(val) }
      else
        raise ArgumentError, "wrong number of arguments (#{args.length}) for 1)"
      end
      nil
    end
    
    def insert(n, *vals)
      if n  == -1
        push(*vals)
      else
        n += count + 1 if n < 0
        self[n, 0] = vals
      end
      self
    end

    def join(sep=$,)
      s = ''
      each do |i|
        s += sep if sep && !s.empty?
        if i == self
          s += '[...]'
        elsif i.is_a? OSX::NSArray
          s += i.join(sep)
        else
          s += i.to_s
        end
      end
      s
    end
    
    def last(n=nil)
      if n
        if n.is_a? Numeric
          len = n.to_i
          if len < 0
            raise ArgumentError, "negative array size (or size too big)"
          end
          if len == 0
            []
          elsif len >= count
            to_a
          else
            self[(-len)..-1]
          end
        else
          raise TypeError, "can't convert #{n.class} into Integer"
        end
      else
        self[-1]
      end
    end
    
    def pack(template)
      to_ruby.pack(template)
    end
    
    def pop
      if count > 0
        result = lastObject
        removeLastObject
        result
      else
        nil
      end
    end

    def push(*args)
      case args.length
      when 0
        ;
      when 1
        addObject(args.first)
      else
        addObjectsFromArray(args)
      end
      self
    end
    
    def rassoc(key)
      each do |i|
        if i.is_a? OSX::NSArray
          if i.count >= 1
            return i.to_a if i[1].isEqual(key)
          end
        end
      end
      nil
    end
    
    def replace(another)
      setArray(another)
      self
    end
    
    def reverse
      result = []
      reverse_each {|i| result << i }
      result
    end
    
    def reverse!
      result = NSMutableArray.alloc.init
      reverse_each {|i| result.addObject(i) }
      setArray(result)
      self
    end
    
    def rindex(*args)
      if block_given?
        n = count
        reverse_each do |i|
          n -= 1
          return n if yield(i)
        end
      elsif args.length == 1
        val = args.first
        n = count
        reverse_each do |i|
          n -= 1
          return n if i.isEqual(val)
        end
      else
        raise ArgumentError, "wrong number of arguments (#{args.length}) for 1)"
      end
      nil
    end
    
    def shift
      unless empty?
        result = objectAtIndex(0)
        removeObjectAtIndex(0)
        result
      else
        nil
      end
    end

    def size
      count
    end
    alias_method :length, :size
    alias_method :nitems, :size
    
    def slice(*args)
      self[*args]
    end
    
    def slice!(*args)
      _read_impl(:slice!, args)
    end
    
    def sort(&block)
      to_a.sort(&block)
    end
    
    def sort!(&block)
      setArray(to_a.sort(&block))
      self
    end
    
    def to_splat
      to_a
    end
    
    def transpose
      if count == 0
        []
      else
        len = objectAtIndex(0).count
        each do |i|
          unless i.is_a? OSX::NSArray
            raise TypeError, "can't convert #{i.class} into Array"
          end
          if i.count != len
            raise IndexError, "element size differs (#{i.count} should be #{len})"
          end
        end
        result = []
        len.times do |n|
          cur = []
          each {|i| cur << i.objectAtIndex(n) }
          result << cur
        end
        result
      end
    end
    
    def uniq
      result = OSX::NSMutableArray.alloc.init
      each {|i| result.addObject(i) unless result.include?(i) }
      result
    end
    
    def uniq!
      len = count
      if len > 1
        index = 0
        while index < count - 1
          removeObject_inRange(objectAtIndex(index), OSX::NSRange.new(index+1, count-index-1))
          index += 1
        end
        if len == count
          nil
        else
          self
        end
      else
        nil
      end
    end
    
    def unshift(*args)
      if count == 0
        push(*args)
      else
        case args.length
        when 0
          ;
        when 1
          insertObject_atIndex(args.first, 0)
        else
          indexes = OSX::NSIndexSet.indexSetWithIndexesInRange(NSRange.new(0, args.length))
          insertObjects_atIndexes(args, indexes)
        end
        self
      end
    end
    
    def values_at(*indexes)
      result = []
      indexes.each {|i| result << self[i] }
      result
    end
    alias_method :indexes, :values_at
    alias_method :indices, :values_at

    private
    
    def _read_impl(method, args)
      slice = method == :slice!
      count = self.count
      case args.length
      when 1
        first = args.first
        case first
        when Numeric
          index = first.to_i
          index += count if index < 0
          if 0 <= index && index < count
            result = objectAtIndex(index)
            removeObjectAtIndex(index) if slice
            result
          else
            nil
          end
        when Range
          range = OSX::NSRange.new(first, count)
          loc = range.location
          if 0 <= loc && loc < count
            indexes = OSX::NSIndexSet.indexSetWithIndexesInRange(range)
            result = objectsAtIndexes(indexes)
            removeObjectsAtIndexes(indexes) if slice
            result.to_a
          else
            if slice
              raise RangeError, "#{first} out of range"
            end
            nil
          end
        else
          raise TypeError, "can't convert #{args.first.class} into Integer"
        end
      when 2
        start, len = args
        unless start.is_a? Numeric
          raise TypeError, "can't convert #{start.class} into Integer"
        end
        unless len.is_a? Numeric
          raise TypeError, "can't convert #{len.class} into Integer"
        end
        start = start.to_i
        len = len.to_i
        if len < 0
          if slice
            raise IndexError, "negative length (#{args[1]})"
          end
          nil
        else
          range = start...(start + len)
          _read_impl(method, [range])
        end
      else
        raise ArgumentError, "wrong number of arguments (#{args.length}) for 2)"
      end
    end    
  end

  # NSArray additions
  class NSArray
    include OSX::OCObjWrapper

    def dup
      mutableCopy
    end
    
    def clone
      obj = dup
      obj.freeze if frozen?
      obj.taint if tainted?
      obj
    end

    # enable to treat as Array
    def to_ary
      to_a
    end

    # comparison between Ruby Array and Cocoa NSArray
    def ==(other)
      if other.is_a? OSX::NSArray
        isEqualToArray?(other)
      elsif other.respond_to? :to_ary
        to_a == other.to_ary
      else
        false
      end
    end

    def <=>(other)
      if other.respond_to? :to_ary
        to_a <=> other.to_ary
      else
        nil
      end
    end

    # responds to Ruby String methods
    alias_method :_rbobj_respond_to?, :respond_to?
    def respond_to?(mname, private = false)
      Array.public_method_defined?(mname) or _rbobj_respond_to?(mname, private)
    end

    alias_method :objc_method_missing, :method_missing
    def method_missing(mname, *args, &block)
      ## TODO: should test "respondsToSelector:"
      if Array.public_method_defined?(mname)
        # call as Ruby array
        rcv = to_a
        org_val = rcv.dup
        result = rcv.send(mname, *args, &block)
        # bang methods modify receiver itself, need to set the new value.
        # if the receiver is immutable, NSInvalidArgumentException raises.
        if rcv != org_val
          setArray(rcv)
        end
      else
        # call as objc array
        result = objc_method_missing(mname, *args)
      end
      result
    end
  end
  class NSArray
    include NSArrayAttachment
  end

  # For NSDictionary duck typing
  module NSDictionaryAttachment
    include Enumerable

    def each
      iter = keyEnumerator
      while key = iter.nextObject
        yield([key, objectForKey(key)])
      end
      self
    end

    def each_pair
      iter = keyEnumerator
      while key = iter.nextObject
        yield(key, objectForKey(key))
      end
      self
    end
    
    def each_key
      iter = keyEnumerator
      while key = iter.nextObject
        yield(key)
      end
      self
    end
    
    def each_value
      iter = objectEnumerator
      while obj = iter.nextObject
        yield(obj)
      end
      self
    end
    
    def [](key)
      result = objectForKey(key)
      if result
        result
      else
        default(key)
      end
    end

    def []=(key, obj)
      setObject_forKey(obj, key)
      obj
    end
    alias_method :store, :[]=
    
    def clear
      removeAllObjects
      self
    end
    
    def default(*args)
      if args.length <= 1
        if @default_proc
          @default_proc.call(self, args.first)
        elsif @default
          @default
        else
          nil
        end
      else
        raise ArgumentError, "wrong number of arguments (#{args.length}) for 2)"
      end
    end
    
    def default=(value)
      @default = value
    end
    
    def default_proc
      @default_proc
    end
    
    def default_proc=(value)
      @default_proc = value
    end
    
    def delete(key)
      obj = objectForKey(key)
      if obj
        removeObjectForKey(key)
        obj
      else
        if block_given?
          yield(key)
        else
          nil
        end
      end
    end
    
    def delete_if(&block)
      reject!(&block)
      self
    end
    
    def reject!
      result = nil
      each do |key,value|
        if yield(key, value)
          removeObjectForKey(key)
          result = self
        end
      end
      result
    end
    
    def empty?
      count == 0
    end
    
    def has_key?(key)
      objectForKey(key) != nil
    end
    alias_method :include?, :has_key?
    alias_method :key?, :has_key?
    alias_method :member?, :has_key?
    
    def has_value?(value)
      each_value {|i| return true if i.isEqual?(value) }
      false
    end
    alias_method :value?, :has_value?
    
    def invert
      result = {}
      each_pair {|key,value| result[value] = key }
      result
    end
    
    def key(val)
      each_pair {|key,value| return key if value.isEqual?(val) }
      nil
    end
    
    def keys
      allKeys.to_a
    end

    def size
      count
    end
    alias_method :length, :size
    
    def rehash; self; end
    
    def reject(&block)
      to_hash.delete_if(&block)
    end
    
    def replace(other)
      setDictionary(other)
      self
    end

    def values
      allValues.to_a
    end
  end

  # NSDictionary additions
  class NSDictionary
    include OSX::OCObjWrapper

    def dup
      mutableCopy
    end
    
    def clone
      obj = dup
      obj.freeze if frozen?
      obj.taint if tainted?
      obj
    end
    
    # enable to treat as Hash
    def to_hash
      h = {}
      each {|k,v| h[k] = v }
      h
    end
    
    # comparison between Ruby Hash and Cocoa NSDictionary
    def ==(other)
      if other.is_a? OSX::NSDictionary
        isEqualToDictionary?(other)
      elsif other.respond_to? :to_hash
        to_hash == other.to_hash
      else
        false
      end
    end

    def <=>(other)
      if other.respond_to? :to_hash
        to_hash <=> other.to_hash
      else
        nil
      end
    end

    # responds to Ruby Hash methods
    alias_method :_rbobj_respond_to?, :respond_to?
    def respond_to?(mname, private = false)
      Hash.public_method_defined?(mname) or _rbobj_respond_to?(mname, private)
    end

    alias_method :objc_method_missing, :method_missing
    def method_missing(mname, *args, &block)
      ## TODO: should test "respondsToSelector:"
      if Hash.public_method_defined?(mname)
        # call as Ruby hash
        rcv = to_hash
        org_val = rcv.dup
        result = rcv.send(mname, *args, &block)
        # bang methods modify receiver itself, need to set the new value.
        # if the receiver is immutable, NSInvalidArgumentException raises.
        if rcv != org_val
          setDictionary(rcv)
        end
      else
        # call as objc dictionary
        result = objc_method_missing(mname, *args)
      end
      result
    end
  end
  class NSDictionary
    include NSDictionaryAttachment
  end

  class NSUserDefaults
    def [] (key)
      self.objectForKey(key)
    end

    def []= (key, obj)
      self.setObject_forKey(obj, key)
    end

    def delete (key)
      self.removeObjectForKey(key)
    end
  end

  # NSData additions
  class NSData
    def rubyString
      cptr = self.bytes
      return cptr.bytestr( self.length )
    end
  end

  # NSIndexSet additions
  class NSIndexSet
    def to_a
      result = []
      index = self.firstIndex
      until index == OSX::NSNotFound
        result << index
        index = self.indexGreaterThanIndex(index)
      end
      return result
    end
  end

  # NSEnumerator additions
  class NSEnumerator
    def to_a
      self.allObjects.to_a
    end
  end

  # NSNumber additions
  class NSNumber
    def to_i
      self.stringValue.to_s.to_i
    end

    def to_f
      self.floatValue
    end
    
    def ==(other)
      if other.is_a? NSNumber
        isEqualToNumber?(other)
      elsif other.is_a? Numeric
        if OSX::CFNumberIsFloatType(self)
          to_f == other
        else
          to_i == other
        end
      else
        false
      end
    end

    def <=>(other)
      if other.is_a? NSNumber
        compare(other)
      elsif other.is_a? Numeric
        if OSX::CFNumberIsFloatType(self)
          to_f <=> other
        else
          to_i <= other
        end
      else
        nil
      end
    end
  end

  # NSDate additions
  class NSDate
    def to_time
      Time.at(self.timeIntervalSince1970)
    end
  end

  # NSObject additions
  class NSObject
    def to_ruby
      case self 
      when OSX::NSDate
        self.to_time
      when OSX::NSCFBoolean
        self.boolValue
      when OSX::NSNumber
        OSX::CFNumberIsFloatType(self) ? self.to_f : self.to_i
      when OSX::NSString
        self.to_s
      when OSX::NSAttributedString
        self.string.to_s
      when OSX::NSArray
        self.map { |x| x.is_a?(OSX::NSObject) ? x.to_ruby : x }
      when OSX::NSDictionary
        h = {}
        self.each do |x, y| 
          x = x.to_ruby if x.is_a?(OSX::NSObject)
          y = y.to_ruby if y.is_a?(OSX::NSObject)
          h[x] = y
        end
        h
      else
        self
      end
    end
  end
end
