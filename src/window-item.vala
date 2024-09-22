public class WindowItem : AppItem, MouseAble {
    public signal void app_activated(string app_id);
    private string _app_id;
    private Gtk.Box dot_box;
    private GLib.HashTable<int, bool> container_ids;

    private const int MAX_DOTS = 3;

    public WindowItem(DesktopAppInfo desktop_info, string app_id) {
        base(desktop_info);
        this._app_id = app_id;
        add_css_class("window-item");
        this.container_ids = new GLib.HashTable<int, bool>(GLib.direct_hash, GLib.direct_equal);

        var orient = Utils.edge_to_orientation(AppSettings.get_default().edge);
        this.dot_box = new Gtk.Box(orient, 0) {
            halign = Gtk.Align.CENTER,
            valign = Gtk.Align.CENTER,
        };
        AppSettings.get_default().layershell_edge_change.connect((new_edge) => {
            dot_box.set_orientation(Utils.edge_to_orientation(new_edge));
        });
        dot_box.set_parent(this);
    }

    public override void dispose() {
        if (dot_box != null) {
            dot_box.unparent();
            dot_box = null;
        }
        base.dispose();
    }

    public override void size_allocate(int width, int height, int baseline) {
        base.size_allocate(width, height, baseline);

        int dot_box_width, dot_box_height;
        dot_box.measure(Gtk.Orientation.HORIZONTAL, -1, out dot_box_width, null, null, null);
        dot_box.measure(Gtk.Orientation.VERTICAL, -1, out dot_box_height, null, null, null);

        Graphene.Rect outer_size;
        this.compute_bounds(this, out outer_size);

        float start_x, start_y;

        switch (AppSettings.get_default().edge) {
            case GtkLayerShell.Edge.BOTTOM:
                start_x = (_icon_size - dot_box_width) / 2.0f;
                start_y = outer_size.size.height + outer_size.origin.y - dot_box_height;
                break;
            case GtkLayerShell.Edge.LEFT:
                start_x = outer_size.origin.x;
                start_y = (_icon_size - dot_box_height) / 2.0f;
                break;
            case GtkLayerShell.Edge.RIGHT:
                start_x = outer_size.size.width + outer_size.origin.x - dot_box_width;
                start_y = (_icon_size - dot_box_height) / 2.0f;
                break;
            default:
                assert_not_reached();
        }

        var dot_box_transform = new Gsk.Transform().translate({ start_x, start_y });
        dot_box.allocate(dot_box_width, dot_box_height, baseline, dot_box_transform);
    }

    public override void snapshot(Gtk.Snapshot snapshot) {
        base.snapshot(snapshot);
        snapshot_child(dot_box, snapshot);
    }

    public override bool handle_click() {
        app_activated(_app_id);
        return true;
    }

    public void update_window_title(string? new_title) {
        if (new_title != null) {
            this.label = new_title;
        }
    }

    public void add_window(int con_id) {
        if (container_ids.contains(con_id)) {
            return;
        }
        container_ids.insert(con_id, true);
        update_dot_indicators();
    }

    public void remove_window(int con_id) {
        if (container_ids.remove(con_id)) {
            update_dot_indicators();
        }
    }

    private void update_dot_indicators() {
        int dot_count = int.min((int)container_ids.size(), MAX_DOTS);

        unowned Gtk.Widget child = dot_box.get_first_child();
        while (child != null) {
            dot_count--;
            child = child.get_next_sibling();
        }

        for (; dot_count < 0; dot_count++) {
            dot_box.get_first_child().unparent();
        }

        for (; 0 < dot_count; dot_count--) {
            var new_indicator = new DotIndicator();
            dot_box.append(new_indicator);
        }

        queue_allocate();
    }

    public bool has_windows() {
        return container_ids.size() > 0;
    }
}
