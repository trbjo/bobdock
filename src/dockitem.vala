public interface WidgetHandler : GLib.Object {
    public abstract bool handle_dropped_item(DockItem file);
}

public interface MouseAble : GLib.Object {
    public abstract bool handle_click();
    protected abstract bool can_handle_mime_type(File file, string mime_type);
    public abstract bool handle_dropped_file(File file);
}

public abstract class DockItem : Gtk.Widget, MouseAble {
    private float bounce_progress = 0.0f;

    protected BadgeWidget badge;

    private int64 icon_start_time = 0;
    private float icon_animation_progress = 1.0f;
    private uint icon_animation_id = 0;
    private bool is_icon_fading_out = false;

    private const float MAX_BOUNCE_SCALE = 1.2f;

    public signal void remove_requested();

    public string user_identification { get; construct; default = "unset"; }
    public string label { get; construct set; default = "Not set"; }
    private uint _hash;
    public virtual uint hash {
        get {
            if (_hash == 0) {
                if (this is AppItem) {
                    _hash = "AppItem".hash() ^ (((AppItem)this).app_id).hash();
                } else if (this is FolderItem) {
                    _hash = "FolderItem".hash() ^ (((FolderItem)this).path).hash();
                } else if (this is WindowItem) {
                    _hash = "AppItem".hash() ^ (((WindowItem)this).app_id).hash();
                } else {
                    uint type_name_hash = this.get_type().name().hash();
                    _hash = type_name_hash ^ this.label.hash();
                }
            }
            return _hash;
        }
    }

    private string _icon_name = "icon-missing";
    protected int _icon_size;
    public virtual int icon_size {
        get { return _icon_size; }
        set {
            if (_icon_size != value) {
                _icon_size = value;
                queue_resize();
            }
        }
    }

    public virtual bool handles_widgets {
        get {
            return false;
        }
    }

    public abstract bool handle_click();
    public abstract bool can_handle_mime_type(File file, string mime_type);
    public abstract bool handle_dropped_file(File file);

    private int _badge_value = 0;
    public int badge_value {
        get { return _badge_value; }
        set {
            if (_badge_value != value) {
                _badge_value = value;
                this.queue_draw();
            }
        }
    }

    public Gtk.Image icon { get; construct; }

    public string icon_name {
        get { return _icon_name; }
        set {
            if (value != _icon_name) {
                _icon_name = value;
                var icon_theme = Gtk.IconTheme.get_for_display(get_display());
                var icon_paintable = icon_theme.lookup_icon(_icon_name, null, 256, scale_factor, Gtk.TextDirection.NONE, Gtk.IconLookupFlags.FORCE_REGULAR);
                icon.set_from_paintable(icon_paintable);
                this.queue_draw();
            }
        }
    }

    construct {
        css_classes = {"dock-item"};

        halign = Gtk.Align.CENTER;
        valign = Gtk.Align.CENTER;

        icon =  new Gtk.Image();
        icon.set_parent(this);

        badge = new BadgeWidget();
        badge.set_parent(this);
    }

    public override void dispose() {
        icon.unparent();
        badge.unparent();
        base.dispose();
    }


    public delegate void AnimationCompletedFunc();

    public void animate_icon(bool fade_in, owned AnimationCompletedFunc? completed_func = null) {
        is_icon_fading_out = !fade_in;
        icon_start_time = get_frame_clock().get_frame_time();

        if (icon_animation_id != 0) {
            remove_tick_callback(icon_animation_id);
            icon_animation_id = 0;
        }

        icon_animation_id = add_tick_callback((widget, frame_clock) => {
            int64 now = frame_clock.get_frame_time();
            double t = (double)(now - icon_start_time) / (ANIMATION_MILLISECONDS * 1000);

            if (t >= 1.0) {
                icon_animation_progress = is_icon_fading_out ? 0.0f : 1.0f;
                this.queue_draw();
                icon_animation_id = 0;
                if (completed_func != null) {
                    completed_func();
                }
                return false;
            }

            // Ease in-out function
            t = t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t;

            icon_animation_progress = is_icon_fading_out ? (float)(1.0 - t) : (float)t;
            this.queue_draw();
            return true;
        });
    }

    public override void size_allocate(int width, int height, int baseline) {
        base.size_allocate(width, height, baseline);

        int badge_width, badge_height, badge_minimum, badge_natural;
        badge.measure(Gtk.Orientation.HORIZONTAL, -1, out badge_minimum, out badge_natural, null, null);
        badge_width = badge_natural;
        badge.measure(Gtk.Orientation.VERTICAL, -1, out badge_minimum, out badge_natural, null, null);
        badge_height = badge_natural;

        var badge_transform = new Gsk.Transform().translate(Graphene.Point() { x = width - badge_width, y = 0 });
        badge.allocate(badge_width, badge_height, baseline, badge_transform);
    }


    public override void measure(Gtk.Orientation orientation,
                                 int for_size,
                                 out int minimum,
                                 out int natural,
                                 out int minimum_baseline,
                                 out int natural_baseline)
    {
        minimum_baseline = natural_baseline = -1;
        icon.measure(orientation, for_size, out minimum, null, null, null);
        natural = int.max(icon_size, minimum);
    }

    public override void snapshot(Gtk.Snapshot snapshot) {
        snapshot.save();

        float icon_scale = icon_animation_progress * (1 + bounce_progress * (MAX_BOUNCE_SCALE - 1));

        float center_x = (((float)icon_size) / 2.0f);
        float center_y = (((float)icon_size) / 2.0f);

        snapshot.translate(Graphene.Point.zero());
        snapshot.translate({center_x, center_y});
        snapshot.scale(icon_scale, icon_scale);
        snapshot.translate({ - center_x, - center_y });

        icon.paintable.snapshot(snapshot, icon_size, icon_size);
        snapshot.restore();
    }
}
