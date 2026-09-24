project(
    'io.github.gornostal.econnect',
    'vala', 'c',
    version: '1.0.2',
    meson_version: '>= 0.61',
    license: 'MIT',
)

app_id = meson.project_name()
gnome = import('gnome')

add_project_arguments(
    '-DGETTEXT_PACKAGE="@0@"'.format(app_id),
    '-DG_LOG_DOMAIN="EConnect"',
    language: 'c',
)
# valac-generated C trips these routinely; silence them so real warnings stand out.
add_project_arguments(
    meson.get_compiler('c').get_supported_arguments(
        '-Wno-unused-but-set-variable',
        '-Wno-unused-variable',
        '-Wno-unused-function',
        '-Wno-discarded-qualifiers',
        '-Wno-incompatible-pointer-types',
        '-Wno-address',
    ),
    language: 'c',
)
add_project_arguments(
    '--target-glib=2.76',
    '--enable-experimental',
    language: 'vala',
)

core_deps = [
    dependency('glib-2.0', version: '>= 2.76'),
    dependency('gobject-2.0'),
    dependency('gio-2.0'),
    dependency('gio-unix-2.0'),
    dependency('json-glib-1.0'),
    dependency('gnutls', version: '>= 3.6'),
    meson.get_compiler('vala').find_library('posix'),
]

conf = configuration_data()
conf.set_quoted('APP_ID', app_id)
conf.set_quoted('VERSION', meson.project_version())
conf.set('APP_ID_RAW', app_id)
conf.set('VERSION_RAW', meson.project_version())
configure_file(output: 'config.h', configuration: conf)
constants_vala = configure_file(
    input: 'src/Constants.vala.in',
    output: 'Constants.vala',
    configuration: conf,
)
config_dep = declare_dependency(
    include_directories: include_directories('.', 'src/Core'),
    sources: constants_vala,
)

gresources = gnome.compile_resources(
    'econnect-resources',
    'data' / app_id + '.gresource.xml',
    source_dir: 'data',
)

subdir('src')
subdir('data')
