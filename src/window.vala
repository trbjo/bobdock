public class DockWindow : Gtk.Window {
    private ContentPopOver content_popover;
    private Dock dock;

    private Gtk.GestureDrag drag_gesture;
    private Gtk.DragSource dock_item_source;
    private Gtk.GestureClick click_controller;
    private Gtk.EventControllerMotion motion_controller;

    private Gtk.GestureLongPress long_press;

    private bool _is_long_pressed;
    private bool is_long_pressed {
        get {
            _is_long_pressed = _is_long_pressed && long_press.get_current_button() != 0;
            return _is_long_pressed;
        }
    }



    private static Gtk.CssProvider css_provider;
    private static AppSettings settings;

    static construct {
        settings = AppSettings.get_default();
        css_provider = new Gtk.CssProvider();
    }


    unowned DockItem? hovered_widget = null;
    private unowned FolderItem? _current_folder = null;
    unowned FolderItem? current_folder {
        get {
            return _current_folder;
        }
        set {
            if (value != _current_folder) {
                if (_current_folder != null) {
                    _current_folder.unset_state_flags(Gtk.StateFlags.SELECTED);
                }
                _current_folder = value;
                if (_current_folder != null) {
                    _current_folder.set_state_flags(Gtk.StateFlags.SELECTED, true);
                }
            }
        }
    }


    public DockWindow(Gtk.Application app, IDesktopConnector conn) {
        Object(application: app);
        conn.apps_changed.connect(dock.set_window_items);
    }

    public string gtk_ls_to_string() {
        switch (settings.edge) {
            case GtkLayerShell.Edge.LEFT:
                return "left";
            case GtkLayerShell.Edge.RIGHT:
                return "right";
            case GtkLayerShell.Edge.TOP:
                return "top";
            case GtkLayerShell.Edge.ENTRY_NUMBER:
            case GtkLayerShell.Edge.BOTTOM:
            default:
                return "bottom";
        }
    }

    construct {
        title = "BobDock";
        decorated = false;
        resizable = false;
        css_classes = {gtk_ls_to_string(), "first-render", "hidden"};

        setup_layer_shell();

        content_popover = new ContentPopOver();
        content_popover.set_parent(this);


        dock = new Dock();
        this.set_child(dock);

        dock.background.secondary_size_changed.connect(() => {
            correct_hidden_margin();
            correct_exclusive_zone();
        });

        setup_controllers();
        setup_drag_handler();

        settings.scale_factor_changed.connect((scale) => {
            if (content_popover.visible || !motion_controller.contains_pointer || is_long_pressed) {
                return;
            }
            dock.on_max_scale_changed(scale);
        });

        settings.dock_folders_changed.connect(() => dock.add_folder_items(settings.get_folder_items()));
        dock.add_folder_items(settings.get_folder_items());

        settings.dock_apps_changed.connect(() => dock.app_items_changed(settings.get_app_items()));
        dock.app_items_changed(settings.get_app_items());

        settings.layershell_edge_change.connect((new_direction) => {
            content_popover.set_position(Utils.orientation_to_position(new_direction));
            update_edge_anchors();
        });
        content_popover.set_position(Utils.orientation_to_position(settings.edge));

        dock.scaled_up.connect(() => {
            adjust_hover_label(hovered_widget);
        });

        map.connect(() => {
            update_edge_anchors();

            // this is run right after we get the first margin
            run_layout(this, () => {
                correct_hidden_margin();
            });

            // this is run after the first paint
            run_after_paint(this, () => {
                set_auto_hide(settings.auto_hide);
                settings.autohide_changed.connect(set_auto_hide);
                remove_css_class("first-render");
            });
        });
    }

    private void setup_controllers () {
        motion_controller = new Gtk.EventControllerMotion();
        motion_controller.leave.connect((motion) => dock.scale_down());
        motion_controller.set_propagation_limit(Gtk.PropagationLimit.SAME_NATIVE);
        motion_controller.motion.connect((motion, x, y) => {
            double _x = settings.edge == GtkLayerShell.Edge.BOTTOM ? x : dock.bg_inner_size() / 2.0;
            double _y = settings.edge == GtkLayerShell.Edge.BOTTOM ? dock.bg_inner_size() / 2.0 : y;

            unowned Gtk.Widget? picked_widget = dock.pick(_x, _y, Gtk.PickFlags.DEFAULT);
            hovered_widget = (picked_widget is DockItem) ? (DockItem)picked_widget : null;
            if (content_popover.visible || is_long_pressed || dock_item_source.is_active()) {
                return;
            }
            dock.request_motion(settings.edge == GtkLayerShell.Edge.BOTTOM ? x : y);
        });

        ((Gtk.Widget)this).add_controller(motion_controller);

        click_controller = new Gtk.GestureClick();
        click_controller.released.connect((n_press, x, y) => {
            if (is_long_pressed) {
                click_controller.set_state(Gtk.EventSequenceState.DENIED);
                return;
            }

            if (hovered_widget == null) {
                return;
            }

            if ((!(hovered_widget is FolderItem))) {
                content_popover.popdown();
            }

            if (!hovered_widget.visible) {
                hovered_widget = (DockItem)hovered_widget.get_next_sibling();
            }

            if (!(hovered_widget is FolderItem)) {
                current_folder = null;
                hovered_widget.handle_click();
                return;
            }

            unowned FolderItem fi = (FolderItem)hovered_widget;
            if (current_folder == fi && content_popover.visible) {
                content_popover.popdown();
                current_folder = null;
                dock.scale_up();
            } else {
                bool bottom = settings.edge == GtkLayerShell.Edge.BOTTOM;
                bool left = settings.edge == GtkLayerShell.Edge.LEFT;

                Graphene.Rect bounds;
                fi.compute_bounds(this, out bounds);
                float start = bottom ? bounds.origin.x + bounds.size.width / 2.0f : bounds.origin.y + bounds.size.height / 2.0f;

                int _x = bottom ? (int)start : left ? dock.bg_inner_size() -1 : 1;
                int _y = bottom ? 1 : (int)start;
                content_popover.open_popup(fi, (int)_x, (int)_y);
                current_folder = fi;
            }
        });
        ((Gtk.Widget)this).add_controller(click_controller);

        content_popover.notify["visible"].connect(() => {
            if (content_popover.visible) {
                this.add_css_class("popover-open");
                dock.scale_down();
            } else {
                this.remove_css_class("popover-open");
                dock.queue_resize();
            }
        });



        var scroll_controller = new Gtk.EventControllerScroll(Gtk.EventControllerScrollFlags.VERTICAL);
        scroll_controller.scroll.connect((dx, dy) => {
            if (!content_popover.visible) {
                settings.max_icon_size += (dy < 0 ? -1 : 1);
            }
            return true;
        });

        ((Gtk.Widget)this).add_controller(scroll_controller);

        var dock_item_target = new Gtk.DropTarget(typeof(Gtk.Widget), Gdk.DragAction.COPY);
        var file_drop_target = new Gtk.DropTarget(typeof(File), Gdk.DragAction.COPY);

        dock_item_target.enter.connect(drop_enter_widget);
        file_drop_target.enter.connect(drop_enter_file);


        dock_item_target.motion.connect((target, x, y) => {
            double _x = settings.edge == GtkLayerShell.Edge.BOTTOM ? x : dock.bg_inner_size() / 2;
            double _y = settings.edge == GtkLayerShell.Edge.BOTTOM ? dock.bg_inner_size() / 2 : y;

            unowned Gtk.Widget? picked_widget = dock.pick(_x, _y, Gtk.PickFlags.DEFAULT);

            hovered_widget = (picked_widget is DockItem) ? (DockItem)picked_widget : null;
            adjust_hover_label(hovered_widget);

            return drop_motion(picked_widget, x, y, dock);
        });
        file_drop_target.motion.connect((target, x, y) => {
            double _x = settings.edge == GtkLayerShell.Edge.BOTTOM ? x : dock.bg_inner_size() / 2;
            double _y = settings.edge == GtkLayerShell.Edge.BOTTOM ? dock.bg_inner_size() / 2 : y;

            unowned Gtk.Widget? picked_widget = dock.pick(_x, _y, Gtk.PickFlags.DEFAULT);
            hovered_widget = (picked_widget is DockItem) ? (DockItem)picked_widget : null;
            adjust_hover_label(hovered_widget);

            return drop_motion(picked_widget, x, y, dock);
        });

        file_drop_target.drop.connect(drop_file);
        dock_item_target.drop.connect(drop_widget);

        dock_item_target.leave.connect(drop_leave);
        file_drop_target.leave.connect(drop_leave);
        ((Gtk.Widget)this).add_controller(dock_item_target);
        ((Gtk.Widget)this).add_controller(file_drop_target);

        dock_item_source = new Gtk.DragSource();
        dock_item_source.prepare.connect((source_origin, x, y) => {
            if (is_long_pressed) {
                dock_item_source.set_state(Gtk.EventSequenceState.DENIED);
                return null;
            }
            dock_item_source.set_state(Gtk.EventSequenceState.CLAIMED);
            var fixed_widget = source_origin.get_widget();

            unowned MouseAble? picked_widget = get_focused_item(fixed_widget, x,y);
            if (picked_widget == null) {
                return null;
            }

            if (picked_widget is DockItem) {
                fixed_widget.set_data<DockItem>("dragged-item", (DockItem)picked_widget);
                return new Gdk.ContentProvider.for_value(fixed_widget);
            } else {
                return null;
            }
        });


        dock_item_source.drag_begin.connect((source_origin, drag) => {
            var fixed_widget = source_origin.get_widget();
            var app_item = fixed_widget.get_data<DockItem>("dragged-item");

            var paintable = new Gtk.WidgetPaintable (app_item);
            source_origin.set_icon(paintable, 0, 0);
        });

        dock_item_source.drag_end.connect((source_origin, drag, delete_data) => {
            source_origin.get_widget().set_data("dragged-item", null);
        });

        dock_item_source.drag_cancel.connect((source_origin, drag, reason) => {
            return false;
        });

        ((Gtk.Widget)this).add_controller(dock_item_source);
    }

    public delegate void Action();
    public void run_after_paint(Gtk.Widget widget, owned Action action) {
        ulong id = 0;
        id = widget.get_frame_clock().after_paint.connect_after(() => {
            widget.get_frame_clock().disconnect(id);
            action();
        });
    }
    public void run_layout(Gtk.Widget widget, owned Action action) {
        ulong id = 0;
        id = widget.get_frame_clock().layout.connect(() => {
            widget.get_frame_clock().disconnect(id);
            action();
        });
    }

    public unowned MouseAble? get_focused_item(Gtk.Widget widget, double x, double y) {
        double _x = settings.edge == GtkLayerShell.Edge.BOTTOM ? x : (double)get_width() / 2.0;
        double _y = settings.edge == GtkLayerShell.Edge.BOTTOM ? ((double)get_height()) / 2.0 : y;

        var picked_widget = widget.pick(_x, _y, Gtk.PickFlags.DEFAULT);
        if (picked_widget is MouseAble) {
            return ((MouseAble)picked_widget);
        }
        return null;
    }


    private void update_edge_anchors() {
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.LEFT, settings.edge == GtkLayerShell.Edge.LEFT);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.RIGHT, settings.edge == GtkLayerShell.Edge.RIGHT);
        GtkLayerShell.set_anchor(this, GtkLayerShell.Edge.BOTTOM, settings.edge == GtkLayerShell.Edge.BOTTOM);

        var rect = Utils.get_current_display_size(this);

        if (settings.edge == GtkLayerShell.Edge.LEFT) {
            remove_css_class("bottom");
            remove_css_class("right");
            add_css_class("left");
            this.set_default_size(-1, rect.height);
        } else if (settings.edge == GtkLayerShell.Edge.RIGHT) {
            remove_css_class("bottom");
            remove_css_class("left");
            add_css_class("right");
            this.set_default_size(-1, rect.height);
        } else if (settings.edge == GtkLayerShell.Edge.BOTTOM) {
            remove_css_class("left");
            add_css_class("bottom");
            remove_css_class("right");
            this.set_default_size(rect.width, -1);
        }

        dock.queue_resize();
        correct_hidden_margin();
        correct_exclusive_zone();
    }

    private void correct_hidden_margin() {
        int margin = dock.bg_inner_size();
        string css = get_css_for_edge(margin, settings.edge);
        css_provider.load_from_string(css);
        WayLauncherStyleProvider.add_style_context(
            Gdk.Display.get_default(),
            css_provider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
        return;
    }

    private void correct_exclusive_zone() {
        int zone = GtkLayerShell.get_exclusive_zone(this);
        int margin = dock.bg_outer_size();
        if (zone != 0 && zone != margin) {
            GtkLayerShell.set_exclusive_zone(this, dock.bg_outer_size());
        }
    }

    private void setup_drag_handler() {
        double start_x = 0;
        double start_y = 0;


        drag_gesture = new Gtk.GestureDrag();
        long_press = new Gtk.GestureLongPress();
        long_press.pressed.connect((x, y) => {
            _is_long_pressed = true;
            drag_gesture.drag_begin(x, y);
        });

        long_press.cancelled.connect(() => {
            _is_long_pressed = false;
        });
        ((Gtk.Widget)this).add_controller(long_press);



        drag_gesture.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
        drag_gesture.drag_begin.connect((x, y) => {
            if (!is_long_pressed) {
                return;
            }

            if (content_popover.visible) {
                drag_gesture.set_state(Gtk.EventSequenceState.DENIED);
                return;
            }

            this.set_state_flags(Gtk.StateFlags.DROP_ACTIVE, false);

            Gdk.Rectangle? rect = Utils.get_current_display_size(this);
            if (rect == null) return;
            dock.scale_down();

            if (settings.edge == GtkLayerShell.Edge.RIGHT) {
                start_x = rect.width - (get_width() - x);
            } else {
                start_x = x;
            }
            if (settings.edge == GtkLayerShell.Edge.BOTTOM) {
                start_y = rect.height - (get_height() - y);
            } else {
                start_y = y;
            }

            drag_gesture.set_state(Gtk.EventSequenceState.CLAIMED);
            this.get_surface().set_cursor(new Gdk.Cursor.from_name("grab", null));
        });

        double threshold = 0.2;

        drag_gesture.drag_update.connect((x, y) => {
            if (!is_long_pressed) {
                return;
            }
            Gdk.Rectangle? rect = Utils.get_current_display_size(this);
            if (rect == null) return;

            int delta_x = (int)Math.round(start_x + x);
            int delta_y = (int)Math.round(start_y + y);
            double horiz_percentage = delta_x / ((double)rect.width);
            double verti_percentage = delta_y / ((double)rect.height);

            bool shift_right = (horiz_percentage > 1.0 - threshold);
            bool shift_left = (horiz_percentage < threshold);
            bool shift_bottom = (verti_percentage > 1.0 - threshold);

            if (shift_bottom && !shift_right && !shift_left) {
                settings.edge = GtkLayerShell.Edge.BOTTOM;
            } else if (shift_right && !shift_bottom) {
                settings.edge = GtkLayerShell.Edge.RIGHT;
            } else if (shift_left && !shift_bottom) {
                settings.edge = GtkLayerShell.Edge.LEFT;
            }
        });

        drag_gesture.drag_end.connect((x, y) => {
            _is_long_pressed = false;
            this.unset_state_flags(Gtk.StateFlags.DROP_ACTIVE);

            drag_gesture.set_state(Gtk.EventSequenceState.DENIED);
            this.get_surface().set_cursor(new Gdk.Cursor.from_name("default", null));
         });
        ((Gtk.Widget)this).add_controller(drag_gesture);
    }

    public void adjust_hover_label(DockItem? hovered) {
        if (hovered == null || hovered.label == "" || (content_popover.visible && (get_state_flags() & Gtk.StateFlags.DROP_ACTIVE) == 0) || dock.current_scale != settings.max_scale) {
            // TODO: Add hover label
            return;
        }

        Graphene.Rect bounds;
        hovered.compute_bounds(this, out bounds);
        int x = 0;
        int y = 0;
        if (settings.edge == GtkLayerShell.Edge.BOTTOM) {
            x = (int)(bounds.origin.x + (bounds.size.width)/2.0);
            y = 0;
        } else if (settings.edge == GtkLayerShell.Edge.RIGHT) {
            x = 0;
            y = (int)(bounds.origin.y + (bounds.size.height)/2.0);
        } else if (settings.edge == GtkLayerShell.Edge.LEFT) {
            x = (int)bounds.size.width;
            y = (int)(bounds.origin.y + (bounds.size.height)/2.0);
        }
    }

    private void setup_layer_shell() {
        if (!GtkLayerShell.is_supported()) {
            warning("GtkLayerShell is not supported on your system");
            return;
        }

        GtkLayerShell.init_for_window(this);
        GtkLayerShell.set_layer(this, GtkLayerShell.Layer.TOP);
    }

    public void toggle_auto_hide() {
        settings.auto_hide = !settings.auto_hide;
    }

    public void set_auto_hide(bool hide) {
        if (hide) {
            this.add_css_class("hidden");
            GtkLayerShell.set_layer(this, GtkLayerShell.Layer.OVERLAY);
            GtkLayerShell.set_exclusive_zone(this, 0);
        } else {
            GtkLayerShell.set_layer(this, GtkLayerShell.Layer.TOP);
            GtkLayerShell.set_exclusive_zone(this, dock.bg_outer_size());
            this.remove_css_class("hidden");
        }
    }

    private void drop_leave() {
        dock.foreach_item((item, i) => {
            item.unset_state_flags(Gtk.StateFlags.INSENSITIVE);
        });
        unset_state_flags(Gtk.StateFlags.PRELIGHT);
        adjust_hover_label(null);
    }

    private Gdk.DragAction drop_enter_widget(Gtk.DropTarget target, double x, double y) {
        this.set_state_flags(Gtk.StateFlags.PRELIGHT, false);
        var drop = target.get_current_drop();
        if (drop == null) {
            return 0;
        }
        var formats = drop.get_formats();
        if (formats.contain_gtype(typeof(Gtk.Widget))) {
            dock.foreach_item((item, i) => {
                if ((item is WidgetHandler)) {
                    item.set_state_flags(Gtk.StateFlags.NORMAL, true);
                } else {
                    item.set_state_flags(Gtk.StateFlags.INSENSITIVE, true);
                }
            });
        }
        return Gdk.DragAction.COPY;
    }

    private Gdk.DragAction drop_enter_file(Gtk.DropTarget target, double x, double y) {
        this.set_state_flags(Gtk.StateFlags.PRELIGHT, false);

        var drop = target.get_current_drop();
        if (drop == null) {
            return 0;
        }

        var formats = drop.get_formats();
        if (formats.contain_gtype(typeof(File)) || formats.contain_mime_type("text/uri-list")) {

            drop.read_value_async.begin(typeof(File), 0, null, (obj, res) => {
                try {
                    var value = drop.read_value_async.end(res);
                    if (value.type() == typeof(File)) {
                        File current_drag_file = (File)value;
                        Utils.get_file_mime_type.begin(current_drag_file, (obj, res) => {
                            string? current_drag_mime_type = Utils.get_file_mime_type.end(res);
                            dock.foreach_item((item, i) => {
                                if (item.can_handle_mime_type(current_drag_file, current_drag_mime_type)) {
                                    item.set_state_flags(Gtk.StateFlags.NORMAL, true);
                                } else {
                                    item.set_state_flags(Gtk.StateFlags.INSENSITIVE, true);
                                }
                            });
                        });
                    }
                } catch (Error e) {
                    warning("Error reading drag content: %s", e.message);
                }
            });
        }
        return Gdk.DragAction.COPY;
    }

    private bool drop_widget(Gtk.DropTarget target, Value value, double x, double y) {
        if (hovered_widget == null) {
            return false;
        }

        if (!(hovered_widget is WidgetHandler)) {
            return false;
        }

        unowned WidgetHandler wh = (WidgetHandler)hovered_widget;
        if (value.type() == typeof(Gtk.Widget)) {
            Gtk.Widget widget = value as Gtk.Widget;
            if (widget == null) {
                warning("Failed to cast value to Gtk.Widget");
                return false;
            }

            var dock_item = widget.get_data<DockItem>("dragged-item");
            if (dock_item is DockItem) {
                return wh.handle_dropped_item(dock_item);
            }
        }
        return false;
    }

    private bool drop_file(Gtk.DropTarget target, Value value, double x, double y) {
        if (hovered_widget == null) {
            return false;
        }
        if (value.type() == typeof(File)) {
            File file = (File)value;
            return hovered_widget.handle_dropped_file(file);
        }
        return false;
    }

    private Gdk.DragAction drop_motion(Gtk.Widget? picked_widget, double x, double y, Dock dock) {
        dock.foreach_visible((item, i) => {
            if (item != picked_widget) {
                item.unset_state_flags(Gtk.StateFlags.PRELIGHT);
            }
        });

        if (picked_widget != null && (picked_widget is DockItem)) {
            picked_widget.set_state_flags(Gtk.StateFlags.PRELIGHT, true);
        }

        return Gdk.DragAction.COPY;
    }
}
