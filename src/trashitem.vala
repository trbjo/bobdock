public class TrashItem : Item, WidgetHandler {
    private File trash_dir;
    private string? trash_path;
    private FileMonitor trash_monitor;
    private uint update_icon_source_id = 0;

    public signal void dock_item_removed(Item item);

    public static TrashItem? create() {
        var item = new TrashItem();
        if (item.initialize()) {
            return item;
        }
        return null;
    }

    private TrashItem() {
        Object(
            label: "Trash",
            icon: new Icon.from_icon_name("user-trash"),
            hash: "Trash".hash()
        );
        css_classes = {"trash"};
    }

    private bool initialize() {
        if (!resolve_trash_path()) {
            return false;
        }

        setup_trash_monitor();
        update_icon_and_label();
        return true;
    }

    private bool resolve_trash_path() {
        var vfs = GLib.Vfs.get_default();
        trash_dir = vfs.get_file_for_uri("trash:///");

        trash_path = trash_dir.get_path();

        if (trash_path == null) {
            trash_path = Path.build_filename(Environment.get_home_dir(), ".local", "share", "Trash", "files");
        }

        var file = File.new_for_path(trash_path);
        if (!file.query_exists()) {
            warning("Trash directory does not exist: %s", trash_path);
            return false;
        }

        debug("Resolved trash path: %s", trash_path);
        return true;
    }

    private void setup_trash_monitor() {
        try {
            trash_monitor = trash_dir.monitor_directory(FileMonitorFlags.NONE, null);
            trash_monitor.changed.connect(() => {
                update_icon_and_label();
            });
        } catch (Error e) {
            warning("Failed to set up trash monitor: %s", e.message);
        }
    }

    private void update_icon_and_label() {
        if (update_icon_source_id != 0) {
            Source.remove(update_icon_source_id);
        }
        update_icon_source_id = Timeout.add(100, () => {
            update_icon_source_id = 0;
            if (trash_path == null) {
                return false;
            }
            try {
                int count = 0;
                Dir dir = Dir.open(trash_path, 0);
                while (dir.read_name() != null) {
                    count++;
                }

                icon.icon_name = count > 0 ? "user-trash-full" : "user-trash";
                change_badge_count(count);
                string items = count != 1 ? "%d items".printf(count) : "1 item";
                label = @"Trash ($items)";
                PopupManager.get_default().update_popover_label(this);
            } catch (Error e) {
                change_badge_count(-1);
                label = @"Trash (Failed to read contents)";
                warning("Failed to check trash contents: %s", e.message);
            }
            return false;
        });
    }

    public override bool can_handle_mime_type(File file, string mime_type) {
        return true; // TrashItem can handle all mime types
    }

    public override bool handle_dropped_file(File file) {
        try {
            return file.trash(null);
        } catch (Error e) {
            warning("Failed to move file %s to trash: %s", file.get_path(), e.message);
        }
        return false;
    }
    public override bool is_drag_source() { return false; }


    public override bool handle_click(int n_press) {
        open_trash();
        return true;
    }

    private void open_trash() {
        try {
            AppInfo.launch_default_for_uri("trash:///", null);
        } catch (Error e) {
            warning("Failed to open trash: %s", e.message);
        }
    }

    public bool handles_widget(Item item) {
        return item != this;
    }

    public bool handle_dropped_item(Item item) {
        message("TrashItem received dropped DockItem: %s", item.label);
        dock_item_removed(item);
        return true;
    }
}
