public class DotIndicator : Gtk.Widget {
    private const float DOT_SIZE = 4.0f;
    private const float DOT_SPACING = 2.0f;
    private const int MAX_DOTS = 3;

    private int _dot_count = 0;
    public int dot_count {
        get { return _dot_count; }
        set {
            _dot_count = int.min(value, MAX_DOTS);
            queue_draw();
        }
    }

    public DotIndicator() {
        halign = Gtk.Align.CENTER;
        valign = Gtk.Align.CENTER;

        set_css_classes({"dot-indicator"});
    }
}
