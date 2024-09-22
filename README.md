# BobDock

BobDock is a dock for Wayland-based Linux desktops, written in Vala using GTK4.

## Features

- **Wayland-only**: Designed specifically for Wayland compositors using the wlr-layershell protocol.
- **High Performance**: Utilizes GTK4 for hardware-accelerated rendering via OpenGL or Vulkan, ensuring a smooth user experience.
- **Sway Integration**: Includes a desktop connector for the Sway window manager, providing detailed container information.
- **Extensible**: Features an `IDesktopConnector` interface, allowing for potential future support of other desktop environments.
- **Customizable Appearance**: Comes with a polished default CSS style, but allows full customization for users to create their own looks.
- **Folder Support**: Includes a FolderItem feature similar to macOS, with folder thumbnails, file monitoring, and content popovers.
- **Drag and Drop**: Supports drag and drop functionality, highlighting compatible applications for dropped files.
- **Auto-hide**: Can be configured to automatically hide when not in use.

## Installation

### Install Dependencies

- glib2
- wayland
- gtk4
- gtk4-layer-shell
- json-glib
- GIO Unix

### Build and Install

To build and install BobDock, run these commands:
   ```
    meson setup build
    meson compile -C build
    doas meson install -C build
    doas glib-compile-schemas /usr/local/share/glib-2.0/schemas

   ```

## Configuration

BobDock uses GSettings for configuration. The schema is located at `io.github.trbjo.bobdock`.

### Key Settings:

- `apps`: List of application desktop IDs to show in the dock
- `folders`: List of folder URIs to display in the dock
- `icon-size-range`: Min and max icon sizes in pixels

## Usage

### Auto-hide via D-Bus

You can toggle the auto-hide feature using the following D-Bus command:

```
gdbus call --session --dest io.github.trbjo.bobdock --object-path /io/github/trbjo/bobdock --method io.github.trbjo.bobdock.AutoHide
```

## Customization

To customize the appearance of BobDock, create a custom CSS file and set its path using the `css-sheet` GSettings key. Refer to the default stylesheet for guidance on available styling options.

