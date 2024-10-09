public class Splitter : Item, WidgetHandler {
    public override bool handle_click(int n_press) {
        return false;
    }

    public signal int folder_dropped(FolderItem folder);
    public override bool is_drag_source() { return false; }

    protected override bool can_handle_mime_type(File file, string mime_type) {
        return true;
    }

    public bool handles_widget(Item item) {
        return item is AppItem;
    }

    public bool handle_dropped_item(Item item) {
        if (!(item is AppItem)) {
            return false;
        }


        return true;
    }

    public override bool handle_dropped_file(File file) {
        if (file.query_file_type(FileQueryInfoFlags.NONE) == FileType.DIRECTORY) {
            var folder_name = file.get_basename();
            var folder_path = file.get_path();
            folder_dropped(new FolderItem(folder_name, folder_path));
            return true;
        }
        return false;
    }

    private unowned Dock dock;

    public Splitter(Dock dock) {
        Object(
            label: "Drop Items here to add them to BobDock",
            icon: new Icon.from_icon_name("insert-object"),
            hash: "Splitter".hash()
        );
        css_classes = {"splitter"};
        visible = true;
        this.dock = dock;
        this.set_parent(dock);
        dock.state_flags_changed.connect(this.on_state_flags_changed);
    }

    private void on_state_flags_changed(Gtk.StateFlags old_flags) {
        var new_flags = dock.get_state_flags();
        old_flags &= ~Gtk.StateFlags.DIR_LTR;
        new_flags &= ~Gtk.StateFlags.DIR_LTR;
        bool is_drop_active = (new_flags & Gtk.StateFlags.DROP_ACTIVE) != 0;
        bool was_drop_active = (old_flags & Gtk.StateFlags.DROP_ACTIVE) != 0;

        if (!was_drop_active && is_drop_active) {
            // this.visible = true;
        } else if (!is_drop_active) {
            // this.visible = true;
        }
        // message("new_flags: %s, old_flags: %s", new_flags.to_string(), old_flags.to_string());
    }


}
