project('io.github.trbjo.bobdock', 'vala', 'c',
        version: '0.5.0',
        default_options:
    [
      'buildtype=release',
      'optimization=2',
      'b_lto=true',
      'prefix=/usr/local'
    ]
)

glib_dep = dependency('glib-2.0', version: '>= 2.66.0')
gtk_dep = dependency('gtk4', version: '>= 4.0.0')
gtk_wayland_dep = dependency('gtk4-wayland', version: '>= 4.0.0')
gtk4_layer_shell_dep = dependency('gtk4-layer-shell-0', version: '>= 0.6.0')
gio_dep = dependency('gio-2.0', version: '>= 2.66.0')
json_glib_dep = dependency('json-glib-1.0', version: '>= 1.8.0')

gio_unix_dep = dependency('gio-unix-2.0')

sources = files(
    'src/appitem.vala',
    'src/appsettings.vala',
    'src/background.vala',
    'src/interfaces.vala',
    'src/dock.vala',
    'src/icon.vala',
    'src/folderitem.vala',
    'src/item-container.vala',
    'src/main.vala',
    'src/popup-manager.vala',
    'src/splitter-item.vala',
    'src/sway-connector.vala',
    'src/sway-ipc.vala',
    'src/thumbnail.vala',
    'src/trashitem.vala',
    'src/utils.vala',
    'src/window.vala',
)

gnome = import('gnome')

gresources = gnome.compile_resources(
    'gresources', join_paths ('data', meson.project_name() + '.gresource.xml'),
    source_dir: 'data',
)


add_project_link_arguments('-Wl,--as-needed', language: 'c')
add_project_link_arguments('-Wl,-z,now', language: 'c')
add_project_arguments('-s', language: 'c')


bobdock = executable('bobdock',
    sources + gresources,
    dependencies: [
        json_glib_dep,
        gio_dep,
        gio_unix_dep,
        glib_dep,
        gtk4_layer_shell_dep,
        gtk_dep,
        gtk_wayland_dep
    ],
    link_args: ['-lm'],
    c_args: ['-w'],
    install: true
)

install_data(
    join_paths(meson.current_source_dir(), 'data', 'io.github.trbjo.bobdock.gschema.xml'),
    install_dir: get_option('prefix') / get_option('datadir') / 'glib-2.0' / 'schemas'
)

install_data('resources/bobdock.service',
  install_dir: join_paths(get_option('datadir'), 'lib', 'systemd', 'system')
)


gnome.post_install(glib_compile_schemas: true)

custom_target(
  'run_custom_command',
  command: ['strip', bobdock],
output: 'stripped',
  depends: bobdock,
  build_by_default: true
)
