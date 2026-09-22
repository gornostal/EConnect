core_sources = files(
    'Core/Packet.vala',
    'Core/Der.vala',
    'Core/DeviceInfo.vala',
    'Core/Config.vala',
    'Core/Certificate.vala',
    'Core/Discovery.vala',
    'Core/DeviceLink.vala',
    'Core/LinkProvider.vala',
    'Core/Pairing.vala',
    'Core/Device.vala',
    'Core/Daemon.vala',
    'Core/History.vala',
    'Plugins/Plugin.vala',
    'Plugins/Ping.vala',
    'Plugins/Share.vala',
    'Plugins/Sftp.vala',
)

if get_option('cli')
    executable(
        'econnect-cli',
        files('Cli/Main.vala'),
        core_sources,
        dependencies: core_deps + [config_dep],
        install: true,
    )
endif

if get_option('gui')
    gui_deps = core_deps + [
        dependency('gtk4', version: '>= 4.10'),
        dependency('granite-7', version: '>= 7.2'),
        config_dep,
    ]
    executable(
        app_id,
        files(
            'App/Application.vala',
            'App/MainWindow.vala',
            'App/DeviceRow.vala',
            'App/DevicePage.vala',
            'App/PairDialog.vala',
            'App/ClipboardPlugin.vala',
            'App/Screenshot.vala',
            'App/Gallery.vala',
        ),
        core_sources,
        dependencies: gui_deps,
        install: true,
    )
endif
