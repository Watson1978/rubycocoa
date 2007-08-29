require 'test/unit'
require 'osx/cocoa'

class TC_NSDictionary < Test::Unit::TestCase
  include OSX
  
  def alloc_nsdictionary
    NSMutableDictionary.alloc.init
  end
  
  def map_to_ruby(dic)
    h = {}
    dic.each_pair do |k,v|
      k = k.to_ruby if k.is_a? NSObject
      v = v.to_ruby if v.is_a? NSObject
      h[k] = v
    end
    h
  end
  
  def test_copy
    assert_nothing_raised {
      a = NSDictionary.dictionaryWithDictionary({:hoge=>111})
      b = a.dup
      b[111] = 333
      b = a.clone
      b[111] = 333
    }
  end
  
  def test_ref
    [
      [1], [1,2,3,4,5], [1,2,'3','4',5.5]
    ].each do |d|
      a = alloc_nsdictionary
      d.each {|i| a[i] = i }
      b = {}
      d.each {|i| b[i] = i }
      d.each {|i| assert_equal(b[i], a[i].to_ruby) }
    end
  end
  
  def test_equal
    [
      [1], [1,2,3,4,5], [1,2,'3','4',5.5]
    ].each do |d|
      a = alloc_nsdictionary
      d.each {|i| a[i] = i }
      b = alloc_nsdictionary
      d.each {|i| b[i] = i }
      d.each {|i| assert_equal(true, b == a) }
    end
  end
  
  def test_clear
    d = [1,2,3]
    a = alloc_nsdictionary
    d.each {|i| a[i] = i }
    a.clear
    assert_equal(0, a.length)
    assert_equal(0, a.size)
  end
  
  def test_default
    d = [1,2,3]
    a = alloc_nsdictionary
    a.default = 99
    d.each {|i| a[i] = i }
    assert_equal(99, a[5])
    assert_equal(99, a[-5])
  end
  
  def test_default_proc
    d = [1,2,3]
    a = alloc_nsdictionary
    a.default_proc = lambda {|hash,key| 99 }
    d.each {|i| a[i] = i }
    assert_equal(99, a[5])
    assert_equal(99, a[-5])
  end
  
  def test_delete
    d = [1,2,3,4,5]
    a = alloc_nsdictionary
    d.each {|i| a[i] = i }
    b = {}
    d.each {|i| b[i] = i }
    assert_equal(b.delete(3), a.delete(3))
    assert_equal(b, a.to_ruby)
    assert_equal(b.delete(99), a.delete(99))
    assert_equal(b.delete(99) { 123 }, a.delete(99) { 123 })
  end
  
  def test_delete_if
    d = [1,2,3,4,5]
    a = alloc_nsdictionary
    d.each {|i| a[i] = i }
    b = {}
    d.each {|i| b[i] = i }
    a.delete_if {|k,v| k.to_i > 3 }
    b.delete_if {|k,v| k > 3 }
    assert_equal(b, a.to_ruby)
  end
  
  def test_reject!
    d = [1,2,3,4,5]
    a = alloc_nsdictionary
    d.each {|i| a[i] = i }
    b = {}
    d.each {|i| b[i] = i }
    x = a.reject! {|k,v| k.to_i > 3 }
    y = b.reject! {|k,v| k > 3 }
    assert_equal(b, a.to_ruby)
    assert_equal(y, x.to_ruby)

    d = [1,2,3,4,5]
    a = alloc_nsdictionary
    d.each {|i| a[i] = i }
    b = {}
    x = a.reject! {|k,v| false }
    y = b.reject! {|k,v| false }
    assert_equal(y, x)
  end
  
  def test_empty?
    a = alloc_nsdictionary
    assert_equal(true, a.empty?)
    a[1] = 1
    assert_equal(false, a.empty?)
  end
  
  def test_has_key?
    [-1,3,6].each do |k|
      d = [1,2,3,4,5]
      a = alloc_nsdictionary
      d.each {|i| a[i] = i }
      b = {}
      d.each {|i| b[i] = i }
      assert_equal(b.has_key?(k), a.has_key?(k))
    end
  end
  
  def test_has_value?
    [-1,3,6].each do |v|
      d = [1,2,3,4,5]
      a = alloc_nsdictionary
      d.each {|i| a[i] = i }
      b = {}
      d.each {|i| b[i] = i }
      assert_equal(b.has_value?(v), a.has_value?(v))
    end
  end
  
  def test_invert
    d = [1,2,3,4,5]
    a = alloc_nsdictionary
    d.each {|i| a[i] = i }
    b = {}
    d.each {|i| b[i] = i }
    a = a.invert
    b = b.invert
    a = map_to_ruby(a)
    assert_equal(b, a)
  end
  
  def test_key
    d = [1,2,3,4,5]
    a = alloc_nsdictionary
    d.each {|i| a[i] = i*2 }
    d.each {|i| assert_equal(a.key(i*2).to_i, i)}
  end
  
  def test_reject
    d = [1,2,3,4,5]
    a = alloc_nsdictionary
    d.each {|i| a[i] = i }
    b = {}
    d.each {|i| b[i] = i }
    a = a.reject {|k,v| k.to_i > 3 }
    b.reject! {|k,v| k > 3 }
    a = map_to_ruby(a)
    assert_equal(b, a)
  end
  
  def test_replace
    d = [1,2,3,4,5]
    a = alloc_nsdictionary
    d.each {|i| a[i] = i }
    b = {}
    d.each {|i| b[i] = i }
    a.replace('a'=>1, 2=>3)
    b.replace('a'=>1, 2=>3)
    a = map_to_ruby(a)
    assert_equal(b, a)
  end
end
