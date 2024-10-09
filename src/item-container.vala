public abstract class Item : Gtk.Widget, IDockClick {
    public virtual bool handle_click(int n_press) { return true; }
    public virtual bool is_drag_source() { return true; }
    public virtual bool can_handle_mime_type(File file, string mime_type) { return false; }
    public virtual bool handle_dropped_file(File file) { return false; }
    protected Gtk.GestureClick click_gesture;

    public new void set_state_flags(Gtk.StateFlags flags, bool clear) {
        icon.set_state_flags(flags, clear);
    }

    public new void unset_state_flags(Gtk.StateFlags flags) {
        icon.unset_state_flags(flags);
    }

    private static unowned AppSettings settings;

    static construct {
        settings = AppSettings.get_default();
        set_css_name("item");
    }

    public virtual string label { get; construct set; default = "Not set"; }
    public uint hash { get; construct; }

    public new void queue_resize () {
        icon.queue_resize();
        base.queue_resize();
    }

    public virtual bool movable
    {
        get {
            return false;
        }
    }

    public int icon_size {
        get { return icon.icon_size; }
        set {
            if (value != icon.icon_size) {
                icon.icon_size = value;
                queue_resize();
            }
        }
    }

    public Icon icon { get; construct; }
    private int _count = 0;

    protected void change_badge_count(int count) {
        icon.badge.visible = count > 0;
        if (_count != count) {
            _count = count;
            icon.badge.label = "%i".printf(count);
            icon.badge.queue_draw();
        }
    }

    construct {
        icon.state_flags_changed.connect(this.on_state_flags_changed);
        icon.set_parent(this);
        click_gesture = new Gtk.GestureClick();

        click_gesture.set_button(0);
        click_gesture.released.connect_after(on_click_released);
        add_controller(click_gesture);

    }

    private void on_click_released(int n_press, double x, double y) {
        PopupManager.get_default().handle_click_for(this);
        handle_click(n_press);
    }

    private void on_state_flags_changed(Gtk.StateFlags old_flags) {
        var new_flags = icon.get_state_flags();
        // old_flags &= ~Gtk.StateFlags.DIR_LTR;
        // new_flags &= ~Gtk.StateFlags.DIR_LTR;
        // message("new_flags: %s, old_flags: %s", new_flags.to_string(), old_flags.to_string());

        bool is_insensitive = (new_flags & Gtk.StateFlags.INSENSITIVE) != 0;

        if (is_insensitive) {
            return;
        }

        bool was_prelight = (old_flags & Gtk.StateFlags.PRELIGHT) != 0;
        bool is_prelight = (new_flags & Gtk.StateFlags.PRELIGHT) != 0;
        bool is_drop_target = (new_flags & Gtk.StateFlags.DROP_ACTIVE) != 0;
        bool was_drop_target = (old_flags & Gtk.StateFlags.DROP_ACTIVE) != 0;

        if (!was_drop_target && is_drop_target) {
            PopupManager.get_default().hover_enter_for(this);
        } else if (was_drop_target && !is_drop_target) {
            PopupManager.get_default().hover_leave_for(this);
        } else if (!was_prelight && is_prelight) {
            PopupManager.get_default().hover_enter_for(this);
        } else if (was_prelight && !is_prelight) {
            PopupManager.get_default().hover_leave_for(this);
        }
    }

    protected override void measure(Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
        icon.measure(orientation, for_size, out minimum, out natural, out minimum_baseline, out natural_baseline);
    }

    public override void size_allocate(int width, int height, int baseline) {
        icon.allocate(width, height, baseline, null);
    }

    public override void snapshot(Gtk.Snapshot snapshot) {
        snapshot_child(icon, snapshot);
    }

    public override void dispose() {
        if (PopupManager.get_default().get_parent() == this) {
            PopupManager.get_default().unparent();
        }
        unowned Gtk.Widget? child = get_first_child();
        while (child != null) {
            child.unparent();
            child = get_first_child();
        }
        base.dispose();
    }
}
