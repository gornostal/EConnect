metadata_conf = configuration_data()
metadata_conf.set('APP_ID', app_id)
metadata_conf.set('VERSION', meson.project_version())

desktop_file = configure_file(
    input: app_id + '.desktop.in',
    output: app_id + '.desktop',
    configuration: metadata_conf,
    install: true,
    install_dir: get_option('datadir') / 'applications',
)

metainfo_file = configure_file(
    input: app_id + '.metainfo.xml.in',
    output: app_id + '.metainfo.xml',
    configuration: metadata_conf,
    install: true,
    install_dir: get_option('datadir') / 'metainfo',
)

# 32, 48, 64 and 128 are what AppCenter requires; 256 is there for HiDPI.
foreach size : ['32', '48', '64', '128', '256']
    install_data(
        'icons' / size / app_id + '.png',
        install_dir: get_option('datadir') / 'icons' / 'hicolor' / size + 'x' + size / 'apps',
    )
endforeach

gnome.post_install(
    gtk_update_icon_cache: true,
    update_desktop_database: true,
)

# The same checks AppCenter runs on submission, so a broken desktop entry or
# metainfo file fails here rather than in review.
desktop_file_validate = find_program('desktop-file-validate', required: false)
if desktop_file_validate.found()
    test(
        'desktop-file-validate',
        desktop_file_validate,
        args: [desktop_file],
        suite: 'metadata',
    )
endif

appstreamcli = find_program('appstreamcli', required: false)
if appstreamcli.found()
    test(
        'appstreamcli-validate',
        appstreamcli,
        args: ['validate', '--no-net', '--explain', '--pedantic', metainfo_file],
        suite: 'metadata',
    )
endif
