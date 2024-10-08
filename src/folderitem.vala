public class FolderItem : Item, IUserItem {
    public static Type TYPE = typeof(FolderItem);

    public string user_id { get; construct; }
    private const int MAX_OVERLAY_ITEMS = 3;
    private File folder;
    private FileMonitor folder_monitor;
    private HashTable<string, FileInfo> recent_files;

    private List<unowned Thumbnails.ThumbnailContainer> thumbnail_widgets;
    private List<Gtk.Box> thumbnail_boxes;
    private static Thumbnails factory;
    private static string THUMBNAIL_SIZE_STRING;
    private bool is_dir;

    static construct {
        THUMBNAIL_SIZE_STRING = FileAttribute.THUMBNAIL_PATH_LARGE;
        factory = Thumbnails.get_instance(THUMBNAIL_SIZE_STRING);
    }

    public void foreach_item(owned Func<Gtk.Box> func) {
        foreach (var item in thumbnail_boxes) {
            func(item);
        }
    }

    public override bool movable
    {
        get {
            return true;
        }
    }


    public FolderItem(string label, string uri) {

        var folder = File.new_for_uri(uri);
        var path = folder.get_path();
        string icon_name = get_folder_icon_name(folder);
        var folder_icon = new FolderIcon(icon_name);

        Object(
            label: label,
            user_id: uri,
            icon: folder_icon,
            hash: "FolderItem".hash() ^ uri.hash()
        );
        folder_icon.add_parent(this);

        this.folder = folder;
        this.recent_files = new HashTable<string, FileInfo>(str_hash, str_equal);

        this.thumbnail_widgets = new List<unowned Thumbnails.ThumbnailContainer>();
        this.thumbnail_boxes = new List<Gtk.Box>();

        setup_folder_monitor();
        update_nice_boxes();
        this.is_dir = (GLib.FileUtils.test(path, GLib.FileTest.IS_DIR));
        this.add_css_class("folder");
        add_css_class(label);
    }

    public override bool handle_click(int n_press) {
        return true;
    }

    public override bool can_handle_mime_type(File file, string mime_type) {
        File? parent = file.get_parent();
        if (parent != null) {
            string? parent_path = parent.get_path();
            if (parent_path != null && parent_path == this.user_id) {
                return false;
            }
        }
        return this.is_dir;
    }


    private static string get_folder_icon_name(File file) {
        try {
            var info = file.query_info("standard::icon", FileQueryInfoFlags.NONE);
            var icon = info.get_icon();
            if (icon is ThemedIcon) {
                var themed_icon = (ThemedIcon) icon;
                return themed_icon.get_names()[0];
            }
        } catch (Error e) {
            warning("Failed to get folder icon: %s", e.message);
        }
        return "folder";
    }


    private Gdk.Texture? load_thumbnail(File file, FileInfo file_info) {
        try {
            var thumbnail_path = file_info.get_attribute_byte_string(THUMBNAIL_SIZE_STRING);

            if (thumbnail_path != null && FileUtils.test(thumbnail_path, FileTest.EXISTS)) {
                return Gdk.Texture.from_filename(thumbnail_path);
            }

            string? path = file.get_path();
            if (path != null && Utils.create_thumbnail(path, Thumbnails.size)) {
                file_info = file.query_info(THUMBNAIL_SIZE_STRING, FileQueryInfoFlags.NONE);
                thumbnail_path = file_info.get_attribute_byte_string(THUMBNAIL_SIZE_STRING);
                if (thumbnail_path != null) {
                    return Gdk.Texture.from_filename(thumbnail_path);
                }
            }
        } catch (Error e) {
            warning("Error loading thumbnail: %s", e.message);
        }
        return null;
    }

    private class FolderIcon : Icon {
        private unowned FolderItem parent_item;

        public FolderIcon(string icon_name) {
            Object(icon_name: icon_name);
        }

        public void add_parent(FolderItem parent) {
            this.parent_item = parent;
        }

        public override void size_allocate(int width, int height, int baseline) {
            base.size_allocate(width, height, baseline);
            // thumbnail_widgets belongs to the parent!
            int max_length = int.min(MAX_OVERLAY_ITEMS, (int)parent_item.thumbnail_widgets.length());
            for (int i = 0; i < max_length; i++) {
                unowned Thumbnails.ThumbnailContainer thumbnail = parent_item.thumbnail_widgets.nth_data(i);
                thumbnail.allocate(width, width, baseline, null);
            }
        }

        public override void snapshot(Gtk.Snapshot snapshot) {
            base.snapshot(snapshot);
            int max_length = int.min(MAX_OVERLAY_ITEMS, (int)parent_item.thumbnail_widgets.length());
            for (int i = 0; i < max_length; i++) {
                unowned Thumbnails.ThumbnailContainer child = parent_item.thumbnail_widgets.nth_data(i);
                snapshot_child(child, snapshot);
            }
        }
    }


    private string ATTRIBUTES = FileAttribute.STANDARD_NAME + "," +
                     FileAttribute.TIME_MODIFIED + "," +
                     FileAttribute.STANDARD_CONTENT_TYPE + "," +
                     FileAttribute.STANDARD_DISPLAY_NAME + "," +
                     FileAttribute.STANDARD_ICON + "," +
                     THUMBNAIL_SIZE_STRING;

    private void setup_folder_monitor() {
        try {

            folder_monitor = folder.monitor_directory(FileMonitorFlags.NONE);
            try {
                var enumerator = folder.enumerate_children(ATTRIBUTES, FileQueryInfoFlags.NONE);

                FileInfo file_info;
                while ((file_info = enumerator.next_file()) != null) {
                    recent_files.set(file_info.get_name(), file_info);
                }
            } catch (Error e) {
                warning("Error updating recent files: %s", e.message);
            }

            folder_monitor.changed.connect((src, dest, event) => {
                on_directory_changed(src, dest, event);
            });
        } catch (Error e) {
            warning("Failed to set up folder monitor: %s", e.message);
        }
    }

    private void on_directory_changed(File file, File? other_file, FileMonitorEvent event_type) {
        if (!file.query_exists()) {
            event_type = FileMonitorEvent.DELETED;
        }
        string? name = file.get_basename();
        if (name == null) {
            message("name is null");
            return;
        }

        switch (event_type) {
            // case FileMonitorEvent.CREATED:
            case FileMonitorEvent.CHANGES_DONE_HINT:
                    Timeout.add(1000, () => {
                        try {
                            FileInfo file_info = file.query_info(ATTRIBUTES, FileQueryInfoFlags.NONE);
                            if (!recent_files.contains(name)) {
                                recent_files.set(name, file_info);
                                update_nice_boxes();
                            }
                        } catch (Error e) {
                            message("failed: %s", e.message);
                            if (recent_files.contains(name)) {
                                recent_files.remove(name);
                                update_nice_boxes();
                            }
                        }
                        return false;
                    });
                break;
            case FileMonitorEvent.DELETED:
                if (recent_files.contains(name)) {
                    recent_files.remove(name);
                    update_nice_boxes();
                }
                break;
            default:
                break;
        }
    }

    private void update_nice_boxes() {
        var file_list = new List<unowned FileInfo>();
        var iter = HashTableIter<string, FileInfo>(recent_files);
        FileInfo fi;
        while (iter.next(null, out fi)) {
            file_list.append(fi);
        }

        // Sort the list
        file_list.sort((a, b) => {
            int64 time_a = a.get_modification_date_time().to_unix();
            int64 time_b = b.get_modification_date_time().to_unix();
            return (int)(time_b - time_a);
        });

        thumbnail_widgets.foreach((item) => {
            item.unparent();
        });
        int tw_length = (int)thumbnail_widgets.length();
        for(int i = 0; i < tw_length; i++) {
            thumbnail_widgets.remove(thumbnail_widgets.nth_data(0));
        }

        int tu_length = (int)thumbnail_boxes.length();
        for(int i = 0; i < tu_length; i++) {
            thumbnail_boxes.remove(thumbnail_boxes.nth_data(0));
        }

        var icon_theme = Gtk.IconTheme.get_for_display(get_display());
        int scale_factor = get_scale_factor();

        foreach (unowned FileInfo file_info in file_list) {
            var item_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0) {
                halign = Gtk.Align.CENTER,
                valign = Gtk.Align.START,
            };

            var file = folder.get_child(file_info.get_name());
            string file_path = file.get_path();

            Gdk.Paintable? paintable = null;

            // Try to load thumbnail
            var thumbnail_path = file_info.get_attribute_byte_string(THUMBNAIL_SIZE_STRING);
            if (thumbnail_path != null && FileUtils.test(thumbnail_path, FileTest.EXISTS)) {
                try {
                    paintable = Gdk.Texture.from_filename(thumbnail_path);
                } catch (Error e) {
                    warning("Failed to load thumbnail: %s", e.message);
                }
            } else if (Utils.create_thumbnail(file_path, Thumbnails.size)) {
                paintable = load_thumbnail(file, file_info);
            }

            // If no thumbnail, use the file's icon
            bool is_thumbnail = true;
            if (paintable == null) {
                var icon = file_info.get_icon();
                paintable = icon_theme.lookup_by_gicon(icon, Thumbnails.size, scale_factor, Gtk.TextDirection.NONE, Gtk.IconLookupFlags.PRELOAD);
                is_thumbnail = false;
            }

            var thumbnail_widget = factory.create_thumbnail(paintable, file, is_thumbnail, scale_factor);

            if (thumbnail_widgets.length() < MAX_OVERLAY_ITEMS) {
                if (!(GLib.FileUtils.test(file.get_path(), GLib.FileTest.IS_DIR))) {
                    var thumbnail_widget_copy = factory.create_thumbnail(paintable, file, is_thumbnail, scale_factor);
                    thumbnail_widget_copy.can_target = false;
                    thumbnail_widgets.append(thumbnail_widget_copy);
                    thumbnail_widget_copy.set_parent(icon);
                }
            }

            var label = new Gtk.Label(file_info.get_display_name()) {
                ellipsize = Pango.EllipsizeMode.END,
                max_width_chars = 15,
                can_target = false,
            };

            item_box.append(thumbnail_widget);
            item_box.append(label);
            thumbnail_boxes.append(item_box);
        }
        thumbnail_widgets.reverse();
    }

    public override bool handle_dropped_file(File file) {
        try {
            var dest_file = folder.get_child(file.get_basename());
            file.move(dest_file, FileCopyFlags.NONE);
            update_nice_boxes();
            queue_draw();
            return true;
        } catch (Error e) {
            warning("Failed to move file %s to folder %s: %s", file.get_path(), user_id, e.message);
        }
        return false;
    }
}
