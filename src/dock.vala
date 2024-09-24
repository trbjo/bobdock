public class Dock : Gtk.Widget {
    private const double MIN_SCALE = 1.0;

    private static AppSettings settings = AppSettings.get_default();

    public Background background { get; construct; }
    private Splitter splitter;
    private TrashItem trash;

    public delegate void ItemFunc(DockItem item, int index);
    public delegate void AppFunc(AppItem item, int index);
    public delegate void FolderFunc(FolderItem item, int index);
    public delegate void WindowFunc(WindowItem item, int index);

    public signal void scaled_up();

    private uint animation_callback_id = 0;

    public double current_scale = 1.0;

    construct {
        name = "dock";

        background = new Background();
        background.set_parent(this);

        splitter = new Splitter();
        trash = new TrashItem();
        splitter.set_parent(this);
        trash.set_parent(this);

        trash.dock_item_removed.connect(remove);
        splitter.folder_dropped.connect(add_folder_item);
    }

    public int foreach_visible(ItemFunc func) {
        int visible_count = 0;
        unowned Gtk.Widget child = background.get_next_sibling();
        while (child != null) {
            unowned Gtk.Widget next = child.get_next_sibling();
            if (child.visible) {
                func(((DockItem)child), visible_count++);
            }
            child = next;
        }
        return visible_count;
    }

    public int foreach_app_item(AppFunc func) {
        int app_count = 0;
        unowned Gtk.Widget child = background.get_next_sibling();
        while (child != splitter) {
            unowned Gtk.Widget next = child.get_next_sibling();
            if (child.get_type() == app_type) {
                func(((AppItem)child), app_count++);
            }
            child = next;
        }
        return app_count;
    }

    public int foreach_window_item(WindowFunc func) {
        int win_count = 0;
        unowned Gtk.Widget child = background.get_next_sibling();
        while (child != splitter) {
            unowned Gtk.Widget next = child.get_next_sibling();
            if (child.get_type() == window_type) {
                func(((WindowItem)child), win_count++);
            }
            child = next;
        }
        return win_count;
    }

    public int foreach_folder_item(FolderFunc func) {
        int folder_count = 0;
        unowned Gtk.Widget child = splitter.get_next_sibling();
        while (child != trash) {
            unowned Gtk.Widget next = child.get_next_sibling();
            func(((FolderItem)child), folder_count++);
            child = next;
        }
        return folder_count;
    }

    public int foreach_item(ItemFunc func) {
        int total_count = 0;
        unowned Gtk.Widget child = background.get_next_sibling();
        while (child != null) {
            unowned Gtk.Widget next = child.get_next_sibling();
            func(((DockItem)child), total_count++);
            child = next;
        }
        return total_count;
    }

    public int item_count {
        get {
            lock(_item_count) {
                return _item_count;
            }
        }
    }

    private int _item_count = 0;
    private void rebuild_item_count() {
        int total = 0;
        lock(_item_count) {
            unowned Gtk.Widget child = background.get_next_sibling();
            while (child != null) {
                if (child.visible) {
                    total++;
                }
                child = child.get_next_sibling();
            }
            _item_count = total;
        }
    }

    private Type app_type = typeof(AppItem);
    private Type folder_type = typeof(FolderItem);
    private Type window_type = typeof(WindowItem);

    private void remove(DockItem child) {
        // let's see if we should remove the app_item
        if (child.get_type() == window_type) {
            foreach_app_item((item, i) => {
                if (item.hash == child.hash) {
                    item.unparent();
                    return;
                }
            });
        } else {
            child.unparent();
        }
        rebuild_dock_items();
        rebuild_item_count();
    }


    public void rebuild_dock_items() {
        var applist = new GLib.List<string>();
        var folder_list = new GLib.List<string>();
        foreach_item((item, i) => {
            if (item.get_type() == app_type) {
                applist.append(item.user_identification);
            } else if (item.get_type() == folder_type) {
                folder_list.append(item.user_identification);
            }
        });
        if (applist.length() > 0) {
            uint counter = 0;
            string[] app_array = new string[applist.length()];
            applist.foreach((name) => {
                app_array[counter++] = name;
            });
            settings.dock_apps = app_array;

        }
        if (folder_list.length() > 0) {
            uint counter = 0;
            string[] folder_array = new string[folder_list.length()];
            folder_list.foreach((name) => {
                folder_array[counter++] = name;
            });
            settings.dock_folders = folder_array;
        }
    }

    public void add_folder_items(GLib.List<FolderItem> folders) {
        int changes = 0;
        folders.foreach((folder) => {
            changes += add_folder_item(folder);
        });

        if (changes != 0) {
            rebuild_item_count();
        }
    }

    public void app_items_changed(GLib.List<AppItem> new_apps) {
        int changes = foreach_app_item((app, i) => {
            app.unparent();
        });

        var app_map = new HashTable<uint?, unowned AppItem>(int_hash, int_equal);

        new_apps.foreach((app) => {
            app.insert_before(this, splitter);
            app_map.set(app.hash, app);
        });

        // then reorder window items.
        foreach_window_item((win, i) => {
            var app = app_map.get(win.hash);
            if (app == null) {
                win.insert_after(this, background);
            } else {
                win.insert_after(this, app);
                app.visible = false;
            }
            // todo: are the pointers in the linked list changed during looping?
        });


        if (changes != new_apps.length()) {
            rebuild_item_count();
        }
    }

    public void on_max_scale_changed(double scale) {
        if (current_scale != scale) {
            current_scale = scale;
            queue_resize();
        }
    }


    private int add_folder_item(FolderItem child) {
        bool is_unique = true;
        foreach_folder_item((folder, index) => {
            if (folder.hash == child.hash) {
                is_unique = false;
            }
        });
        if (is_unique) {
            child.insert_before(this, trash);
            return 1;
        }
        return 0;
    }

    public void set_window_items(GLib.HashTable<uint?, unowned WindowItem> window_map) {
        var app_map = new HashTable<uint?, unowned AppItem>(int_hash, int_equal);

        foreach_app_item((app, i) => {
            app_map.set(app.hash, app);
            if (app.hash in window_map) {
                var win = window_map.get(app.hash);
                if (win.get_parent() == null) {
                    win.insert_after(this, app);
                    app.visible = false;
                }
            }
        });


        foreach_window_item((item, i) => {
            if (!(item.hash in window_map)) {
                var app = app_map.get(item.hash);
                app.visible = true;
                item.unparent();
                rebuild_item_count();
            }
        });

        // add the remaining
        window_map.foreach((key, win) => {
            if (win.get_parent() == null) {
                win.insert_after(this, background);
                // win.animate_icon(true, null);
            }
        });

        rebuild_item_count();
    }

    public void scale_up() {
        scaling_up = true;
        start_animation();
    }


    public void scale_down() {
        scaling_up = false;
        start_animation();
    }

    private void start_animation() {
        if (animation_callback_id == 0) {
            animation_callback_id = add_tick_callback(animate_tick);
        }
    }

    private bool scaling_up = true;

    private bool animate_tick(Gtk.Widget widget, Gdk.FrameClock frame_clock) {
        var monitor = Gdk.Display.get_default().get_monitor_at_surface(get_root().get_surface());
        double scale_delta = settings.max_scale - MIN_SCALE;

        current_scale += scale_delta / (settings.scale_speed * monitor.refresh_rate / 1000.0) * (scaling_up ? 1 : -1);
        current_scale = current_scale.clamp(MIN_SCALE, settings.max_scale);

        if (current_scale >= settings.max_scale || current_scale <= MIN_SCALE) {
            animation_callback_id = 0;
        }

        queue_resize();
        return animation_callback_id != 0;
    }

    private double last_cursor;

    public void request_motion(double outside_pos) {
        last_cursor = outside_pos;
        if (current_scale != settings.max_scale) {
            scale_up();
        } else {
            queue_resize();
        }
    }


    private void set_icon_targets(double baseline_percentage, double for_scale, int ideal_size_for_scale, int base_size) {
        int accumulated_sizes = 0;
        List<unowned DockItem> item_list = new List<unowned DockItem>();

        double spread_inverse = 100.0 / settings.spread_factor;
        double scale_factor = for_scale - 1.0;

        foreach_visible((item, i) => {
            double icon_center_percentage = ((double)(i + 0.5)) / ((double)item_count);
            double distance = icon_center_percentage - baseline_percentage;
            double item_scale = 1.0 + scale_factor * Math.exp(-distance * distance * spread_inverse);

            int icon_size = (int)Math.floor(base_size * item_scale);
            item.icon_size = icon_size;
            accumulated_sizes += icon_size;
            item_list.append(item);
        });

        int sizediff = accumulated_sizes - ideal_size_for_scale;
        int adjustment = sizediff > 0 ? -1 : 1;
        bool can_distribute = sizediff != 0;

        item_list.sort((a, b) => (a.icon_size - b.icon_size));
        while (can_distribute) {
            can_distribute = false;

            foreach (var item in item_list) {
                if (sizediff == 0) {
                    return;
                }

                if (base_size < item.icon_size) {
                    item.icon_size += adjustment;
                    sizediff += adjustment;
                    can_distribute = true;
                }
            }
        }
    }

    public delegate Gsk.Transform TransformFunc(int x_size, int y_size);

    protected override void measure(Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
        natural = minimum = minimum_baseline = natural_baseline = -1;
        Gtk.Orientation orthogonal = settings.edge != GtkLayerShell.Edge.BOTTOM ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL;
        if (orientation == orthogonal) {
            int icon_size, bg_size, item_spacing;
            background.image_size.measure(orientation, -1, out icon_size, null, null, null);
            background.measure(orientation, -1, out bg_size, null, null, null);
            background.padding.measure(orientation, -1, out item_spacing, null, null, null);
            int scaled_icon = (int)Math.round(((double)icon_size)*current_scale) + bg_size + item_spacing;
            minimum = natural = scaled_icon;
        }
    }

    public override void size_allocate(int base_width, int base_height, int baseline) {
        bool is_bottom = settings.edge == GtkLayerShell.Edge.BOTTOM;
        int base_dimension = Utils.round_to_nearest_even((is_bottom ? base_width: base_height) -1);

        Gtk.Orientation parallel = is_bottom ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL;
        int primary_min_size = 0;
        foreach_visible((item, i) => {
            int min;
            item.measure(parallel, -1, out min, null, null, null);
            primary_min_size+=min;
        });

        double baseline_percentage = calculate_baseline_cursor(last_cursor, primary_min_size, base_dimension);

        int dock_padding;
        background.measure(parallel, -1, out dock_padding, null, null, null);

        int base_size;
        background.image_size.measure(Gtk.Orientation.HORIZONTAL, -1, out base_size, null, null, null);
        int padding = (int)Math.round(primary_min_size + dock_padding - item_count*base_size);

        double nearest_center = get_edge_favoring_icon_percentage(baseline_percentage);

        double max_scale = get_expansion_factor(0.5, current_scale);
        double ideal_scale = get_expansion_factor(baseline_percentage, current_scale);
        double extreme_scale = get_expansion_factor(nearest_center, current_scale);

        ideal_scale = double.max(ideal_scale, extreme_scale);
        double max_size_for_scale = ((double)base_size) * max_scale;
        double ideal_size_for_scale = ((double)base_size) * ideal_scale;

        double scale_difference = max_scale - ideal_scale;
        int deficit = (int)Math.round(((double)base_size) * scale_difference);

        int background_total_size = (int)Math.round(ideal_size_for_scale);
        if (baseline_percentage > 0.5) {
            deficit = 0;
        } else {
            background_total_size = (int)Math.round(max_size_for_scale - deficit);
        }

        set_icon_targets(baseline_percentage, current_scale, background_total_size, base_size);
        background_total_size += padding;

        int fixed_transform = (int)Math.round((base_dimension - max_size_for_scale - padding)/2.0);
        int x_offset = is_bottom ? (fixed_transform + deficit) : 0;
        int y_offset = !is_bottom ? (fixed_transform + deficit) : 0;

        var rect = new Cairo.Region.rectangle(Cairo.RectangleInt() {
            x = x_offset,
            y = y_offset,
            width = is_bottom ? background_total_size : base_dimension,
            height = !is_bottom ? background_total_size : base_dimension,
        });
        get_root().get_surface().set_input_region(rect);

        TransformFunc trans;
        Gtk.Orientation orthogonal = !is_bottom ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL;
        int base_dock_padding, item_padding;
        background.measure(orthogonal, -1, out base_dock_padding, null, null, null);
        background.padding.measure(orthogonal, -1, out item_padding, null, null, null);
        int secondary_size = base_dock_padding + item_padding + base_size;

        if (is_bottom) {
            var transform = new Gsk.Transform().translate(Graphene.Point() { x = x_offset, y = base_height - secondary_size });
            background.allocate(background_total_size, secondary_size, baseline, transform);

            Graphene.Rect bg_margins;
            background.compute_bounds(background, out bg_margins);
            x_offset-=(int)bg_margins.origin.x;
            trans = (x_size, y_size) => {
                int x = x_offset;
                x_offset += x_size;
                return new Gsk.Transform().translate(Graphene.Point() {
                    x = x,
                    y = base_height - y_size
                });
            };
        } else if (settings.edge == GtkLayerShell.Edge.RIGHT) {
            var transform = new Gsk.Transform() .translate(Graphene.Point() { x = base_width - secondary_size, y = y_offset });
            background.allocate(secondary_size, background_total_size, baseline, transform);

            Graphene.Rect bg_margins;
            background.compute_bounds(background, out bg_margins);
            y_offset-=(int)bg_margins.origin.y;


            trans = (x_size, y_size) => {
                int y = y_offset;
                y_offset += y_size;
                return new Gsk.Transform().translate(Graphene.Point() {
                    x = base_width - x_size,
                    y = y
                });
            };
        } else { // LEFT
            var transform = new Gsk.Transform().translate(Graphene.Point() { x = 0, y = y_offset });
            background.allocate(secondary_size, background_total_size, baseline, transform);

            Graphene.Rect bg_margins;
            background.compute_bounds(background, out bg_margins);
            y_offset-=(int)bg_margins.origin.y;

            trans = (x_size, y_size) => {
                int y = y_offset;
                y_offset += y_size;
                return new Gsk.Transform().translate(Graphene.Point() {x = 0, y = y });
            };
        }

        foreach_visible((item, i) => {
            int nat_h, nat_v;
            item.measure(Gtk.Orientation.HORIZONTAL, -1, null, out nat_h, null, null);
            item.measure(Gtk.Orientation.VERTICAL, -1, null, out nat_v, null, null);
            item.allocate(nat_h, nat_v, baseline, trans(nat_h, nat_v));
        });

    }

    public override void snapshot(Gtk.Snapshot snapshot) {
        List<unowned DockItem> visible_items = new List<unowned DockItem>();
        snapshot_child(background, snapshot);
        foreach_visible((item, index) => visible_items.append(item));
        visible_items.sort((a, b) => (a.icon_size - b.icon_size));
        foreach(var child in visible_items) {
            snapshot_child(child, snapshot);
        }
    }

    public double get_expansion_factor(double cursor_percentage, double max_scale) {
        double spread_inverse = 100.0 / settings.spread_factor;
        double scale_factor = max_scale - 1.0;
        double total_factor = 0;

        for (int i = 0; i < item_count; i++) {
            double distance = ((double)i + 0.5) / item_count - cursor_percentage;
            total_factor += 1.0 + scale_factor * Math.exp(-distance * distance * spread_inverse);
        }

        return total_factor;
    }

    public double get_edge_favoring_icon_percentage(double cursor_percentage) {
        int item_count = this.item_count;

        if (cursor_percentage <= 0.5 / item_count) {
            return 0.0; // First icon
        }
        if (cursor_percentage >= (item_count - 0.5) / item_count) {
            return 1.0; // Last icon
        }

        double adjusted_cursor = cursor_percentage * item_count - 0.5;

        int nearest_icon;
        if (cursor_percentage < 0.5) {
            nearest_icon = (int)Math.floor(adjusted_cursor);
        } else {
            nearest_icon = (int)Math.ceil(adjusted_cursor);
        }

        return (nearest_icon + 0.5) / item_count;
    }

    public int bg_inner_size() {
        return settings.edge == GtkLayerShell.Edge.BOTTOM ? background.get_height() : background.get_width();
    }

    public int bg_outer_size() {
        Graphene.Rect bg_margins;
        background.compute_bounds(background, out bg_margins);
        return settings.edge == GtkLayerShell.Edge.BOTTOM ? (int)bg_margins.size.height : (int)bg_margins.size.width;
    }

    public double calculate_baseline_cursor(double raw_cursor, double min_size, double max_size) {
        double scaling_difference = max_size - min_size;

        double unscaled_cursor_position = raw_cursor - (scaling_difference / 2.0);

        double adjusted_cursor_position = 0;
        if (unscaled_cursor_position <= 0.0) {
            adjusted_cursor_position = 0;
        } else if (unscaled_cursor_position >= min_size) {
            adjusted_cursor_position = 1;
        } else {
            adjusted_cursor_position = (unscaled_cursor_position) / min_size;
        }

        return adjusted_cursor_position;
    }
}
