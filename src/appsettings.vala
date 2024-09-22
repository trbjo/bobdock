namespace WayLauncherStyleProvider {
    // TODO: Remove when merged
    // https://gitlab.gnome.org/GNOME/vala/-/merge_requests/312/
    [CCode (cname = "gtk_style_context_add_provider_for_display")]
    extern static void add_style_context(Gdk.Display display, Gtk.StyleProvider provider, uint priority);

    // https://gitlab.gnome.org/GNOME/vala/-/merge_requests/312/
    [CCode (cname = "gtk_style_context_remove_provider_for_display")]
    extern static void remove_style_context(Gdk.Display display, Gtk.StyleProvider provider);
}

public class AppSettings : GLib.Object {
    private static AppSettings? instance;
    public GLib.Settings settings;

    private string _css_path;

    private AppSettings() {
        Object();
    }

    construct {
        settings = new GLib.Settings(BOBDOCK_APP_ID);
        this.settings.changed.connect(settings_changed);
        update_all();
    }

    public static AppSettings get_default() {
        if (instance == null) {
            instance = new AppSettings();
        }
        return instance;
    }

    private void settings_changed(string key) {
        switch (key) {
            case "gtk-layer-shell-edge":
                update_gtk_layer_shell_edge();
                break;
            case "auto-hide":
                update_auto_hide();
                break;
            case "css-sheet":
                update_css_sheet();
                break;
            case "icon-size-range":
                update_icon_size_range();
                break;
            case "apps":
                update_dock_apps();
                dock_apps_changed();
                break;
            case "folders":
                update_dock_folders();
                dock_folders_changed();
                break;
        }
    }

    protected void update_icon_size_range() {
        Variant variant = settings.get_value("icon-size-range");
        if (variant.is_of_type(new VariantType("(ii)"))) {
            int min, max;
            variant.get("(ii)", out min, out max);
            if (min > max) {
                warning("minimum icon size (%i) can't be larger than maximum (%i)", min, max);
                min = max;
            }
            max_icon_size = max;
            min_icon_size = min;
        }
    }

    public enum SizeTuple {
        MIN = 0,
        MAX = 1
    }

    private int _min_icon_size;
    private int _max_icon_size;

    private int min_icon_size {
        get {
            return _min_icon_size;
        }
        set {
            if (_min_icon_size != value && MIN_SIZE <= value <= max_icon_size) {
                _min_icon_size = value;
                string css = get_css_icon_size(_min_icon_size);
                icon_size_provider.load_from_string(css);
                WayLauncherStyleProvider.add_style_context(
                    Gdk.Display.get_default(),
                    icon_size_provider,
                    Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
                );
                settings.set_value("icon-size-range", new Variant("(ii)", value, max_icon_size));
            }
        }
    }

    private int max_icon_size {
        get {
            return _max_icon_size;
        }
        set {
            if (_max_icon_size != value && min_icon_size <= value <= MAX_SIZE) {
                _max_icon_size = value;
                double max_scale = ((double)_max_icon_size) / ((double)min_icon_size);
                settings.set_value("icon-size-range", new Variant("(ii)", min_icon_size, value));
                scale_factor_changed(max_scale);
            }
        }
    }

    public signal void scale_factor_changed(double scale);
    public double max_scale {
        get {
            return ((double)_max_icon_size) / ((double)min_icon_size);;
        }
        set {
            int scaled_to_pixel = (int)Math.round(value * ((double)min_icon_size));
            scaled_to_pixel = scaled_to_pixel.clamp(min_icon_size, MAX_SIZE);
            if (_max_icon_size != scaled_to_pixel) {
                max_icon_size = scaled_to_pixel;
            }
        }
    }

    public signal void autohide_changed(bool hide);
    private bool _auto_hide = false;
    public bool auto_hide {
        get {
            return _auto_hide;
        }
        set {
            if (_auto_hide != value) {
                _auto_hide = value;
                settings.set_boolean("auto-hide", value);
                autohide_changed(value);
            }
        }
    }

    public signal void layershell_edge_change(GtkLayerShell.Edge edge);
    private GtkLayerShell.Edge _layer_shell_edge = GtkLayerShell.Edge.ENTRY_NUMBER;
    public GtkLayerShell.Edge edge {
        get { return _layer_shell_edge; }
        set {
            GtkLayerShell.Edge valid_edge = valid_edges((GtkLayerShell.Edge)value);
            if (valid_edge != _layer_shell_edge) {
                _layer_shell_edge = valid_edge;
                settings.set_enum("gtk-layer-shell-edge", (int)_layer_shell_edge);
                layershell_edge_change(_layer_shell_edge);
            }
        }
    }

    private FileMonitor? file_monitor;
    private Gtk.CssProvider? css_provider;
    private static Gtk.CssProvider icon_size_provider;

    static construct {
        icon_size_provider = new Gtk.CssProvider();
    }

    private void update_css() {
        if (file_monitor != null) {
            file_monitor.changed.disconnect(on_css_file_changed);
            file_monitor.cancel();
            file_monitor = null;
        }

        if (css_provider != null) {
            WayLauncherStyleProvider.remove_style_context(Gdk.Display.get_default(), css_provider);
            css_provider = null;
        }

        css_provider = new Gtk.CssProvider();

        if (FileUtils.test(this._css_path, FileTest.EXISTS)) {
            try {
                css_provider.load_from_path(this._css_path);

                var file = File.new_for_path(this._css_path);
                file_monitor = file.monitor_file(FileMonitorFlags.NONE);
                file_monitor.changed.connect(on_css_file_changed);
            } catch (Error e) {
                warning("Error loading CSS from path: %s", e.message);
                load_default_css(css_provider);
            }
        } else {
            load_default_css(css_provider);
        }

        WayLauncherStyleProvider.add_style_context(
            Gdk.Display.get_default(),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_USER
        );
    }

    private void load_default_css(Gtk.CssProvider css_provider) {
        css_provider.load_from_resource("io/github/trbjo/bobdock/Application.css");
    }

    private void on_css_file_changed(File file, File? other_file, FileMonitorEvent event_type) {
        if (event_type == FileMonitorEvent.CHANGED || event_type == FileMonitorEvent.CREATED) {
            Idle.add(() => {
                update_css();
                return false;
            });
        }
    }

    protected void update_all() {
        update_gtk_layer_shell_edge();
        update_auto_hide();
        update_css_sheet();
        update_dock_apps();
        update_dock_folders();
        update_icon_size_range();
    }

    protected void update_css_sheet() {
        _css_path = settings.get_string("css-sheet");
        this.update_css();
    }

    protected void update_auto_hide() {
        auto_hide = settings.get_boolean("auto-hide");
    }

    protected GtkLayerShell.Edge valid_edges(GtkLayerShell.Edge input) {
        switch (input) {
            case GtkLayerShell.Edge.LEFT:
                return GtkLayerShell.Edge.LEFT;
            case GtkLayerShell.Edge.RIGHT:
                return GtkLayerShell.Edge.RIGHT;
            default:
                return GtkLayerShell.Edge.BOTTOM;
        }
    }

    protected void update_gtk_layer_shell_edge() {
        int _edge = settings.get_enum("gtk-layer-shell-edge");
        edge = (GtkLayerShell.Edge)_edge;
    }

    private string[] _dock_apps;
    public string[] dock_apps {
        get { return _dock_apps; }
        set {
            if (_dock_apps != value) {
                _dock_apps = value;
                settings.set_strv("apps", value);
                dock_apps_changed();
            }
        }
    }

    private string[] _dock_folders;
    public string[] dock_folders {
        get { return _dock_folders; }
        set {
            if (_dock_folders != value) {
                _dock_folders = value;
                settings.set_strv("folders", value);
                dock_folders_changed();
            }
        }
    }

    public signal void dock_folders_changed();
    public signal void dock_apps_changed();

    protected void update_dock_apps() {
        _dock_apps = settings.get_strv("apps");
        if (_dock_apps.length == 0) {
            _dock_apps = get_default_apps();
            settings.set_strv("apps", _dock_apps);
        }
    }

    protected void update_dock_folders() {
        _dock_folders = settings.get_strv("folders");
        if (_dock_folders.length == 0) {
            _dock_folders = get_default_folders();
            settings.set_strv("folders", _dock_folders);
        }
    }

    private string[] get_default_apps() {
        string[] default_apps = {};
        string[] mime_types = {
            "inode/directory",
            "x-scheme-handler/http",
            "text/plain",
            "image/jpeg",
            "x-scheme-handler/mailto",
            "audio/mpeg",
            "video/mp4",
            "application/pdf",
            "x-scheme-handler/terminal"
        };

        foreach (string mime_type in mime_types) {
            var app_info = GLib.AppInfo.get_default_for_type(mime_type, false);
            if (app_info != null) {
                var desktop_info = app_info as DesktopAppInfo;
                if (desktop_info != null) {
                    string app_id = Utils.strip_desktop_extension(desktop_info.get_id());
                    if (!(app_id in default_apps)) {
                        default_apps += app_id;
                    }
                }
            }
        }

        return default_apps;
    }

    private string[] get_default_folders() {
        string[] default_folders = {};

        // Get the user's download directory
        string? download_dir = Environment.get_user_special_dir(UserDirectory.DOWNLOAD);
        if (download_dir != null) {
            default_folders += File.new_for_path(download_dir).get_uri();
        }

        return default_folders;
    }

    public GLib.List<AppItem> get_app_items() {
        GLib.List<AppItem> items = new GLib.List<AppItem>();
        foreach (string app_id in _dock_apps) {
            string? file_info = Utils.find_desktop_file(app_id);
            if (file_info != null) {
                items.append(new AppItem(new DesktopAppInfo.from_filename(file_info)));
            }
        }
        return items;
    }

    public GLib.List<FolderItem> get_folder_items() {
        GLib.List<FolderItem> items = new GLib.List<FolderItem>();
        foreach (string folder_uri in _dock_folders) {
            var folder_file = File.new_for_uri(folder_uri);
            if (folder_file.query_exists()) {
                items.append(new FolderItem(folder_file.get_basename(), folder_uri));
            }
        }
        return items;
    }
}
