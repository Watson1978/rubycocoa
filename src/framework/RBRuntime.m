/** -*-objc-*-
 *
 *   $Id$
 *
 *   Copyright (c) 2001 FUJIMOTO Hisakuni <hisa@imasy.or.jp>
 *
 *   This program is free software.
 *   You can distribute/modify this program under the terms of
 *   the GNU Lesser General Public License version 2.
 *
 **/

#import <LibRuby/ruby.h>
#import <string.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSString.h>
#import <Foundation/NSBundle.h>

#import <RubyCocoa/RBObject.h>

#import <objc/objc.h>
#import <objc/objc-class.h>
#import <objc/objc-runtime.h>

#import "OverrideMixin.h"
#import "ocdata_conv.h"

#define RUBY_MAIN_NAME "rb_main.rb"

static char* rb_main_path(const char* rb_main_name)
{
  char* result;
  id path;
  id pool = [[NSAutoreleasePool alloc] init];
  NSBundle* bundle = [NSBundle mainBundle];
  if (rb_main_name == NULL) rb_main_name = RUBY_MAIN_NAME;
  path = [NSString stringWithCString: rb_main_name];
  result = strdup([[bundle pathForResource: path ofType: nil] cString]);
  [pool release];
  return result;
}

static char* resource_path()
{
  NSString* str;
  char* result;
  id pool = [[NSAutoreleasePool alloc] init];
  NSBundle* bundle = [NSBundle mainBundle];
  str = [bundle resourcePath];
  result = strdup([str cString]);
  [pool release];
  return result;
}

static char* osxobjc_resource_path()
{
  NSString* str;
  char* result;
  id pool = [[NSAutoreleasePool alloc] init];
  NSBundle* bundle = [NSBundle bundleForClass: [RBObject class]];
  str = [bundle resourcePath];
  result = strdup([str cString]);
  [pool release];
  return result;
}

int
RBApplicationMain(const char* rb_main_name, int argc, char* argv[])
{
  int private_argc;
  char* private_argv[] = {
    argv[0],
    "-I",
    resource_path(),
    "-I",
    osxobjc_resource_path(),
    rb_main_path(rb_main_name)
  };

  private_argc = sizeof(private_argv) / sizeof(char*);

  ruby_init();
  ruby_options(private_argc, private_argv);
  ruby_run();
  return 0;
}


/////

static Class objc_class_alloc(const char* name, Class super_class)
{
  Class c = malloc(sizeof(struct objc_class));
  Class isa = malloc(sizeof(struct objc_class));
  struct objc_method_list **mlp0, **mlp1;
  int i;
  const int cnt = 16;
  mlp0 = malloc(cnt * sizeof(void*));
  mlp1 = malloc(cnt * sizeof(void*));
  for (i = 0; i < cnt; i++) {
    mlp0[i] = mlp1[i] = NULL;
  }

  c->isa = isa;
  c->super_class = super_class;
  c->name = strdup(name);
  c->version = 0;
  c->info = CLS_CLASS + CLS_METHOD_ARRAY;
  c->instance_size = super_class->instance_size;
  c->ivars = NULL;
  c->methodLists = mlp0;
  c->cache = NULL;
  c->protocols = NULL;

  isa->isa = super_class->isa->isa;
  isa->super_class = super_class->isa;
  isa->name = c->name;
  isa->version = 5;
  isa->info = CLS_META + CLS_INITIALIZED + CLS_METHOD_ARRAY;
  isa->instance_size = super_class->isa->instance_size;
  isa->ivars = NULL;
  isa->methodLists = mlp1;
  isa->cache = NULL;
  isa->protocols = NULL;
  return c;
}

static void install_ivar_list(Class c)
{
  int i;
  struct objc_ivar_list* ivlp = malloc(override_mixin_ivar_list_size());
  *ivlp = *(override_mixin_ivar_list());
  for (i = 0; i < ivlp->ivar_count; i++) {
    int octype = to_octype(ivlp->ivar_list[i].ivar_type);
    ivlp->ivar_list[i].ivar_offset = c->instance_size;
    c->instance_size += ocdata_size(octype);
  }
  c->ivars = ivlp;
}

static void install_method_list(Class c)
{
  class_addMethods(c, override_mixin_method_list());
}

static void install_class_method_list(Class c)
{
  class_addMethods((c->isa), override_mixin_class_method_list());
}

Class RBOCClassNew(const char* name, Class super_class)
{
  Class c = objc_class_alloc(name, super_class);
  objc_addClass(c);
  return c;
}

Class RBOCDerivedClassNew(const char* name, Class super_class)
{
  Class c = objc_class_alloc(name, super_class);

  // init instance variable (m_proxy)
  install_ivar_list(c);

  // init instance methods
  install_method_list(c);

  // init class methods
  install_class_method_list(c);

  // add class to runtime system
  objc_addClass(c);
  return c;
}
