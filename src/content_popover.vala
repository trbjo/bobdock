public class ContentPopOver : Gtk.Popover {

    private Gtk.ScrolledWindow scrolled_window;
    private Gtk.Box popover_box;
    private Gtk.FlowBox flow_box;
    internal Gtk.Label folder_label;

    construct {
        autohide = false;
        can_focus = false;
        has_arrow = true;


        add_css_class("folder-view");


        flow_box = new Gtk.FlowBox() {
            homogeneous = true,
            max_children_per_line = 3,
            selection_mode = Gtk.SelectionMode.NONE,
        };

        scrolled_window = new Gtk.ScrolledWindow();
        scrolled_window.set_child(flow_box);
        scrolled_window.set_size_request(450, 450);

        folder_label = new Gtk.Label("Folder View") {
            css_classes = {"header"}
        };
        popover_box = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
        popover_box.append(folder_label);
        popover_box.append(scrolled_window);

        set_child(popover_box);

        flow_box.child_activated.connect((fb) => {
            this.popdown();
            if (fb == null || !(fb is Gtk.FlowBoxChild)) {
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
        });

        var dock_item_source = new Gtk.DragSource();
        dock_item_source.prepare.connect((source_origin, x, y) => {
            var fixed_widget = source_origin.get_widget();
            var picked_widget = fixed_widget.pick(x, y, Gtk.PickFlags.DEFAULT);

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

            double outer_height =  (double)paintable.get_intrinsic_height();
            double outer_width =  (double)paintable.get_intrinsic_width();

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
                    var file_provider = new Gdk.ContentProvider.for_bytes(file_info.get_content_type(), Utils.load_file_content(thumb.file));
                    return new Gdk.ContentProvider.union({
                        uri_provider,
                        file_provider,
                        gnome_copied_files_provider,
                        text_plain_provider
                    });
                } else {
                    return new Gdk.ContentProvider.union({
                        uri_provider,
                        gnome_copied_files_provider,
                        text_plain_provider
                    });
                }
            } catch (Error e) {
                warning("Error getting file info for thumbnail: %s", e.message);
                return null;
            }
        });


        bool drop_accepted = false;
        dock_item_source.drag_begin.connect((drag) => {
            drop_accepted = false;
            drag.drop_performed.connect(() => {
                drop_accepted = true;
            });

            drag.dnd_finished.connect(() => {
                if (drop_accepted) {
                    this.popdown();
                }
                drop_accepted = false;
            });
        });

        dock_item_source.drag_cancel.connect((source_origin, drag, reason) => {
            return false;
        });
        flow_box.add_controller(dock_item_source);
    }

    public void open_popup(FolderItem fi, int x, int y) {
        scrolled_window.hadjustment.value = 0.0;
        unowned Gtk.Widget flowbox_child = flow_box.get_first_child();
        while (flowbox_child != null) {
            flow_box.remove(flowbox_child);
            flowbox_child = flow_box.get_first_child();
        }

        folder_label.label = fi.label;
        fi.foreach_item((item_box) => {
            flow_box.append(item_box);
        });

        this.set_pointing_to({ x, y, 1, 1 });

        this.popup();
        scrolled_window.vadjustment.value = 0.0;
    }
}
