public static string get_css_for_edge(int _margin, GtkLayerShell.Edge edge) {
    string margin = "-%ipx".printf(_margin);
    switch (edge) {
        case GtkLayerShell.Edge.LEFT:
            return @"window.left.hidden #dock { margin-left: $margin; }";
        case GtkLayerShell.Edge.RIGHT:
            return @"window.right.hidden #dock { margin-right: $margin; }";
        case GtkLayerShell.Edge.BOTTOM:
        default:
            return @"window.bottom.hidden #dock { margin-bottom: $margin; }";
    }
}

public static string get_css_icon_size(int _size) {
    string size = "%ipx".printf(_size);
        return @"image { -gtk-icon-size: $size; }";
}
