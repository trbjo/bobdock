public class PopupManager : Gtk.Popover {
    private static PopupManager? instance;
    private Gtk.ScrolledWindow scrolled_window;
    private Gtk.Box popover_box;
    private Gtk.FlowBox flow_box;
    private Gtk.Label label;

    private static unowned AppSettings settings;

    static construct {
        settings =  AppSettings.get_default();
    }

    private PopupManager() { }

    public static PopupManager get_default() {
        if (instance == null) {
            instance = new PopupManager();
        }
        return instance;
    }

    construct {
        autohide = false;
        can_focus = false;

        settings.layershell_edge_change.connect_after((new_direction) =>
                set_position(Utils.orientation_to_position(new_direction)));
        setup_popover();
        setup_drag_source();
        set_hover_mode();
    }

    public signal void popup_opened(FolderItem dockable);
    public signal void popup_closed();
    public signal void selected_item();

    private void setup_popover() {
        flow_box = new Gtk.FlowBox() {
            homogeneous = true,
            max_children_per_line = 3,
            selection_mode = Gtk.SelectionMode.NONE,
        };
        flow_box.child_activated.connect(on_flow_box_child_activated);

        scrolled_window = new Gtk.ScrolledWindow();
        scrolled_window.set_child(flow_box);

        label = new Gtk.Label(null) {
            css_classes = {"header"},
            ellipsize = Pango.EllipsizeMode.END,
            max_width_chars = settings.hover_label_max_length,
            hexpand = true,
            can_focus = false,
            can_target = false,
        };
        settings.hover_label_max_length_changed.connect(label.set_max_width_chars);
        popover_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        popover_box.append(label);
        popover_box.append(scrolled_window);
        this.set_child(popover_box);
    }

    private void on_flow_box_child_activated(Gtk.FlowBoxChild fb) {
        if (fb == null) {
            return;
        }
        unowned Gtk.Widget child = fb.get_child();
        if (child == null || !(child is Gtk.Box)) {
            return;
        }
        child = ((Gtk.Box)child).get_first_child();
        if (child == null || !(child is Thumbnails.ThumbnailContainer)) {
            return;
        }
        unowned Thumbnails.ThumbnailContainer thumb = (Thumbnails.ThumbnailContainer)child;
        thumb.handle_click();

        set_hover_mode();
        selected_item();
        this.visible = false;
    }

    private void setup_drag_source() {
        var dock_item_source = new Gtk.DragSource();
        dock_item_source.prepare.connect((source_origin, x, y) => {
            dock_item_source.set_state(Gtk.EventSequenceState.CLAIMED);

            var picked_widget = source_origin.get_widget().pick(x, y, Gtk.PickFlags.DEFAULT);

            if (picked_widget == null || !(picked_widget is Thumbnails.ThumbnailContainer.ThumbnailWidget)) {
                return null;
            }
            unowned Thumbnails.ThumbnailContainer.ThumbnailWidget inner = (Thumbnails.ThumbnailContainer.ThumbnailWidget)picked_widget;
            unowned Gtk.Widget outer = inner.get_parent();
            if (outer == null || !(outer is Thumbnails.ThumbnailContainer)) {
                return null;
            }
            unowned Thumbnails.ThumbnailContainer thumb = (Thumbnails.ThumbnailContainer)outer;
            string uri = thumb.file.get_uri();
            var paintable = new Gtk.WidgetPaintable(thumb);

            double outer_height = (double)paintable.get_intrinsic_height();
            double outer_width = (double)paintable.get_intrinsic_width();

            double inner_height =  (double)thumb.thumbnail.get_height();
            double inner_width =  (double)thumb.thumbnail.get_width();
            int hot_x = (int)((outer_width/2.0) - (inner_width/2.0));
            int hot_y = (int)((outer_height/2.0) - (inner_height/2.0));


            source_origin.set_icon(paintable, hot_x, hot_y);

            var uri_provider = new Gdk.ContentProvider.for_bytes("text/uri-list", new Bytes(thumb.file.get_uri().data));
            var gnome_copied_files_provider = new Gdk.ContentProvider.for_bytes(
                "application/x-gnome-copied-files",
                new Bytes(("copy\n" + uri).data)
            );

            var text_plain_provider = new Gdk.ContentProvider.for_bytes(
                "text/plain",
                new Bytes(thumb.file.get_path().data)
            );

            try {
                FileInfo file_info = thumb.file.query_info(FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE);
                if (file_info.get_content_type().has_prefix("text")) {
                    return new Gdk.ContentProvider.union({
                        uri_provider,
                        new Gdk.ContentProvider.for_bytes(file_info.get_content_type(), Utils.load_file_content(thumb.file)),
                        gnome_copied_files_provider,
                        text_plain_provider
                    });
                }
            } catch (Error e) {
                warning("Error getting file info for thumbnail: %s", e.message);
            }

            return new Gdk.ContentProvider.union({
                uri_provider,
                gnome_copied_files_provider,
                text_plain_provider
            });
        });

        dock_item_source.drag_begin.connect((drag) => {
            drag.drop_performed.connect(() => {
                set_hover_mode();
            });

            drag.dnd_finished.connect(() => {
                dock_item_source.set_state(Gtk.EventSequenceState.DENIED);
                this.visible =  false;
            });
        });

        flow_box.add_controller(dock_item_source);
    }


    public bool in_popup_mode() {
        return scrolled_window.visible;
    }

    private void set_hover_mode() {
        if (scrolled_window.visible) {
            has_arrow = scrolled_window.visible = false;
            this.remove_css_class("open");
            popup_closed();
        }

        if (get_parent() != null) {
            this.visible = true;
        }
    }

    private void set_popup_mode(Item item) {
        if (get_parent() == null) {
            return;
        }
        var folder_item = (FolderItem)item;
        flow_box.remove_all();

        folder_item.foreach_item((item_box) => {
            flow_box.append(item_box);
        });

        scrolled_window.vadjustment.value = 0.0;
        this.visible = has_arrow = scrolled_window.visible = true;
        this.add_css_class("open");
        popup_opened(folder_item);
    }

    public void handle_hover_leave() {
        if (in_popup_mode()) {
            return;
        }
        if (parent != null) {
            this.visible = false;
        }
    }

    public void update_popover_label(Item item) {
        if (get_parent() != item) {
            return;
        }

        bool changed_label = label.label != item.label;
        if (changed_label) {
            label.label = item.label;
            this.present();
        }
    }

    public void handle_hover_for(Item item) {
        if (in_popup_mode()) {
            return;
        }
        update_parent(item);
        update_popover_label(item);
        set_hover_mode();
    }

    public void update_parent(Item item) {
        unowned Gtk.Widget parent = get_parent();

        if (parent == item) {
            return;
        }
        if (parent != null) {
            this.unparent();
        }
        this.set_parent(item);
    }

    public void handle_click_for(Item item) {
        if (!(item is FolderItem)) {
            update_parent(item);
            set_hover_mode();
            return;
        }

        if (get_parent() == item && in_popup_mode()) {
            set_hover_mode();
            return;
        }
        set_popup_mode(item);
        update_parent(item);
        this.present();
    }
}
