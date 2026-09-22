project(
    'io.github.agornostal.econnect',
    'vala', 'c',
    version: '0.1.0',
    meson_version: '>= 0.61',
    license: 'GPL-3.0-or-later',
)

app_id = meson.project_name()
gnome = import('gnome')

add_project_arguments(
    '-DGETTEXT_PACKAGE="@0@"'.format(app_id),
    '-DG_LOG_DOMAIN="EConnect"',
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
    include_directories: include_directories('.'),
    sources: constants_vala,
)

subdir('src')
subdir('data')
