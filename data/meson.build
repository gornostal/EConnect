desktop_conf = configuration_data()
desktop_conf.set('APP_ID', app_id)
configure_file(
    input: app_id + '.desktop.in',
    output: app_id + '.desktop',
    configuration: desktop_conf,
    install: true,
    install_dir: get_option('datadir') / 'applications',
)
