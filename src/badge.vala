public class BadgeWidget : Gtk.Widget {
    private int _value = 0;
    public int value {
        get { return _value; }
        set {
            if (_value != value) {
                _value = value;
                visible = (_value > 0);
                queue_draw();
            }
        }
    }

    construct {
        visible = false;
        can_target = false;
        css_classes = {"badge"};
    }

    public override void snapshot(Gtk.Snapshot snapshot) {
        base.snapshot(snapshot);

        var layout = create_pango_layout(_value.to_string());
        layout.set_alignment(Pango.Alignment.CENTER);

        Pango.Rectangle ink_rect, logical_rect;
        layout.get_pixel_extents(out ink_rect, out logical_rect);

        float text_x = (get_width() - logical_rect.width) / 2;
        float text_y = (get_height() - logical_rect.height) / 2;

        snapshot.translate({ text_x, text_y });
        snapshot.append_layout(layout, get_color());
    }
}
