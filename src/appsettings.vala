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
    const int MIN_SIZE = 16;
    const int MAX_SIZE = 256;

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

    public static unowned AppSettings get_default() {
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
            case "spread-factor":
                update_spread_factor();
                break;
            case "hover-label-max-length":
                update_hover_label_max_length();
                break;
            case "scale-speed":
                update_scale_speed();
                break;
            case "auto-hide":
                update_auto_hide();
                break;
            case "css-sheet":
                update_css_sheet();
                break;
            case "icon-size-range":
                update_icon_size_range_from_settings();
                break;
            case "apps":
                update_dock_apps();
                break;
            case "folders":
                update_dock_folders();
                break;
        }
    }

    protected void update_icon_size_range_from_settings() {
        Variant variant = settings.get_value("icon-size-range");
        if (variant.is_of_type(new VariantType("(ii)"))) {
            int min, max;
            variant.get("(ii)", out min, out max);
            if (min > max) {
                warning("minimum icon size (%i) can't be larger than maximum (%i)", min, max);
            }
            set_icon_sizes(min, max);
        }
    }

    protected void set_icon_sizes(int min, int max) {
        int old_min = _min_icon_size;
        int old_max = _max_icon_size;
        bool min_emit_change = min != min_icon_size;
        bool max_emit_change = max != max_icon_size;

        min = min.clamp(MIN_SIZE, MAX_SIZE);
        max = max.clamp(MIN_SIZE, MAX_SIZE);
        int adjusted_min = int.min(min, MAX_SIZE);
        bool max_follow_min = max <= _min_icon_size;
        int adjusted_max = 0;
        if (max_follow_min) {
            // adjusted_max = adjusted_min;
        } else {
        }
            adjusted_max = int.max(adjusted_min, max);

        _min_icon_size = adjusted_min;
        _max_icon_size = adjusted_max;

        if (min_emit_change || max_emit_change) {
            sizes_changed(old_min, old_max);
            settings.set_value("icon-size-range", new Variant("(ii)", adjusted_min, adjusted_max));
        }
    }

    private int _max_icon_size;
    public int max_icon_size {
        get {
            return _max_icon_size;
        }
        set {
            if (_max_icon_size != value) {
                set_icon_sizes(min_icon_size, value);
            }
        }
    }
    private int _min_icon_size;

    public int min_icon_size {
        get {
            return _min_icon_size;
        }
        set {
            if (_min_icon_size != value) {
                set_icon_sizes(value, max_icon_size);
            }
        }
    }

    public enum SizeTuple {
        MIN = 0,
        MAX = 1
    }

    private double _spread_factor;
    public double spread_factor { get { return _spread_factor; } }

    private double _scale_speed;
    public double scale_speed { get { return _scale_speed; } }

    protected void update_spread_factor() {
        _spread_factor = (double)settings.get_double("spread-factor");
    }

    public signal void hover_label_max_length_changed(int max_width);
    private int _hover_label_max_length;
    public int hover_label_max_length {
        get {
            return _hover_label_max_length;
        }
        set {
            if (value != _hover_label_max_length) {
                _hover_label_max_length = value;
                hover_label_max_length_changed(_hover_label_max_length);
            }

        }
    }
    protected void update_hover_label_max_length() {
        hover_label_max_length = settings.get_int("hover-label-max-length");
    }

    protected void update_scale_speed() {
        // convert to seconds
        _scale_speed = ((double)settings.get_int("scale-speed")) / 1000.0;
    }

    public signal void sizes_changed(int old_min, int old_max);

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
    private Gtk.CssProvider? css_edges;


    private void update_css() {
        if (file_monitor != null) {
            file_monitor.changed.disconnect(on_css_file_changed);
            file_monitor.cancel();
            file_monitor = null;
        }

        if (css_edges != null) {
            WayLauncherStyleProvider.remove_style_context(Gdk.Display.get_default(), css_edges);
            css_edges = null;
        }

        css_edges = new Gtk.CssProvider();

        if (FileUtils.test(this._css_path, FileTest.EXISTS)) {
            try {
                css_edges.load_from_path(this._css_path);

                var file = File.new_for_path(this._css_path);
                file_monitor = file.monitor_file(FileMonitorFlags.NONE);
                file_monitor.changed.connect(on_css_file_changed);
            } catch (Error e) {
                warning("Error loading CSS from path: %s", e.message);
                load_default_css(css_edges);
            }
        } else {
            load_default_css(css_edges);
        }

        WayLauncherStyleProvider.add_style_context(
            Gdk.Display.get_default(),
            css_edges,
            Gtk.STYLE_PROVIDER_PRIORITY_USER
        );
    }

    private void load_default_css(Gtk.CssProvider css_edges) {
        css_edges.load_from_resource("io/github/trbjo/bobdock/Application.css");
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
        update_icon_size_range_from_settings();
        update_spread_factor();
        update_hover_label_max_length();
        update_scale_speed();
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

    private bool arrays_equal(string[] arr1, string[] arr2) {
        if (arr1 == null || arr2 == null)
            return arr1 == arr2;
        if (arr1.length != arr2.length)
            return false;
        for (int i = 0; i < arr1.length; i++) {
            if (arr1[i] != arr2[i])
                return false;
        }
        return true;
    }

    private string[] _dock_apps;
    public string[] dock_apps {
        get { return _dock_apps; }
        set {
            var unique_apps = remove_duplicates(value);
            if (unique_apps.length == 0) {
                unique_apps = get_default_apps();
            }
            if (!arrays_equal(_dock_apps, unique_apps)) {
                _dock_apps = unique_apps;
                dock_apps_changed();
                settings.set_strv("apps", unique_apps);
            }
        }
    }

    protected void update_dock_apps() {
        dock_apps = settings.get_strv("apps");
    }

    public signal void dock_apps_changed();

    private string[] remove_duplicates(string[] array) {
        var hash = new GLib.HashTable<string, bool>(str_hash, str_equal);
        string[] unique = {};

        foreach (var item in array) {
            if (!hash.contains(item)) {
                hash.insert(item, true);
                unique += item;
            }
        }
        return unique;
    }

    private string[] _dock_folders;
    public string[] dock_folders {
        get { return _dock_folders; }
        set {
            var unique_folders = remove_duplicates(value);
            if (unique_folders.length == 0) {
                unique_folders = get_default_folders();
            }

            if (!arrays_equal(_dock_folders, unique_folders)) {
                _dock_folders = unique_folders;
                dock_folders_changed();
                settings.set_strv("folders", unique_folders);
            }
        }
    }

    public signal void dock_folders_changed();

    protected void update_dock_folders() {
        dock_folders = settings.get_strv("folders");
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
            string file_info = Utils.find_desktop_file(app_id, "") ?? "";
            var dai = new DesktopAppInfo.from_filename(file_info);
            if (dai != null) {
                items.append(new AppItem(dai, true));
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
