public class Icon : Gtk.Widget {
    private static unowned AppSettings settings;

    static construct {
        set_css_name("icon");
        settings = AppSettings.get_default();
    }

    private Gdk.Paintable paintable;
    private int min_x;
    private int min_y;
    private int max_x;
    private int max_y;

    private int top_left;
    private int top_right;
    private int bottom_left;
    private int bottom_right;

    private const uint8 ALPHA_THRESHOLD_BADGE = 0;
    private const uint8 ALPHA_THRESHOLD_BB = 254;

    public int icon_size;

    public static Gdk.Paintable retrieve_paintable(Gtk.Widget widget, string name, int size) {
        var icon_theme = Gtk.IconTheme.get_for_display(widget.get_display());
        return icon_theme.lookup_icon(
            name,
            null,
            size,
            widget.scale_factor,
            Gtk.TextDirection.NONE,
            Gtk.IconLookupFlags.FORCE_REGULAR
        );
    }

    private string _icon_name = "icon-missing";
    public string icon_name {
        get { return _icon_name; }
        construct set {
            _icon_name = value;
            var examined = retrieve_paintable(this, _icon_name, settings.max_icon_size);
            calculate_bounding_box(examined);
            calculate_content_bounds(examined);
            paintable = retrieve_paintable(this, _icon_name, settings.max_icon_size * 2); // add extra quality
            this.queue_draw();
        }
    }

    public static Icon.from_icon_name(string icon_name) {
        Object(icon_name: icon_name);
    }

    public Gtk.Label badge;

    construct {
        settings.sizes_changed.connect((old_min, old_max) => {
            if (old_max != settings.max_icon_size) {
                // force trigger re-loading of icon size
                Idle.add(() => {
                    icon_name = icon_name;
                    return false;
                }, GLib.Priority.LOW);
            }
        });

        badge = new Gtk.Label("0") {
            can_target = false,
            can_focus = false,
            css_classes = {"badge"},
            visible = false,
        };
        badge.set_parent(this);
    }

    public static Gdk.Texture paintable_to_texture(Gdk.Paintable p) {
        int width = p.get_intrinsic_width();
        int height = p.get_intrinsic_height();
        var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, width, height);
        var cr = new Cairo.Context(surface);

        var snapshot = new Gtk.Snapshot();
        p.snapshot(snapshot, width, height);
        var node = snapshot.to_node();
        if (node != null) {
            node.draw(cr);
        }

        surface.flush();
        unowned uchar[] pixel_data = surface.get_data();
        int stride = surface.get_stride();
        size_t bytes_size = (size_t)(stride * surface.get_height());

        return new Gdk.MemoryTexture(
            surface.get_width(),
            surface.get_height(),
            Gdk.MemoryFormat.B8G8R8A8,
            new GLib.Bytes.take(pixel_data[0:bytes_size]),
            stride
        );
    }

    private void calculate_content_bounds(Gdk.Paintable p) {
        int width = p.get_intrinsic_width();
        int height = p.get_intrinsic_height();
        if (width <= 0 || height <= 0) {
            error("width cannot be less than 0");
        }

        var texture = paintable_to_texture(p);
        if (texture == null) {
            message("Failed to create texture from paintable for icon: %s", icon_name);
            return;
        }

        uint8[] pixel_data = new uint8[width * height * 4];
        texture.download(pixel_data, width * 4);

        int center_x = width / 2;
        int center_y = height / 2;

        int local_top_left;
        find_corner(pixel_data, width, height, center_x, center_y, -1, -1, out local_top_left);
        top_left = local_top_left;

        int local_top_right;
        find_corner(pixel_data, width, height, center_x, center_y, 1, -1, out local_top_right);
        top_right = local_top_right;

        int local_bottom_right;
        find_corner(pixel_data, width, height, center_x, center_y, 1, 1, out local_bottom_right);
        bottom_right = local_bottom_right;

        int local_bottom_left;
        find_corner(pixel_data, width, height, center_x, center_y, -1, 1, out local_bottom_left);
        bottom_left = local_bottom_left;
    }

    private void find_corner(uint8[] pixel_data, int width, int height, int start_x, int start_y, int dir_x, int dir_y, out int result) {
        int x = start_x;
        int y = start_y;

        while (x >= 0 && x < width && y >= 0 && y < height) {
            int next_x = x + dir_x;
            int next_y = y + dir_y;

            if (next_x < 0 || next_x >= width || next_y < 0 || next_y >= height ||
                !has_non_transparent_pixel(pixel_data, next_x, next_y, width, height)) {
                result = x;
                return;
            }

            x = next_x;
            y = next_y;
        }

        // If we reach here, we didn't find a suitable corner (should not happen)
        result = start_x;
    }

    private bool has_non_transparent_pixel(uint8[] pixel_data, int x, int y, int width, int height) {
        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                int check_x = x + dx;
                int check_y = y + dy;
                if (check_x >= 0 && check_x < width && check_y >= 0 && check_y < height) {
                    int index = (check_y * width + check_x) * 4;
                    if (pixel_data[index + 3] > ALPHA_THRESHOLD_BADGE) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    public override void size_allocate(int width, int height, int baseline) {
        var badge_transform = new Gsk.Transform().translate(Graphene.Point() { x = - 0, y =  - 0 });

        int badge_width, badge_height;
        badge.measure(Gtk.Orientation.HORIZONTAL, -1, null, out badge_width, null, null);
        badge.measure(Gtk.Orientation.VERTICAL, -1, null, out badge_height, null, null);


        double upscaled = (double)(icon_size - settings.min_icon_size) /
                              (double)(settings.max_icon_size - settings.min_icon_size);

        int upscaled_point = (int) (top_left * upscaled);
        int badge_point_x = int.max(0, int.min(upscaled_point, icon_size - badge_width));
        int badge_point_y = int.max(0, int.min(upscaled_point, icon_size - badge_height));

        badge_transform = badge_transform.translate(Graphene.Point() { x = badge_point_x, y = badge_point_y });

        double translate_x = -min_x * upscaled;
        double translate_y = -min_y * upscaled;

        int width_diff = (max_x - min_x) - (max_y - min_y);

        if (width_diff > 0) {
            translate_y += (width_diff * upscaled) / 2;
        } else if (width_diff < 0) {
            translate_x += (-width_diff * upscaled) / 2;
        }

        badge_transform = badge_transform.translate({ (float)translate_x, (float)translate_y });
        badge.allocate(badge_width, badge_height, baseline, badge_transform);
    }

    public override void snapshot(Gtk.Snapshot snapshot) {
        double scale_factor = (double)get_width() / (double)settings.max_icon_size;

        double translate_x = -min_x * scale_factor;
        double translate_y = -min_y * scale_factor;

        int width_diff = (max_x - min_x) - (max_y - min_y);

        // Add extra translation for centering in the shortest dimension
        if (width_diff > 0) {
            translate_y += (width_diff * scale_factor) / 2;
        } else if (width_diff < 0) {
            translate_x += (-width_diff * scale_factor) / 2;
        }

        int extra_x = (int)((settings.max_icon_size - max_x + min_x) * scale_factor);
        int extra_y = (int)((settings.max_icon_size - max_y + min_y) * scale_factor);
        int extra = int.min(extra_x, extra_y);

        snapshot.save();
        snapshot.translate({ (float)translate_x, (float)translate_y });
        paintable.snapshot(snapshot, icon_size + extra, icon_size + extra);
        snapshot.restore();
        snapshot_child(badge, snapshot);
    }


    public override void dispose() {
        unowned Gtk.Widget? child = get_first_child();
        while (child != null) {
            child.unparent();
            child = get_first_child();
        }
        base.dispose();
    }


    private void calculate_bounding_box(Gdk.Paintable p) {
        var texture = paintable_to_texture(p);

        int width = texture.get_width();
        int height = texture.get_height();

        uint8[] pixel_data = new uint8[width * height * 4];
        texture.download(pixel_data, width * 4);

        min_x = width;
        min_y = height;
        max_x = 0;
        max_y = 0;

        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                int index = (y * width + x) * 4;
                uint8 alpha = pixel_data[index + 3];
                if (alpha > ALPHA_THRESHOLD_BB) {
                    min_x = int.min(min_x, x);
                    min_y = int.min(min_y, y);
                    max_x = int.max(max_x, x);
                    max_y = int.max(max_y, y);
                }
            }
        }
    }
}
