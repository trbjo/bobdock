public class AppItem : DockItem, MouseAble {
    public string app_id { get; protected set; }
    private DesktopAppInfo? desktop_info;
    protected string[] mime_types;

    public AppItem(AppInfo app_info) {
        if (!(app_info is DesktopAppInfo)) {
            warning("app_info does not have a .desktop file");
        }
        var desktop_info = (DesktopAppInfo)app_info;

        string label;
        string icon_name;

        if (desktop_info != null) {
            label = desktop_info.get_display_name() ?? desktop_info.get_name();
            var icon = desktop_info.get_icon();
            icon_name = icon != null ? icon.to_string() : "application-x-executable";
        } else {
            warning("Failed to create DesktopAppInfo for %s", app_info.get_name());
            label = app_id;
            icon_name = "application-x-executable";
        }

        string app_id = Utils.strip_desktop_extension(desktop_info.get_id());
        Object(user_identification: app_id, label: label, icon_name: icon_name);
        add_css_class("app-item");

        this.app_id = app_id;
        this.desktop_info = desktop_info;
        load_mime_types();
    }

    private void load_mime_types() {
        if (desktop_info == null) {
            mime_types = {};
            return;
        }

        try {
            var keyfile = new KeyFile();
            keyfile.load_from_file(desktop_info.get_filename(), KeyFileFlags.NONE);
            if (keyfile.has_key(KeyFileDesktop.GROUP, KeyFileDesktop.KEY_MIME_TYPE)) {
                mime_types = keyfile.get_string_list(KeyFileDesktop.GROUP, KeyFileDesktop.KEY_MIME_TYPE);
            } else {
                mime_types = {};
            }
        } catch (Error e) {
            warning("Failed to load MIME types for %s: %s", app_id, e.message);
            mime_types = {};
        }
    }

    public override bool can_handle_mime_type(File file, string mime_type) {
        return Utils.array_contains(mime_types, mime_type);
    }

    public override bool handle_dropped_file(File file) {
        try {
            var file_list = new GLib.List<File>();
            file_list.append(file);
            return desktop_info != null ? desktop_info.launch(file_list, null) : false;
        } catch (Error e) {
            warning("Failed to launch %s with file %s: %s", app_id, file.get_path(), e.message);
        }
        return false;
    }

    public override bool handle_click() {
        if (!visible) {
            critical("widget is not visible");
        }
        if (desktop_info == null) {
            warning("Cannot launch app: no valid DesktopAppInfo for %s", app_id);
            return false;
        }

        try {
            desktop_info.launch(null, null);
        } catch (Error e) {
            warning("Failed to launch %s: %s", app_id, e.message);
        }
        return true;
    }
}
