public class TrashItem : DockItem, MouseAble, WidgetHandler {
    private File trash_dir;
    private FileMonitor trash_monitor;
    private uint update_icon_source_id = 0;

    public signal void dock_item_removed(DockItem item);

    public TrashItem() {
        Object(label: "Trash", icon_name: "user-trash");
        trash_dir = File.new_for_uri("trash:///");
        setup_trash_monitor();
        update_icon();
    }

    private void setup_trash_monitor() {
        try {
            trash_monitor = trash_dir.monitor_directory(FileMonitorFlags.NONE, null);
            trash_monitor.changed.connect(() => {
                update_icon();
            });
        } catch (Error e) {
            warning("Failed to set up trash monitor: %s", e.message);
        }
    }

    private void update_icon() {
        if (update_icon_source_id != 0) {
            Source.remove(update_icon_source_id);
        }
        update_icon_source_id = Timeout.add(100, () => {
            update_icon_source_id = 0;
            try {
                var children = trash_dir.enumerate_children("standard::*", FileQueryInfoFlags.NONE);
                bool has_files = children.next_file() != null;
                icon_name = has_files ? "user-trash-full" : "user-trash";
            } catch (Error e) {
                warning("Failed to check trash contents: %s", e.message);
            }
            return false;
        });
    }

    public override bool handle_dropped_file(File file) {
        try {
            return file.trash(null);
        } catch (Error e) {
            warning("Failed to move file %s to trash: %s", file.get_path(), e.message);
        }
        return false;
    }

    public override bool handle_click() {
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

    public bool handle_dropped_item(DockItem item) {
        message("TrashItem received dropped DockItem: %s", item.label);
        dock_item_removed(item);
        return true;
    }


    protected override bool can_handle_mime_type(File file, string mime_type) {
        return true; // TrashItem can handle all mime types
    }
}
