# -*- mode:ruby; indent-tabs-mode:nil; coding:utf-8 -*-
require 'test/unit'
require 'osx/cocoa'
$KCODE = 'utf-8'

class TC_ObjcString < Test::Unit::TestCase

  def setup
    @nsstr = OSX::NSString.stringWithString('NSString')
  end

  # to_str convenience

  def test_autoconv
    path = OSX::NSString.stringWithString(__FILE__)
    assert_nothing_raised('NSString treat as RubyString with "to_str"') {
      open(path) {"no operation"}
    }
  end

  # comparison between Ruby String and Cocoa String

  def test_comparison
    # receiver: OSX::NSString
    assert_equal(0, @nsstr <=> 'NSString', '1-1.NSStr <=> Str -> true')
    assert_not_equal(0, @nsstr <=> 'RBString', '1-2.NSStr <=> Str -> false')
    assert(@nsstr == 'NSString', '1-3.NSStr == Str -> true')
    assert(!(@nsstr == 'RBString'), '1-4.NSStr == Str -> false')
    # receiver: String
    assert_equal(0, 'NSString' <=> @nsstr, '2-1.Str <=> NSStr -> true')
    assert_not_equal(0, 'nsstring' <=> @nsstr, '2-2.Str <=> NSStr -> false')
    assert('NSString' == @nsstr, '2-3.Str == NSStr -> true')
    assert(!('RBString' == @nsstr), '2-4.Str == NSStr -> false')
  end

  # forwarding to Ruby String

  def test_respond_to
    assert_respond_to(@nsstr, :ocm_send, 'should respond to "OSX::ObjcID#ocm_send"')
    assert_respond_to(@nsstr, :gsub, 'should respond to "String#gsub"')
    assert_respond_to(@nsstr, :+, 'should respond to "String#+"')
    assert(!@nsstr.respond_to?(:_xxx_not_defined_method_xxx_), 
      'should not respond to undefined method in String')
  end

  def test_call_string_method
    str = ""
    assert_nothing_raised() {str = @nsstr + 'Appended'}
    assert_equal('NSStringAppended', str) 
  end

  def test_immutable
    assert_raise(OSX::OCException, 'cannot modify immutable string') {
      @nsstr.gsub!(/S/, 'X')
    }
    assert_equal('NSString', @nsstr.to_s, 'value not changed on error(gsub!)')
    assert_raise(OSX::OCException, 'cannot modify immutable string') {
      @nsstr << 'Append'
    }
    assert_equal('NSString', @nsstr.to_s, 'value not changed on error(<<!)')
  end

  def test_mutable
    str = OSX::NSMutableString.stringWithString('NSMutableString')
    assert_nothing_raised('can modify mutable string') {
      str.gsub!(/S/, 'X')}
    assert_equal('NXMutableXtring', str.to_s)
  end

  def test_length
    str = OSX::NSString.stringWithString('日本語の文字列')
    assert_equal(7, str.length)
  end

end
