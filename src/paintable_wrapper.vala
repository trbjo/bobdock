public class PaintableWidgetWrapper : Gtk.Widget {
    private double aspect_ratio;
    private double scaled_width;
    private double scaled_height;

    public File file { get; construct; }
    public Gdk.Paintable paintable { get; construct; }

    static construct {
        checkerboard = create_checkerboard(512);
    }

    construct {
        overflow = Gtk.Overflow.HIDDEN;

        valign = Gtk.Align.FILL;
        halign = Gtk.Align.FILL;

        add_css_class("thumbnail-widget");
        aspect_ratio = paintable.get_intrinsic_aspect_ratio();
        scaled_width = paintable.get_intrinsic_width() / ((double)scale_factor);
        scaled_height = paintable.get_intrinsic_height() / ((double)scale_factor);
        update_alpha_status();
    }

    public bool handle_click() {
        return true;
    }


    public override void measure(Gtk.Orientation orientation,
                                 int for_size,
                                 out int minimum,
                                 out int natural,
                                 out int minimum_baseline,
                                 out int natural_baseline)
    {
        natural = minimum = minimum_baseline = natural_baseline = -1;
        if (for_size > 0 && orientation == Gtk.Orientation.HORIZONTAL) {
            if (aspect_ratio < 1.0) {
                double downscaled_width = Math.round(for_size * aspect_ratio);
                minimum = natural = (int)downscaled_width;
            } else if (aspect_ratio > 1.0) {
                minimum = natural = for_size;
            } else {
                minimum = natural = for_size;
            }
        } else if (for_size > 0 && orientation == Gtk.Orientation.VERTICAL) {
            if (aspect_ratio < 1.0) {
                minimum = natural = for_size;
            } else if (aspect_ratio > 1.0) {
                double downscaled_height = Math.round(for_size / aspect_ratio);
                minimum = natural = (int)downscaled_height;
            } else {
                minimum = natural = for_size;
            }
        } else {

        }
        message("aa, scaled_height: %f, for_size: %i", scaled_height, for_size);
    }

    public override Gtk.SizeRequestMode get_request_mode() {
        return Gtk.SizeRequestMode.WIDTH_FOR_HEIGHT;
    }

    private static Gdk.Paintable checkerboard;
    private bool paintable_has_alpha;


    private void update_alpha_status() {
        var current_image = paintable.get_current_image();
        if (current_image is Gdk.Texture) {
            paintable_has_alpha = texture_has_alpha((Gdk.Texture)current_image);
        } else {
            // If it's not a texture, we can't be certain. Assume it might have alpha.
            paintable_has_alpha = true;
        }
    }


    private bool texture_has_alpha(Gdk.Texture texture) {
        Gdk.MemoryFormat format = texture.get_format();
        switch (format) {
            case Gdk.MemoryFormat.B8G8R8A8_PREMULTIPLIED:
            case Gdk.MemoryFormat.A8R8G8B8_PREMULTIPLIED:
            case Gdk.MemoryFormat.R8G8B8A8_PREMULTIPLIED:
            case Gdk.MemoryFormat.B8G8R8A8:
            case Gdk.MemoryFormat.A8R8G8B8:
            case Gdk.MemoryFormat.R8G8B8A8:
            case Gdk.MemoryFormat.A8B8G8R8:
            case Gdk.MemoryFormat.R16G16B16A16_PREMULTIPLIED:
            case Gdk.MemoryFormat.R16G16B16A16:
            case Gdk.MemoryFormat.R16G16B16A16_FLOAT_PREMULTIPLIED:
            case Gdk.MemoryFormat.R16G16B16A16_FLOAT:
            case Gdk.MemoryFormat.R32G32B32A32_FLOAT_PREMULTIPLIED:
            case Gdk.MemoryFormat.R32G32B32A32_FLOAT:
            case Gdk.MemoryFormat.G8A8_PREMULTIPLIED:
            case Gdk.MemoryFormat.G8A8:
            case Gdk.MemoryFormat.G16A16_PREMULTIPLIED:
            case Gdk.MemoryFormat.G16A16:
            case Gdk.MemoryFormat.A8:
            case Gdk.MemoryFormat.A16:
            case Gdk.MemoryFormat.A16_FLOAT:
            case Gdk.MemoryFormat.A32_FLOAT:
            case Gdk.MemoryFormat.A8B8G8R8_PREMULTIPLIED:
                return true;
            default:
                return false;
        }
    }


    public override void snapshot(Gtk.Snapshot snapshot) {
        snapshot.save();

        if (paintable_has_alpha) {
            checkerboard.snapshot(snapshot, get_width(), get_height());
        }
        message("snapshot: %i, %i", get_width(), get_height());

        paintable.snapshot(snapshot, get_width(), get_height());
        snapshot.restore();
    }

    private static Gdk.Paintable create_checkerboard(int size_at_scale) {
        Graphene.Size dimensions = Graphene.Size() {
           width = size_at_scale,
           height = size_at_scale
        };
        var snapshot = new Gtk.Snapshot();
        var rect = Graphene.Rect().init(0, 0, size_at_scale, size_at_scale);

        snapshot.append_color(Gdk.RGBA() { red = 0.9f, green = 0.9f, blue = 0.9f, alpha = 0.7f }, rect);

        int tile_size = size_at_scale / 16;
        for (int y = 0; y < size_at_scale; y += tile_size * 2) {
            for (int x = 0; x < size_at_scale; x += tile_size * 2) {
                snapshot.push_clip(Graphene.Rect().init(x, y, tile_size, tile_size));
                snapshot.append_color(Gdk.RGBA() { red = 0.8f, green = 0.8f, blue = 0.8f, alpha = 0.7f }, rect);
                snapshot.pop();

                snapshot.push_clip(Graphene.Rect().init(x + tile_size, y + tile_size, tile_size, tile_size));
                snapshot.append_color(Gdk.RGBA() { red = 0.8f, green = 0.8f, blue = 0.8f, alpha = 0.7f }, rect);
                snapshot.pop();
            }
        }
        return snapshot.to_paintable(dimensions);
    }
}
