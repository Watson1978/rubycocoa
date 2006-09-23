# create a real project.pbxproj file by applying libruby
# configuration.

target_files = %w[
  ext/rubycocoa/extconf.rb
  framework/GeneratedConfig.xcconfig
  framework/src/objc/Version.h
]

target_files.concat Dir.glob('template/ProjectBuilder/Application/**/*.pbxproj.in').collect {|tmpl| tmpl.sub(/\.in\Z/, '')}

config_ary = [
  [ :frameworks,      @config['frameworks'] ],
  [ :ruby_header_dir, @config['ruby-header-dir'] ],
  [ :libruby_path,    @config['libruby-path'] ],
  [ :libruby_path_dirname,  File.dirname(@config['libruby-path']) ],
  [ :libruby_path_basename, File.basename(@config['libruby-path']) ],
  [ :rubycocoa_version,      @config['rubycocoa-version'] ],
  [ :rubycocoa_version_short,   @config['rubycocoa-version-short'] ],
  [ :rubycocoa_release_date, @config['rubycocoa-release-date'] ],
  [ :build_dir, framework_obj_path ],
]

# build options
cflags = '-fno-common -g -fobjc-exceptions'
ldflags = '-undefined suppress -flat_namespace'
sdkroot = ''

if @config['build-universal'] == 'yes'
  cflags << ' -arch ppc -arch i386'
  ldflags << ' -arch ppc -arch i386'

  sdkroot = '/Developer/SDKs/MacOSX10.4u.sdk'
  cflags << ' -isysroot ' << sdkroot
  ldflags << ' -Wl,-syslibroot,' << sdkroot

  # validation
  raise "ERROR: SDK \"#{sdkroot}\" does not exist." unless File.exist?(sdkroot)
  #libruby_sdk = File.join(sdkroot, @config['libruby-path'])
  libruby_sdk = @config['libruby-path']
  raise "ERROR: library \"#{libruby_sdk}\" does not exists." unless File.exist?(libruby_sdk)
end

if File.exists?('/usr/include/libxml2') and File.exists?('/usr/lib/libxml2.dylib')
    cflags << ' -I/usr/include/libxml2 -DHAS_LIBXML2 '
    ldflags << ' -lxml2 '
else
    puts "libxml2 is not available!"
end

config_ary << [ :other_cflags, cflags ]
config_ary << [ :other_ldflags, ldflags ]

target_files.each do |dst_name|
  src_name = dst_name + '.in'
  data = File.open(src_name) {|f| f.read }
  config_ary.each do |sym, str|
    data.gsub!( "%%%#{sym}%%%", str )
  end
  File.open(dst_name,"w") {|f| f.write(data) }
  $stderr.puts "create #{dst_name}"
end
