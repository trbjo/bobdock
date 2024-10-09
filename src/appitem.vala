public class WindowInfo: GLib.Object, IDockWidget, IDockClick {
    private GLib.HashTable<int, DotIndicator> container_ids;
    public string app_id { get; construct; }
    public signal void title_changed(string title);

    private string _window_title;
    public string title {
        get {
            return _window_title;
        }
        set {
            if (value != null && value != _window_title) {
                _window_title = value;
                title_changed(_window_title);
            }
        }
    }

    private const int MAX_DOTS = 3;

    private Gtk.Box dot_box;

    private class DotIndicator : Gtk.Widget {
        public int container_id { get; set; }

        construct {
            halign = Gtk.Align.CENTER;
            valign = Gtk.Align.CENTER;
            css_classes = {"dot-indicator"};
        }
    }

    public uint hash { get; construct; }

    public WindowInfo(uint hash, string app_id, string title) {
        Object (
            hash: hash,
            app_id: app_id,
            title: title
        );
    }

    construct {
        this.container_ids = new GLib.HashTable<int, DotIndicator>(GLib.direct_hash, GLib.direct_equal);

        var orient = Utils.edge_to_orientation(AppSettings.get_default().edge);
        dot_box = new Gtk.Box(orient, 0) {
            name = "dot-box",
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
            can_focus = false,
            can_target = false,
        };

        AppSettings.get_default().layershell_edge_change.connect((new_edge) => {
            dot_box.set_orientation(Utils.edge_to_orientation(new_edge));
        });
    }

    public void set_parent(Gtk.Widget parent) {
        if (parent == dot_box.get_parent()) {
            return;
        }
        dot_box.unparent();
        dot_box.set_parent(parent);
    }

    public void size_allocate(int width, int height, int baseline) {
        int dot_box_width, dot_box_height;
        dot_box.measure(Gtk.Orientation.HORIZONTAL, -1, out dot_box_width, null, null, null);
        dot_box.measure(Gtk.Orientation.VERTICAL, -1, out dot_box_height, null, null, null);

        Graphene.Rect outer_size;
        dot_box.get_parent().compute_bounds(dot_box.get_parent(), out outer_size);

        float start_x, start_y;

        switch (AppSettings.get_default().edge) {
            case GtkLayerShell.Edge.BOTTOM:
                start_x = (width - dot_box_width) / 2.0f;
                start_y = outer_size.size.height + outer_size.origin.y - dot_box_height;
                break;
            case GtkLayerShell.Edge.LEFT:
                start_x = outer_size.origin.x;
                start_y = (height - dot_box_height) / 2.0f;
                break;
            case GtkLayerShell.Edge.RIGHT:
                start_x = outer_size.size.width + outer_size.origin.x - dot_box_width;
                start_y = (height - dot_box_height) / 2.0f;
                break;
            default:
                assert_not_reached();
        }

        var dot_box_transform = new Gsk.Transform().translate({ start_x, start_y });
        dot_box.allocate(dot_box_width, dot_box_height, baseline, dot_box_transform);
    }

    public void snapshot(Gtk.Snapshot snapshot) {
        dot_box.get_parent().snapshot_child(dot_box, snapshot);
    }

    public void set_state_flags(Gtk.StateFlags flags, bool clear) {
        dot_box.set_state_flags(flags, clear);
    }

    public signal void app_activated(string app_id);

    public bool handle_click(int n_press) {
        app_activated(app_id);
        return true;
    }


    public void selected_container_changed(int con_id) {
        unowned Gtk.Widget? selected_dot = container_ids.get(con_id);
        unowned Gtk.Widget child = dot_box.get_first_child();
        while (child != null) {
            if (child == selected_dot) {
                selected_dot.set_state_flags(Gtk.StateFlags.SELECTED, false);
            } else {
                child.unset_state_flags(Gtk.StateFlags.SELECTED);
            }
            child = child.get_next_sibling();
        }
    }

    public void unparent() {
        dot_box.unparent();
    }

    private void update_dot_indicators() {
        int dot_count = int.min((int)container_ids.size(), MAX_DOTS);
        dot_box.visible = dot_count > 0;


        unowned Gtk.Widget child = dot_box.get_first_child();
        // while (child != null) {
            // dot_count--;
            // child = child.get_next_sibling();
        // }

        // for (; dot_count < 0; dot_count++) {
            // dot_box.get_first_child().unparent();
        // }

        // for (; 0 < dot_count; dot_count--) {
            // var new_indicator = new DotIndicator();
            // dot_box.append(new_indicator);
        // }

        int[] keys = container_ids.get_keys_as_array();
        int i = 0;
        child = dot_box.get_first_child();
        while (child != null && i < keys.length && i < MAX_DOTS) {
            ((DotIndicator)child).container_id = keys[i++];
            child = child.get_next_sibling();
        }
        dot_box.queue_allocate();
    }

    public void add_window(int con_id) {
        if (container_ids.contains(con_id)) {
            return;
        }
        var new_indicator = new DotIndicator();
        new_indicator.container_id = con_id;
        container_ids.insert(con_id, new_indicator);
        dot_box.append(new_indicator);
        update_dot_indicators();
    }

    public void remove_window(int con_id) {
        var dot = container_ids.get(con_id);
        if (dot != null) {
            container_ids.remove(con_id);
            dot.unparent();
            update_dot_indicators();
        }
    }

    public bool has_windows() {
        return container_ids.size() > 0;
    }
}

public class AppItem : Item, IUserItem {
    public static Type TYPE = typeof(AppItem);

    public WindowInfo? window_info;
    public string user_id { get; construct; }
    public GLib.DesktopAppInfo app_info { get; construct; }
    protected string[] mime_types;

    public bool open {
        get {
            return window_info != null;
        }
    }

    private string app_label;
    public override string label {
        get {
            if (window_info != null) {
                return window_info.title;
            }
            return app_label;
        }
        construct set {
            app_label = value;
        }
    }


    public static uint app_item_hash(DesktopAppInfo app_info) {
        string app_id = Utils.strip_desktop_extension(app_info.get_id());
        return app_id.hash();
    }

    public bool pinned { get; construct set; }

    public override bool movable
    {
        get {
            return pinned;
        }
    }

    public AppItem(DesktopAppInfo app_info, bool pinned) {
        string app_id = Utils.strip_desktop_extension(app_info.get_id());
        string label = app_info.get_display_name() ?? app_info.get_name();
        var desktop_icon = app_info.get_icon();
        string icon_name = desktop_icon != null ? desktop_icon.to_string() : "application-x-executable";

        Object(
            label: label,
            app_info: app_info,
            user_id: app_id,
            icon: new Icon.from_icon_name(icon_name),
            hash: app_item_hash(app_info),
            pinned: pinned
        );

        css_classes = {"app", app_id.replace(".", "-")};

        load_mime_types();
        icon.state_flags_changed.connect(this.on_state_flags_changed);
    }

    public void update_window_info(WindowInfo? info) {
        if (this.window_info != info && this.window_info != null) {
            this.window_info.unparent();
            this.window_info = null;
        }
        this.window_info = info;

        if (this.window_info == null) {
            remove_css_class("open");
        } else {
            add_css_class("open");
            this.window_info.set_parent(this);
            this.window_info.title_changed.connect(() =>
               PopupManager.get_default().update_popover_label(this));
        }

        PopupManager.get_default().update_popover_label(this);
    }


    // keep dot indictator and item in sync.
    private void on_state_flags_changed(Gtk.StateFlags old_flags) {
        if (window_info != null) {
            window_info.set_state_flags(icon.get_state_flags(), true);
        }
    }

    public override void size_allocate(int width, int height, int baseline) {
        base.size_allocate(width, height, baseline);
        if (window_info != null) {
            window_info.size_allocate(width, height, baseline);
        }
    }

    public override void snapshot(Gtk.Snapshot snapshot) {
        if (window_info != null) {
            window_info.snapshot(snapshot);
        }
        base.snapshot(snapshot);
    }

    public override bool can_handle_mime_type(File file, string mime_type) {
        return Utils.array_contains(mime_types, mime_type);
    }

    public override bool handle_dropped_file(File file) {
        try {
            var file_list = new GLib.List<File>();
            file_list.append(file);
            return app_info != null ? app_info.launch(file_list, null) : false;
        } catch (Error e) {
            warning("Failed to launch %s with file %s: %s", user_id, file.get_path(), e.message);
        }
        return false;
    }

    public override bool handle_click(int n_press) {

        if (click_gesture.get_current_button() == Gdk.BUTTON_PRIMARY) {
            if (window_info != null) {
                return window_info.handle_click(n_press);
            }
        }

        try {
            var event_display = get_root().get_display();
            var context = event_display.get_app_launch_context();
            context.set_timestamp(click_gesture.get_current_event_time());

            if (!app_info.launch(null, context)) {
                warning("failed to launch: %s", app_info.filename);
            }
        } catch (Error e) {
            warning("Failed to launch %s: %s", user_id, e.message);
        }
        return true;
    }

    private void load_mime_types() {
        try {
            var keyfile = new KeyFile();
            keyfile.load_from_file(app_info.get_filename(), KeyFileFlags.NONE);
            if (keyfile.has_key(KeyFileDesktop.GROUP, KeyFileDesktop.KEY_MIME_TYPE)) {
                mime_types = keyfile.get_string_list(KeyFileDesktop.GROUP, KeyFileDesktop.KEY_MIME_TYPE);
            } else {
                mime_types = {};
            }
        } catch (Error e) {
            warning("Failed to load MIME types for %s: %s", user_id, e.message);
            mime_types = {};
        }
    }

}
