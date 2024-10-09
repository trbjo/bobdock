public class DockWindow : Gtk.Window {
    // window class that mostly acts as a controller
    private PopupManager popup_manager;
    private Dock dock;

    private Gtk.GestureDrag dock_drag;
    private Gtk.EventControllerMotion motion_controller;
    private Gtk.DragSource dock_item_source;

    private Gtk.GestureLongPress long_press;

    private static Gtk.CssProvider css_provider;
    private static AppSettings settings;

    static construct {
        settings = AppSettings.get_default();
        css_provider = new Gtk.CssProvider();
        PopupManager.get_default();
    }

    public DockWindow(Gtk.Application app, IDesktopConnector conn) {
        Object(application: app);
        conn.apps_changed.connect(dock.update_window_items);
    }

    construct {
        title = "BobDock";
        decorated = false;
        resizable = false;
        css_classes = {Utils.gtk_ls_to_string(settings.edge), "first-render", "hidden"};

        setup_layer_shell();

        popup_manager = PopupManager.get_default();

        dock = new Dock();
        child = dock;

        dock.add_folder_items(settings.get_folder_items());
        dock.app_items_changed(settings.get_app_items());

        unowned Gtk.Widget win_as_widget = ((Gtk.Widget)this);
        setup_drag_handler(win_as_widget);
        setup_controllers(win_as_widget);
        connect_signals();
    }

    private void setup_controllers(Gtk.Widget widget_controller) {
        popup_manager.popup_opened.connect((dock_item) => {
            this.add_css_class("popover-open");
            set_active_controller(DockWindow.Controller.POPUP, widget_controller);
            dock_item.set_state_flags(Gtk.StateFlags.SELECTED, false);
        });
        popup_manager.popup_closed.connect(() => {
            this.remove_css_class("popover-open");
            set_active_controller(DockWindow.Controller.MOTION, widget_controller);
        });

        motion_controller = new Gtk.EventControllerMotion();
        motion_controller.set_propagation_limit(Gtk.PropagationLimit.SAME_NATIVE);
        motion_controller.leave.connect(() => {
            set_active_controller(DockWindow.Controller.HOVER_LEAVE, widget_controller);
        });
        motion_controller.motion.connect((motion, x, y) => {
            dock.request_motion(settings.edge == GtkLayerShell.Edge.BOTTOM ? x : y);
        });
        widget_controller.add_controller(motion_controller);

        var scroll_controller = new Gtk.EventControllerScroll(Gtk.EventControllerScrollFlags.VERTICAL | Gtk.EventControllerScrollFlags.HORIZONTAL);
        scroll_controller.scroll.connect((dx, dy) => {
            if ((popup_manager.in_popup_mode() || has_flags(this, Gtk.StateFlags.DROP_ACTIVE))) {
                return false;
            }
            if (dx.abs() > dy.abs()) {
                settings.min_icon_size += (dx < 0 ? -1 : 1);
            } else {
                settings.max_icon_size += (dy < 0 ? -1 : 1);
            }
            return true;
        });

        widget_controller.add_controller(scroll_controller);

        var dock_item_target = new Gtk.DropTarget(typeof(Gtk.Widget), Gdk.DragAction.COPY);
        var file_drop_target = new Gtk.DropTarget(typeof(File), Gdk.DragAction.COPY);

        file_drop_target.enter.connect((target, x, y) => drop_setup(widget_controller, target, drop_enter_file));
        dock_item_target.enter.connect((target, x, y) => drop_setup(widget_controller, target, drop_enter_widget));

        file_drop_target.motion.connect(file_drop_motion);
        dock_item_target.motion.connect(widget_drop_motion);

        file_drop_target.drop.connect(drop_file);
        dock_item_target.drop.connect(drop_widget);

        file_drop_target.leave.connect(() => {
            set_active_controller(DockWindow.Controller.DROP_LEAVE, widget_controller);
        });

        dock_item_target.leave.connect(() => {
            widget_controller.unset_state_flags(Gtk.StateFlags.PRELIGHT);
        });

        widget_controller.add_controller(dock_item_target);
        widget_controller.add_controller(file_drop_target);

        dock_item_source = new Gtk.DragSource();
        dock_item_source.prepare.connect((source_origin, x, y) => {
            unowned Item? item = item_under_cursor(x, y);
            if (item != null) {
                dock_item_source.set_state(Gtk.EventSequenceState.CLAIMED);
                if (!item.movable) {
                    return null;
                }
                // set_active_controller(Controller.ITEM, widget_controller);
                if (item.is_drag_source()) {
                    item.add_css_class("dragging");
                    widget_controller.set_data<Item>("dragged-item", item);
                    item.set_state_flags(Gtk.StateFlags.SELECTED, true);
                    var paintable = Icon.retrieve_paintable(this, item.icon.icon_name, dock.current_max_size);
                    // var paintable = new Gtk.WidgetPaintable(item.icon);
                    source_origin.set_icon(paintable, paintable.get_intrinsic_width()/2, paintable.get_intrinsic_height()/2);
                } else {
                    this.get_surface().set_cursor(new Gdk.Cursor.from_name("not-allowed", null));
                }
                return new Gdk.ContentProvider.for_value(widget_controller);
            } else {
                set_active_controller(Controller.MOTION, widget_controller);
                return null;
            }
        });


        dock_item_source.drag_end.connect((source_origin, drag, delete_data) => {
            Item drop_source = source_origin.get_widget().get_data<Item>("dragged-item");
            source_origin.get_widget().set_data("dragged-item", null);
            dock_item_source.set_icon(null, 0, 0);
            set_active_controller(Controller.MOTION, widget_controller);

            if (drop_source == null) {
                return;
            }

            drop_source.remove_css_class("dragging");
            drop_source.remove_css_class("moved-backward");
            drop_source.remove_css_class("moved-forward");
            drop_source.queue_resize();
            if (drop_source.get_type() == FolderItem.TYPE) {
                string[] folders = {};
                dock.foreach_folder((folder) => {
                    folders += folder.user_id;
                });
                settings.dock_folders = folders;
            } else if (drop_source.get_type() == AppItem.TYPE) {
                string[] apps = {};
                dock.foreach_app((app) => {
                    if (app.pinned) {
                        apps+=app.user_id;
                    }
                });
                settings.dock_apps = apps;
            }
        });

        dock_item_source.drag_cancel.connect((source_origin, drag, reason) => {
            set_active_controller(Controller.MOTION, widget_controller);
            return false;
        });

        widget_controller.add_controller(dock_item_source);
    }

    private void connect_signals() {
        dock.background.secondary_size_changed.connect(() => {
            correct_hidden_margin();
            correct_exclusive_zone();
        });

        settings.sizes_changed.connect(dock.sizes_changed);
        settings.dock_folders_changed.connect(() => dock.add_folder_items(settings.get_folder_items()));
        settings.dock_apps_changed.connect(() => dock.app_items_changed(settings.get_app_items()));
        settings.layershell_edge_change.connect(() => update_edge_anchors());

        map.connect(() => {
            // ensure all subscribing members get the updated edge:
            settings.layershell_edge_change(settings.edge);

            // this is run right after we get the first margin
            ulong layout_id = 0;
            layout_id = this.get_frame_clock().layout.connect(() => {
                this.get_frame_clock().disconnect(layout_id);
                correct_hidden_margin();
            });

            // this is run after the first paint
            ulong after_paint_id = 0;
            after_paint_id = this.get_frame_clock().after_paint.connect_after(() => {
                this.get_frame_clock().disconnect(after_paint_id);
                set_auto_hide(settings.auto_hide);
                settings.autohide_changed.connect(set_auto_hide);
                remove_css_class("first-render");
            });
        });

        this.notify["scale-factor"].connect_after(() => {
            Idle.add(() => {
                update_edge_anchors();
                return false;
            });
        });
    }

    private unowned Item? item_under_cursor(double x, double y, Gtk.PickFlags flags = Gtk.PickFlags.DEFAULT) {
        double _x = settings.edge == GtkLayerShell.Edge.BOTTOM ? x : dock.bg_outer_size() / 2.0;
        double _y = settings.edge == GtkLayerShell.Edge.BOTTOM ? dock.bg_outer_size() / 2.0 : y;
        unowned Gtk.Widget? picked_widget = this.pick(_x, _y, flags);
        if (picked_widget != null && picked_widget is Icon) {
            return (Item)(picked_widget.get_parent());
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
        int margin = dock.background.last_size;
        string edge_class = Utils.gtk_ls_to_string(settings.edge);
        var css = "window.%s.hidden #dock { margin-%s: -%ipx; }".printf(edge_class, edge_class, margin);
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

    private void setup_drag_handler(Gtk.Widget widget_controller) {
        double start_x = 0;
        double start_y = 0;

        bool _is_long_pressed = false;

        dock_drag = new Gtk.GestureDrag();
        widget_controller.add_controller(dock_drag);
        long_press = new Gtk.GestureLongPress();
        widget_controller.add_controller(long_press);

        long_press.pressed.connect((x, y) => {
            if (popup_manager.in_popup_mode()) {
                return;
            }

            set_active_controller(Controller.DOCK, widget_controller);
            _is_long_pressed = true;
            Gdk.Rectangle? rect = Utils.get_current_display_size(this);
            if (rect == null) return;

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
        });

        double threshold = 0.2;

        dock_drag.drag_update.connect((x, y) => {
            if (!_is_long_pressed) {
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

        dock_drag.drag_end.connect((x, y) => {
            if(_is_long_pressed) {
                _is_long_pressed = false;
                set_active_controller(Controller.MOTION, widget_controller);
            }
         });
    }

    public enum Controller {
        MOTION,
        ITEM,
        DOCK,
        POPUP,
        DROP_LEAVE,
        HOVER_LEAVE,
    }

    private void set_active_controller(Controller controller, Gtk.Widget widget_controller) {
        // message("controller: %s", controller.to_string());

        switch (controller) {
            case DROP_LEAVE:
                popup_manager.handle_hover_leave();
                dock.scale_down();
                items_unset_state_flags(Gtk.StateFlags.DROP_ACTIVE | Gtk.StateFlags.INSENSITIVE);
                widget_controller.unset_state_flags(Gtk.StateFlags.DROP_ACTIVE);
                // dock.splitter.visible = false;
                break;
            case HOVER_LEAVE:
                dock.scale_down();
                popup_manager.handle_hover_leave();
                break;
            case POPUP:
                dock_drag.set_state(Gtk.EventSequenceState.DENIED);
                dock_item_source.set_state(Gtk.EventSequenceState.DENIED);

                dock_drag.set_propagation_phase(Gtk.PropagationPhase.NONE);
                dock_item_source.set_propagation_phase(Gtk.PropagationPhase.NONE);
                motion_controller.set_propagation_phase(Gtk.PropagationPhase.NONE);

                items_unset_state_flags(Gtk.StateFlags.ACTIVE | Gtk.StateFlags.SELECTED | Gtk.StateFlags.DROP_ACTIVE | Gtk.StateFlags.INSENSITIVE | Gtk.StateFlags.BACKDROP);
                dock.scale_down();
                break;
            case MOTION:
                dock.sensitive = true;
                dock_drag.set_state(Gtk.EventSequenceState.DENIED);
                dock_item_source.set_state(Gtk.EventSequenceState.DENIED);

                dock_drag.set_propagation_phase(Gtk.PropagationPhase.BUBBLE);
                dock_item_source.set_propagation_phase(Gtk.PropagationPhase.BUBBLE);
                motion_controller.set_propagation_phase(Gtk.PropagationPhase.BUBBLE);

                items_unset_state_flags(Gtk.StateFlags.ACTIVE | Gtk.StateFlags.SELECTED | Gtk.StateFlags.DROP_ACTIVE | Gtk.StateFlags.INSENSITIVE | Gtk.StateFlags.BACKDROP);
                this.get_surface().set_cursor(new Gdk.Cursor.from_name("default", null));

                widget_controller.unset_state_flags(Gtk.StateFlags.DROP_ACTIVE);
                // popup_manager.handle_hover_leave();
                break;
            case ITEM:
                dock_drag.set_state(Gtk.EventSequenceState.DENIED);
                dock_item_source.set_state(Gtk.EventSequenceState.CLAIMED);

                dock_drag.set_propagation_phase(Gtk.PropagationPhase.NONE);
                dock_item_source.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
                motion_controller.set_propagation_phase(Gtk.PropagationPhase.NONE);
                break;
            case DOCK:
                dock.sensitive = false;
                dock.scale_down();
                popup_manager.handle_hover_leave();

                this.get_surface().set_cursor(new Gdk.Cursor.from_name("grab", null));

                dock_drag.set_state(Gtk.EventSequenceState.CLAIMED);
                dock_item_source.set_state(Gtk.EventSequenceState.DENIED);

                dock_drag.set_propagation_phase(Gtk.PropagationPhase.CAPTURE);
                dock_item_source.set_propagation_phase(Gtk.PropagationPhase.NONE);
                motion_controller.set_propagation_phase(Gtk.PropagationPhase.NONE);
                break;
        }
    }

    private void items_unset_state_flags(Gtk.StateFlags flags) {
        dock.foreach_item((item) => {
            item.unset_state_flags(flags);
        });
    }
    private void items_set_state_flags(Gtk.StateFlags flags, bool clear) {
        dock.foreach_item((item) => {
            item.set_state_flags(flags, clear);
        });
    }

    private bool has_flags(Gtk.Widget widget, Gtk.StateFlags flags) {
        return (widget.get_state_flags() & flags) != 0;
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

    public delegate Gdk.DragAction DropEnterFunc(Gtk.DropTarget drop);

    private Gdk.DragAction drop_setup(Gtk.Widget widget_controller, Gtk.DropTarget target, DropEnterFunc func) {
        widget_controller.set_state_flags(Gtk.StateFlags.PRELIGHT, false);
        return func(target);
    }

    private Gdk.DragAction drop_enter_widget(Gtk.DropTarget target) {
        items_set_state_flags(Gtk.StateFlags.INSENSITIVE | Gtk.StateFlags.BACKDROP, false);
        var val = target.get_value();
        if (val != null) {
            var obj = val.get_object ();
            if (obj != null && obj is Item) {
                message("hello");
            }
        }
        var drop = target.get_current_drop();


        var formats = drop.get_formats();
        if (formats.contain_gtype(typeof(Gtk.Widget))) {
            drop.read_value_async.begin(typeof(Gtk.Widget), 0, null, (obj, res) => {
                try {
                    var value = drop.read_value_async.end(res);
                    if (value.type() == typeof(Gtk.Widget)) {
                        Gtk.Widget widget = (Gtk.Widget)value;
                        Item? dragged_item = widget.get_data<Item>("dragged-item");
                        if (dragged_item == null) {
                            return;
                        }
                        dock.foreach_item((item) => {
                            if (item is WidgetHandler && ((WidgetHandler)item).handles_widget(dragged_item)) {
                                item.unset_state_flags(Gtk.StateFlags.INSENSITIVE);
                            }
                        });
                    }
                } catch (Error e) {
                    warning("Error reading drag content: %s", e.message);
                }
            });
        }
        return 0;
    }

    private Gdk.DragAction drop_enter_file(Gtk.DropTarget target) {
        var drop = target.get_current_drop();

        items_set_state_flags(Gtk.StateFlags.INSENSITIVE, false);
        var formats = drop.get_formats();
        if (formats.contain_gtype(typeof(File)) || formats.contain_mime_type("text/uri-list")) {
            drop.read_value_async.begin(typeof(File), 0, null, (obj, res) => {
                try {
                    var value = drop.read_value_async.end(res);
                    if (value.type() == typeof(File)) {
                        File current_drag_file = (File)value;
                        Utils.get_file_mime_type.begin(current_drag_file, (obj, res) => {
                            string? current_drag_mime_type = Utils.get_file_mime_type.end(res);
                            dock.foreach_item((item) => {
                                if (item.can_handle_mime_type(current_drag_file, current_drag_mime_type)) {
                                    item.unset_state_flags(Gtk.StateFlags.INSENSITIVE);
                                }
                            });
                        });
                    }
                } catch (Error e) {
                    warning("Error reading drag content: %s", e.message);
                }
            });
        }
        return 0;
    }

    private bool drop_widget(Gtk.DropTarget target, Value value, double x, double y) {
        unowned Item? picked_widget = item_under_cursor(x, y);
        if (picked_widget == null || !(picked_widget is WidgetHandler)) {
            return false;
        }

        unowned WidgetHandler wh = (WidgetHandler)picked_widget;
        if (value.type() == typeof(Gtk.Widget)) {
            Gtk.Widget widget = value as Gtk.Widget;
            if (widget == null) {
                warning("Failed to cast value to Gtk.Widget");
                return false;
            }

            var item = widget.get_data<Item>("dragged-item");
            if (item is Item) {
                return wh.handle_dropped_item(item);
            }
        }
        return false;
    }

    private bool drop_file(Gtk.DropTarget target, Value value, double x, double y) {
        var hovered = item_under_cursor(x, y);
        if (value.type() == typeof(File) && hovered != null) {
            File file = (File)value;
            return hovered.handle_dropped_file(file);
        }
        return false;
    }

    private Gdk.DragAction widget_drop_motion(Gtk.DropTarget target, double x, double y) {
        Item? accepting_widget = item_under_cursor(x, y, Gtk.PickFlags.DEFAULT);
        Item? hover_item = item_under_cursor(x, y, Gtk.PickFlags.INSENSITIVE);
        Item drop_source = target.get_widget().get_data<Item>("dragged-item");

        dock.request_motion(settings.edge == GtkLayerShell.Edge.BOTTOM ? x : y);
        Gdk.DragAction retval = (accepting_widget != null && accepting_widget is WidgetHandler) ? Gdk.DragAction.COPY : 0;
        if (hover_item == null || drop_source == hover_item || accepting_widget == drop_source) {
            return retval;
        }

        var window = target.get_widget();
        Graphene.Rect hover_bounds, drop_bounds, drop_size, hover_size;
        hover_item.compute_bounds(window, out hover_bounds);
        hover_item.compute_bounds(hover_item, out hover_size);
        drop_source.compute_bounds(window, out drop_bounds);
        drop_source.compute_bounds(drop_source, out drop_size);

        dock.foreach_item((item) => {
            if (accepting_widget == item && item is WidgetHandler) {
                item.set_state_flags(Gtk.StateFlags.DROP_ACTIVE, false);
            } else {
                item.unset_state_flags(Gtk.StateFlags.DROP_ACTIVE);
            }
        });
        bool is_left_half = true;
        bool is_far_enough = false;

        if (!hover_item.movable) {
            return retval;
        }

        double hover_origin = settings.edge == GtkLayerShell.Edge.BOTTOM ? hover_bounds.origin.x : hover_bounds.origin.y;
        double drop_origin = settings.edge == GtkLayerShell.Edge.BOTTOM ? drop_bounds.origin.x : drop_bounds.origin.y;


        // Calculate the distance between the cursor and the center of the drop_source
        if (settings.edge == GtkLayerShell.Edge.BOTTOM) {
            double drop_source_reference;
            if (drop_origin < hover_origin) {
                // drop_source is to the left of hover_item
                drop_source_reference = drop_origin + drop_bounds.size.width;
            } else {
                // drop_source is to the right of hover_item
                drop_source_reference = drop_origin;
            }
            double distance_from_drop_edge = Math.fabs(x - drop_source_reference);
            is_far_enough = distance_from_drop_edge > (hover_size.size.width / 2);

            double hover_item_center_x = hover_origin + hover_size.size.width / 2;
            is_left_half = x < hover_item_center_x;
        } else {
            double drop_source_reference;
            if (drop_origin < hover_origin) {
                // drop_source is to the left of hover_item
                drop_source_reference = drop_origin + drop_size.size.height;
            } else {
                // drop_source is to the right of hover_item
                drop_source_reference = drop_origin;
            }
            double distance_from_drop_edge = Math.fabs(y - drop_source_reference);
            is_far_enough = distance_from_drop_edge > (hover_size.size.height / 2);

            double hover_item_center_y = hover_origin + hover_size.size.height / 2;
            is_left_half = y < hover_item_center_y;
        }

        if (!is_far_enough) {
            return retval;
        }

        Type hovered_type = hover_item.get_type();

        bool is_folder = drop_source.get_type() == FolderItem.TYPE;
        bool folder_drag = is_folder && hovered_type == FolderItem.TYPE;
        bool app_drag = !is_folder && hovered_type == AppItem.TYPE;

        if (!app_drag && !folder_drag) {
            return retval;
        }

        if (hover_origin < drop_origin) {
            Gtk.Widget end = drop_source.get_next_sibling();

            Gtk.Widget start = hover_item;
            if (!is_left_half) {
                start = start.get_next_sibling();
            }
            drop_source.insert_before(dock, start);

            while (start != end) {
                start.add_css_class("moved-forward");
                start.remove_css_class("moved-backward");
                start = start.get_next_sibling();
            }

        } else if (hover_origin > drop_origin) {
            Gtk.Widget start = drop_source.get_prev_sibling();

            Gtk.Widget end = hover_item;
            if (is_left_half && start != dock.background) {
                end = end.get_prev_sibling();
            }
            drop_source.insert_after(dock, end);
            while (start != end) {
                end.add_css_class("moved-backward");
                end.remove_css_class("moved-forward");
                end = end.get_prev_sibling();
            }
        }
        return retval;
    }

    private Gdk.DragAction file_drop_motion(double x, double y) {
        var hovered = item_under_cursor(x, y);
        dock.request_motion(settings.edge == GtkLayerShell.Edge.BOTTOM ? x : y);

        dock.foreach_item((item) => {
            if (item == hovered) {
                item.set_state_flags(Gtk.StateFlags.DROP_ACTIVE, false);
            } else {
                item.unset_state_flags(Gtk.StateFlags.DROP_ACTIVE);
            }
        });
        return hovered == null ? 0 : Gdk.DragAction.COPY;
    }
}
