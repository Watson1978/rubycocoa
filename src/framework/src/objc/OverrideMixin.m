/* 
 * Copyright (c) 2006-2007, The RubyCocoa Project.
 * Copyright (c) 2001-2006, FUJIMOTO Hisakuni.
 * All Rights Reserved.
 *
 * RubyCocoa is free software, covered under either the Ruby's license or the 
 * LGPL. See the COPYRIGHT file for more information.
 */

#import <Cocoa/Cocoa.h>
#import <stdarg.h>
#import <pthread.h>
#import "OverrideMixin.h"
#import "RBObject.h"
#import "RBSlaveObject.h"
#import "internal_macros.h"
#import "RBClassUtils.h"
#import "ocdata_conv.h"
#import "BridgeSupport.h"
#import "st.h"
#import <objc/objc-runtime.h>
#import "mdl_osxobjc.h"
#import "objc_compat.h"

#define OVMIX_LOG(fmt, args...) DLOG("OVMIX", fmt, ##args)

static SEL super_selector(SEL a_sel)
{
  char selName[1024];

  snprintf (selName, sizeof selName, "super:%s", sel_getName(a_sel));
  return sel_registerName(selName);
}

static IMP super_imp(id rcv, SEL a_sel, IMP origin_imp)
{
  IMP ret = NULL;
  Class klass = [rcv class];

  while (klass = [klass superclass]) {
    ret = [klass instanceMethodForSelector: a_sel];
    if (ret && ret != origin_imp)
      return ret;
  }
  return NULL;
}

static id slave_obj_new(id rcv)
{
  return [[RBObject alloc] initWithClass: [rcv class] masterObject: rcv];
}

/**
 *  accessor for instance variables
 **/

static void set_slave(id rcv, id slave)
{
  object_setInstanceVariable(rcv, "m_slave", slave);
}

static id get_slave(id rcv)
{
  id ret;
  object_getInstanceVariable(rcv, "m_slave", (void*)(&ret));
  return ret;
}

void release_slave(id rcv)
{
  [get_slave(rcv) release];
}

/**
 * ruby method handler
 **/

/* Implemented in RBObject.m for now, still private. */
VALUE rbobj_call_ruby(id rbobj, SEL selector, VALUE args);

static void
ovmix_ffi_closure_done(ffi_cif* cif, void* resp, void** args, void* userdata)
{
  char *retval_octype = *(char **)userdata;
  if (*retval_octype == _C_ID)
    [*(id *)resp retain];
}

static void
ovmix_ffi_closure(ffi_cif* cif, void* resp, void** args, void* userdata)
{
  char *retval_octype;
  char **args_octypes;
  VALUE rb_args;
  unsigned i;
  VALUE retval;

  retval_octype = *(char **)userdata;

  if (!IS_MAIN_THREAD()) {
    rb_warning("Closure `%s' called from another thread - forwarding it to the main thread", *(char **)args[1]);
    ffi_dispatch_closure_in_main_thread(ovmix_ffi_closure, cif, resp, args, userdata, ovmix_ffi_closure_done);
    if (*retval_octype == _C_ID)
      [*(id *)resp autorelease];
    return;
  }

  args_octypes = ((char **)userdata) + 1;
  rb_args = rb_ary_new2(cif->nargs - 2);

  OVMIX_LOG("ffi_closure cif %p nargs %d sel '%s'", cif, cif->nargs, *(SEL *)args[1]); 

  for (i = 2; i < cif->nargs; i++) {
    VALUE arg;

    if (!ocdata_to_rbobj(Qfalse, args_octypes[i - 2], args[i], &arg, NO))
      rb_raise(rb_eRuntimeError, "Can't convert Objective-C argument #%d of octype '%s' to Ruby value", i - 2, args_octypes[i - 2]);

    OVMIX_LOG("converted arg #%d of type '%s' to Ruby value %p", i - 2, args_octypes[i - 2], arg);

    rb_ary_store(rb_args, i - 2, arg);
  }

  OVMIX_LOG("calling Ruby method `%s' on %@...", *(char **)args[1], *(id *)args[0]);
  retval = rbobj_call_ruby(*(id *)args[0], *(SEL *)args[1], rb_args);
  OVMIX_LOG("calling Ruby method done, retval %p", retval);

  // Make sure to sync boxed pointer ivars.
  for (i = 2; i < cif->nargs; i++) {
    struct bsBoxed *bs_boxed;
    if (is_boxed_ptr(args_octypes[i - 2], &bs_boxed)) {
      VALUE arg = RARRAY(rb_args)->ptr[i - 2];
      rb_bs_boxed_get_data(arg, bs_boxed->encoding, NULL, NULL, NO);
    }
  }

  if (*encoding_skip_modifiers(retval_octype) != _C_VOID) {
    if (!rbobj_to_ocdata(retval, retval_octype, resp, YES))
      rb_raise(rb_eRuntimeError, "Can't convert return Ruby value to Objective-C value of octype '%s'", retval_octype);
  }
}

static struct st_table *ffi_imp_closures;
static pthread_mutex_t ffi_imp_closures_lock;

static IMP 
ovmix_imp_for_type(const char *type)
{
  BOOL ok;
  void *closure;
  IMP imp;
  unsigned i, argc;
  char *retval_type;
  char **arg_types;
  char **octypes;

  OVMIX_LOG("retrieving closure imp for method type '%s'", type);

  pthread_mutex_lock(&ffi_imp_closures_lock);
  imp = NULL;
  ok = st_lookup(ffi_imp_closures, (st_data_t)type, (st_data_t *)&imp);
  pthread_mutex_unlock(&ffi_imp_closures_lock); 
  if (ok)
    return imp;

  decode_method_encoding(type, nil, &argc, &retval_type, &arg_types, NO);

  octypes = (char **)malloc(sizeof(char *) * (argc + 1)); /* first int is retval octype, then arg octypes */
  ASSERT_ALLOC(octypes);
  for (i = 0; i < argc; i++) {
    if (i >= 2)
      octypes[i - 1] = arg_types[i];
  }
  octypes[0] = retval_type;

  closure = ffi_make_closure(retval_type, (const char **)arg_types, argc, ovmix_ffi_closure, octypes);

  pthread_mutex_lock(&ffi_imp_closures_lock);
  imp = NULL;
  ok = st_lookup(ffi_imp_closures, (st_data_t)type, (st_data_t *)&imp);
  if (!ok)
    st_insert(ffi_imp_closures, (st_data_t)type, (st_data_t)closure);
  pthread_mutex_unlock(&ffi_imp_closures_lock);
  if (ok) {
    if (arg_types != NULL) {
      for (i = 0; i < argc; i++)
        free(arg_types[i]);
      free(arg_types);
    }
    free(retval_type);
    free(octypes);   
    free(closure);
    closure = imp;
  }

  return closure;
}

/**
 * instance methods implementation
 **/

static id imp_slave (id rcv, SEL method)
{
  return get_slave(rcv);
}

@interface NSObject (AliasedCopyWithZone)
- (id)__copyWithZone:(NSZone *)zone;
@end

static id imp_copyWithZone (id rcv, SEL method, NSZone *zone)
{
  id copy = [rcv __copyWithZone:zone];
  set_slave(copy, nil);
  return copy;
}

static id imp_rbobj (id rcv, SEL method)
{
  id slave = get_slave(rcv);
  if (slave == nil) {
    // Lazily create the slave, because the traditional allocation methods that 
    // we hook might not have been called.
    slave = slave_obj_new(rcv);
    set_slave(rcv, slave);
  }
  return (id)[slave __rbobj__];
}

static BOOL imp_respondsToSelector (id rcv, SEL method, SEL arg0)
{
  BOOL ret;
  IMP simp = super_imp(rcv, method, (IMP)imp_respondsToSelector);
 
  ret = ((BOOL (*)(id, SEL, SEL))simp)(rcv, method, arg0);
  if (!ret) {
    id slave = get_slave(rcv);
    ret = [slave respondsToSelector: arg0];
  }
  return ret;
}

static id imp_methodSignatureForSelector (id rcv, SEL method, SEL arg0)
{
  id ret;
  IMP simp = super_imp(rcv, method, (IMP)imp_methodSignatureForSelector);
  id slave = get_slave(rcv);
  ret = (*simp)(rcv, method, arg0);
  if (ret == nil)
    ret = [slave methodSignatureForSelector: arg0];
  return ret;
}

static id imp_forwardInvocation (id rcv, SEL method, NSInvocation* arg0)
{
  IMP simp = super_imp(rcv, method, (IMP)imp_forwardInvocation);
  id slave = get_slave(rcv);

  if ([slave respondsToSelector: [arg0 selector]])
    [slave forwardInvocation: arg0];
  else
    (*simp)(rcv, method, arg0);
  return nil;
}

static id imp_valueForUndefinedKey (id rcv, SEL method, NSString* key)
{
  id ret = nil;
  id slave = get_slave(rcv);

  if ([slave respondsToSelector: @selector(rbValueForKey:)])
    ret = (id)[rcv performSelector: @selector(rbValueForKey:) withObject: key];
  else
    ret = [rcv performSelector: super_selector(method) withObject: key];
  return ret;
}

static void imp_setValue_forUndefinedKey (id rcv, SEL method, id value, NSString* key)
{
  id slave = get_slave(rcv);
  id dict;

  /* In order to avoid ObjC values to be autorelease'd while they are still proxied in the
     Ruby world, we keep them in an internal hash. */
  if (object_getInstanceVariable(rcv, "__rb_kvc_dict__", (void *)&dict) == NULL) {
    dict = [[NSMutableDictionary alloc] init];
    object_setInstanceVariable(rcv, "__rb_kvc_dict__", dict);
  }

  if ([slave respondsToSelector: @selector(rbSetValue:forKey:)]) {
    [slave performSelector: @selector(rbSetValue:forKey:) withObject: value withObject: key];
    if (value == nil) {
      [dict removeObjectForKey:key];
    }
    else {
      [dict setObject:value forKey:key];
    }
  }
  else
    [rcv performSelector: super_selector(method) withObject: value withObject: key];
}

/**
 * class methods implementation
 **/
static id imp_c_alloc(Class klass, SEL method)
{
  id new_obj;
  id slave;

  new_obj = class_createInstance(klass, 0);
  slave = slave_obj_new(new_obj);
  set_slave(new_obj, slave);
  return new_obj;
}

static id imp_c_allocWithZone(Class klass, SEL method, NSZone* zone)
{
  // XXX: use zone
  return imp_c_alloc(klass, method);
}

void 
ovmix_register_ruby_method(Class klass, SEL method, BOOL direct_override)
{
  Method me;
  IMP me_imp, imp;
  SEL me_name;
  char *me_types;

  me = class_getInstanceMethod(klass, method);
  // warn if trying to override a method that isn't a member of the specified class
  if (me == NULL)
    rb_raise(rb_eRuntimeError, "could not add '%s' to class '%s': Objective-C cannot find it in the superclass", (char *)method, class_getName(klass));
    
  me_imp = method_getImplementation(me);
  me_name = method_getName(me);
  me_types = strdup(method_getTypeEncoding(me));

  // override method
  OVMIX_LOG("Registering %sRuby method by selector '%s' types '%s'", direct_override ? "(direct override) " : "", (char *)method, me_types);
  imp = ovmix_imp_for_type(me_types);
  if (me_imp == imp) {
    OVMIX_LOG("Already registered Ruby method by selector '%s' types '%s', skipping...", (char *)method, me_types);
    return;
  }

#if MAC_OS_X_VERSION_MAX_ALLOWED > MAC_OS_X_VERSION_10_4
  if (direct_override)
    method_setImplementation(me, imp);
  else
#endif
    class_addMethod(klass, me_name, imp, me_types);

  class_addMethod(klass, super_selector(me_name), me_imp, me_types);
  
  OVMIX_LOG("Registered Ruby method by selector '%s' types '%s'", (char *)method, me_types);
}

static id imp_c_addRubyMethod(Class klass, SEL method, SEL arg0)
{
  ovmix_register_ruby_method(klass, arg0, NO);
  return nil;
}

static id imp_c_addRubyMethod_withType(Class klass, SEL method, SEL arg0, const char *type)
{
  class_addMethod(klass, sel_registerName((const char*)arg0), ovmix_imp_for_type(type), strdup(type));
  OVMIX_LOG("Registered Ruby method by selector '%s' types '%s'", (char *)arg0, type);
  return nil;
}

void install_ovmix_ivars(Class c)
{
#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_4
  struct objc_ivar_list* ivlp = NSZoneMalloc(NSDefaultMallocZone(), sizeof(struct objc_ivar));
  ivlp->ivar_count = 1;
  ivlp->ivar_list[0].ivar_name = "m_slave";
  ivlp->ivar_list[0].ivar_type = "@";
  ivlp->ivar_list[0].ivar_offset = c->instance_size;
  c->instance_size += ocdata_size("@");
#ifdef __LP64__
  ivlp->ivar_list[0].space = 0;
#endif
  c->ivars = ivlp;
#else
  class_addIvar(c, "m_slave", ocdata_size("@"), 0, "@");
#endif
}

void install_ovmix_methods(Class c)
{
  class_addMethod(c, @selector(__slave__), (IMP)imp_slave, "@4@4:8");
  class_addMethod(c, @selector(__rbobj__), (IMP)imp_rbobj, "L4@4:8");
  class_addMethod(c, @selector(respondsToSelector:), (IMP)imp_respondsToSelector, "c8@4:8:12");
  class_addMethod(c, @selector(methodSignatureForSelector:), (IMP)imp_methodSignatureForSelector, "@8@4:8:12");
  class_addMethod(c, @selector(forwardInvocation:), (IMP)imp_forwardInvocation, "v8@4:8@12");
  class_addMethod(c, @selector(valueForUndefinedKey:), (IMP)imp_valueForUndefinedKey, "@12@0:4@8");
  class_addMethod(c, @selector(setValue:forUndefinedKey:), (IMP)imp_setValue_forUndefinedKey, "v16@0:4@8@12");
}

void install_ovmix_hooks(Class c)
{
  if (class_respondsToSelector(c, @selector(copyWithZone:))) {
    Method copy_method = class_getInstanceMethod(c, @selector(copyWithZone:));
    if (copy_method != NULL) {
      class_addMethod(c, @selector(__copyWithZone:), method_getImplementation(copy_method), "@8@4:8^{_NSZone=}12");
      class_addMethod(c, @selector(copyWithZone:), (IMP)imp_copyWithZone, "@8@4:8^{_NSZone=}12");
    }
  }
}

static inline void install_ovmix_pure_class_methods(Class c)
{
  class_addMethod(c->isa, @selector(addRubyMethod:), (IMP)imp_c_addRubyMethod, "@4@4:8:12");
  class_addMethod(c->isa, @selector(addRubyMethod:withType:), (IMP)imp_c_addRubyMethod_withType, "@4@4:8:12*16");
}

void install_ovmix_class_methods(Class c)
{
  class_addMethod(c->isa, @selector(alloc), (IMP)imp_c_alloc, "@4@4:8");
  class_addMethod(c->isa, @selector(allocWithZone:), (IMP)imp_c_allocWithZone, "@8@4:8^{_NSZone=}12");
}

void init_ovmix(void)
{   
  ffi_imp_closures = st_init_strtable();
  pthread_mutex_init(&ffi_imp_closures_lock, NULL);
  install_ovmix_pure_class_methods(objc_lookUpClass("NSObject"));
}

@implementation NSObject (__rbobj__)

+ (VALUE)__rbclass__
{
  return rb_const_get(osx_s_module(), rb_intern(class_getName((Class)self)));
}

@end
