public class Dock : Gtk.Widget {
    private const double MIN_SCALE = 1.0;

    private static AppSettings settings;

    static construct {
        settings = AppSettings.get_default();
    }

    public Background background;
    public Splitter splitter;
    public TrashItem trash;

    public delegate void ItemFunc(Item item);
    public delegate void AppFunc(AppItem item);
    public delegate void FolderFunc(FolderItem item);
    public delegate void ItemIterator(ItemFunc item_func);

    private uint animation_callback_id = 0;

    private int _current_icon_size;
    public int current_max_size {
        get { return _current_icon_size.clamp(settings.min_icon_size, settings.max_icon_size); }
        private set {
            _current_icon_size = value.clamp(settings.min_icon_size, settings.max_icon_size);
        }
    }

    construct {
        current_max_size = settings.min_icon_size;
        name = "dock";

        background = new Background();
        background.set_parent(this);

        splitter = new Splitter(this);
        splitter.folder_dropped.connect(add_folder_item);

        trash = TrashItem.create();
        if (trash != null) {
            trash.set_parent(this);
            trash.dock_item_removed.connect(remove);
        }
    }

    private Gtk.Widget first_visible_item() {
        unowned Gtk.Widget child = background.get_next_sibling();
        while (child != null) {
            if (child.visible) {
                return child;
            }
            child = child.get_next_sibling();
        }
        error("Dock does not have any visible childen, cannot continue");
    }

    public void sizes_changed(int old_min, int old_max) {
        if (old_min == current_max_size) {
            current_max_size = settings.min_icon_size;
        } else if (old_max == current_max_size) {
            current_max_size = settings.max_icon_size;
        }
        foreach_item((item) => {
            item.queue_resize();
        });
        queue_resize();
    }

    public int foreach_app(AppFunc func) {
        int app_count = 0;
        unowned Gtk.Widget child = background.get_next_sibling();
        while (child.get_type() == AppItem.TYPE) {
            unowned Gtk.Widget next = child.get_next_sibling();
            func((AppItem)child);
            child = next;
        }
        return app_count;
    }

    public int foreach_folder(FolderFunc func) {
        int folder_count = 0;
        unowned Gtk.Widget child = splitter.get_next_sibling();
        while (child.get_type() == FolderItem.TYPE) {
            unowned Gtk.Widget next = child.get_next_sibling();
            func((FolderItem)child);
            child = next;
        }
        return folder_count;
    }

    public void foreach_item(ItemFunc func) {
        unowned Gtk.Widget child = background;
        while (child != trash) {
            child = child.get_next_sibling();
            if (child.visible) {
                func((Item)child);
            }
        }
    }

    public void foreach_item_rev(ItemFunc func) {
        unowned Gtk.Widget child = trash;
        while (child != background) {
            if (child.visible) {
                func((Item)child);
            }
            child = child.get_prev_sibling();
        }
    }


    private void remove(Item item) {
        var child_type = item.get_type();
        if (child_type == FolderItem.TYPE) {
            item.unparent();
        // let's see if we should remove the app_item
        } else if (child_type == AppItem.TYPE) {
            unowned AppItem app = (AppItem)item;
            if (app.pinned) {
                app.pinned = false;
                if (app.window_info == null) {
                    item.unparent();
                }
            }
        }
        rebuild_dock_items();
    }


    public void rebuild_dock_items() {
        var applist = new GLib.List<string>();
        var folder_list = new GLib.List<string>();
        foreach_item((item) => {
            if (item.get_type() == AppItem.TYPE) {
                applist.append(((AppItem)item).user_id);
            } else if (item.get_type() == FolderItem.TYPE) {
                folder_list.append(((FolderItem)item).user_id);
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
        folders.foreach((folder) => {
            add_folder_item(folder);
        });

    }

    public void app_items_changed(GLib.List<AppItem> new_apps) {
        var winfos = new HashTable<uint?, AppItem>(int_hash, int_equal);
        new_apps.foreach((app) => {
            winfos.set(app.hash, app);
        });

        // we need to ensure all unpinned apps are at the beginning of the dock.
        Gtk.Widget last_pinned = background;

        foreach_app((app) => {
            if(app.pinned) {
                var new_app = winfos.get(app.hash);
                if (new_app == null) {
                    app.unparent();
                } else {
                    app.insert_after(this, last_pinned);
                    winfos.remove(app.hash);
                }
            } else {
                app.insert_after(this, background);
            }
            last_pinned = app;
        });

        new_apps.foreach((app) => {
            if (winfos.get(app.hash) != null) {
                app.insert_after(this, last_pinned);
                last_pinned = app;
            }
        });

    }

    private int add_folder_item(FolderItem new_folder) {
        bool is_unique = true;
        foreach_folder((folder) => {
            if (folder.hash == new_folder.hash) {
                is_unique = false;
            }
        });
        if (is_unique) {
            new_folder.insert_before(this, trash);
            return 1;
        }
        return 0;
    }

    public void update_window_items(GLib.HashTable<uint?, unowned WindowInfo> window_map) {
        foreach_app((container) => {
            var is_open_info = window_map.get(container.hash);
            container.update_window_info(is_open_info);
            window_map.remove(container.hash);
        });

        window_map.foreach((key, win) => {
            string path = Utils.find_desktop_file(win.app_id, win.title) ?? "";
            var dai = new DesktopAppInfo.from_filename(path);
            if (dai != null) {
                var app = new AppItem(dai, false);
                app.update_window_info(win);
                app.insert_after(this, background);
            }
        });

        foreach_app((container) => {
            if (!container.open && !container.pinned) {
                container.unparent();
            }

        });
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
    private double _scale_accumulator = 0.0;

    private bool animate_tick(Gtk.Widget widget, Gdk.FrameClock frame_clock) {
        var surf = get_root().get_surface();
        if (surf == null) {
            animation_callback_id = 0;
            return false;
        }
        var monitor = Gdk.Display.get_default().get_monitor_at_surface(surf);
        double refresh_rate = ((double)monitor.refresh_rate) / 1000.0;
        int icon_size_delta = settings.max_icon_size - settings.min_icon_size;

        double size_change = (icon_size_delta / (settings.scale_speed * refresh_rate)) * (scaling_up ? 1 : -1);
        _scale_accumulator += size_change;

        int pixel_change = (int)Math.round(_scale_accumulator);
        if (pixel_change != 0) {
            current_max_size += pixel_change;
            _scale_accumulator -= pixel_change;

            current_max_size = current_max_size.clamp(settings.min_icon_size, settings.max_icon_size);

            if (current_max_size >= settings.max_icon_size || current_max_size <= settings.min_icon_size) {
                animation_callback_id = 0;
                _scale_accumulator = 0.0; // Reset accumulator when animation ends
            }
            queue_resize();
        }

        return animation_callback_id != 0;
    }

    private double last_cursor;

    public void request_motion(double outside_pos) {
        last_cursor = outside_pos;
        if (current_max_size != settings.max_icon_size) {
            scale_up();
        } else {
            queue_resize();
        }
    }

    protected override void measure(Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
        natural = minimum = minimum_baseline = natural_baseline = -1;
        Gtk.Orientation orthogonal = settings.edge != GtkLayerShell.Edge.BOTTOM ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL;
        if (orientation == orthogonal) {
            int base_dock_padding, splitter_size;
            background.measure(orthogonal, -1, out base_dock_padding, null, null, null);
            first_visible_item().measure(orientation, -1, out splitter_size, null, null, null);
            minimum = natural = current_max_size + splitter_size + base_dock_padding;
        }
    }

    public override void size_allocate(int base_width, int base_height, int baseline) {
        bool is_bottom = settings.edge == GtkLayerShell.Edge.BOTTOM;
        int base_dimension = is_bottom ? base_width: base_height;

        Gtk.Orientation parallel = is_bottom ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL;
        Gtk.Orientation orthogonal = !is_bottom ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL;

        int icon_min_sizes = 0;
        // first pass, find dock minimum size;
        int[] parallel_array = {};
        int[] position_array = {};
        foreach_item((item) => {
            int min;
            item.measure(parallel, -1, out min, null, null, null);
            parallel_array += min;
            position_array += icon_min_sizes;
            icon_min_sizes += min + settings.min_icon_size;
        });

        int baseline_pixels = (int)calculate_baseline_pixel_cursor(last_cursor, icon_min_sizes, base_dimension);
        int cursor_max_size = icon_min_sizes/2;

        double current_scale = ((double)current_max_size) / ((double)settings.min_icon_size);
        double current_scale_factor = current_scale - 1.0;

        int[] ortho_size_array = new int[parallel_array.length];

        double max_sizes = 0;
        int acc_sizes = 0;

        double pixel_accumulator = 0;

        int direction, i;
        ItemIterator item_iterator;
        bool cursor_in_second_half = last_cursor > base_dimension/2;
        if (cursor_in_second_half) {
            i = 0;
            direction = 1;
            item_iterator = foreach_item;
        } else {
            direction = -1;
            item_iterator = foreach_item_rev;
            i = parallel_array.length - 1;
        }


        double spread_pixels = settings.spread_factor * settings.min_icon_size;
        spread_pixels = 2 * spread_pixels * spread_pixels;

        // second pass, find actual distance from the cursor.
        item_iterator((item) => {
            int pos_start = position_array[i];
            int min = parallel_array[i];
            int mid = pos_start + (min+settings.min_icon_size)/2;

            double distance = mid - baseline_pixels;
            double item_scale = 1.0 + current_scale_factor * Math.exp(-(distance * distance) / spread_pixels);

            double icon_size = settings.min_icon_size * item_scale;
            int icon_size_int = (int)Math.round(icon_size);

            double icon_size_diff = icon_size - icon_size_int;

            pixel_accumulator += icon_size_diff;
            int pixel_change = (int)Math.round(pixel_accumulator);

            if (pixel_change != 0 && icon_size_int > settings.min_icon_size) {
                icon_size_int += pixel_change;
                pixel_accumulator -= pixel_change;
            }

            item.icon_size = icon_size_int;
            parallel_array[i] = icon_size_int + min;
            acc_sizes += icon_size_int + min;

            int ortho_min;
            item.measure(orthogonal, -1, out ortho_min, null, null, null);
            ortho_size_array[i] = ortho_min + icon_size_int;

            double max_distance = mid - cursor_max_size;
            double max_item_scale = 1.0 + current_scale_factor * Math.exp(-(max_distance * max_distance) / spread_pixels);
            double max_icon_size = settings.min_icon_size * max_item_scale;
            max_sizes += max_icon_size + min;

            i += direction;
        });

        int dock_width, dock_height, icon_padding;
        background.measure(Gtk.Orientation.HORIZONTAL, -1, out dock_width, null, null, null);
        background.measure(Gtk.Orientation.VERTICAL, -1, out dock_height, null, null, null);
        first_visible_item().measure(orthogonal, -1, out icon_padding, null, null, null);

        dock_height += (is_bottom ? icon_padding + settings.min_icon_size : acc_sizes);
        dock_width += (is_bottom ? acc_sizes : icon_padding + settings.min_icon_size);

        double translate_down = direction * (max_sizes - acc_sizes - pixel_accumulator);

        float fixed_transform = (float)(base_dimension - (is_bottom ? dock_width : dock_height) - translate_down)/2.0f;

        float x_offset = is_bottom ? fixed_transform : 0;
        float y_offset = !is_bottom ? fixed_transform : 0;
        int input_width = is_bottom ? dock_width : base_dimension;
        int input_height = !is_bottom ? dock_height : base_dimension;
        input_region(x_offset, y_offset, input_width, input_height);

        var transform = new Gsk.Transform().translate(Graphene.Point() { x = x_offset, y = y_offset });;
        if (is_bottom) {
            transform = transform.translate(Graphene.Point() { x = 0, y = base_height - dock_height });
        } else if (settings.edge == GtkLayerShell.Edge.RIGHT) {
            transform = transform.translate(Graphene.Point() { x = base_width - dock_width, y = 0 });
        }
        background.allocate(dock_width, dock_height, baseline, transform);

        Graphene.Rect bg_margins;
        background.compute_bounds(background, out bg_margins);
        x_offset -= (int)bg_margins.origin.x;
        y_offset -= (int)bg_margins.origin.y;

        int j = 0;
        int[] horiz_array = is_bottom ? parallel_array : ortho_size_array;
        int[] verti_array = !is_bottom ? parallel_array : ortho_size_array;

        foreach_item((item) => {
            int horiz = horiz_array[j];
            int verti = verti_array[j++];
            if (is_bottom) {
                item.allocate(horiz, verti, baseline, new Gsk.Transform().translate({ x_offset, base_height - verti }));
            } else if (settings.edge == GtkLayerShell.Edge.RIGHT) {
                item.allocate(horiz, verti, baseline, new Gsk.Transform().translate({ base_width - horiz, y_offset }));
            } else { // LEFT
                item.allocate(horiz, verti, baseline, new Gsk.Transform().translate({ 0, y_offset }));
            }
            x_offset += horiz;
            y_offset += verti;
        });
    }

    public override void snapshot(Gtk.Snapshot snapshot) {
        List<unowned Item> visible_items = new List<unowned Item>();
        snapshot_child(background, snapshot);
        foreach_item((item) => visible_items.append(item));
        visible_items.sort((a, b) => (a.icon_size - b.icon_size));
        foreach(var child in visible_items) {
            snapshot_child(child, snapshot);
        }
    }

    private void input_region(float start_x, float start_y, int end_x, int end_y) {

        var rect = new Cairo.Region.rectangle(Cairo.RectangleInt() {
            x = (int)Math.floor(start_x),
            y = (int)Math.floor(start_y),
            width = end_x,
            height = end_y,
        });
        get_root().get_surface().set_input_region(rect);

    }

    public int bg_inner_size() {
        // without margins and border
        return settings.edge == GtkLayerShell.Edge.BOTTOM ? background.get_height() : background.get_width();
    }

    public int bg_outer_size() {
        // with margins and border
        Graphene.Rect bg_margins;
        background.compute_bounds(background, out bg_margins);
        return settings.edge == GtkLayerShell.Edge.BOTTOM ? (int)bg_margins.size.height : (int)bg_margins.size.width;
    }

    public double calculate_baseline_pixel_cursor(double raw_cursor, double min_size, double max_size) {
        double scaling_difference = max_size - min_size;
        double unscaled_cursor_position = raw_cursor - (scaling_difference / 2.0);
        return unscaled_cursor_position;
    }
}

