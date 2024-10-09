namespace Utils {
    private static void calculate_dimensions(int original_width, int original_height, int max_size, out int new_width, out int new_height) {
        if (original_width > original_height) {
            new_width = max_size;
            new_height = (int)((double)original_height / original_width * max_size);
        } else {
            new_height = max_size;
            new_width = (int)((double)original_width / original_height * max_size);
        }
    }

    private static async string? get_file_mime_type(File file) {
        try {
            var info = yield file.query_info_async("standard::content-type", FileQueryInfoFlags.NONE);
            return info.get_content_type();
        } catch (Error e) {
            warning("Error querying file info: %s", e.message);
            return null;
        }
    }



    private static Bytes load_file_content(File file) {
        try {
            uint8[] contents;
            string etag_out;

            if (file.load_contents(null, out contents, out etag_out)) {
                return new Bytes(contents);
            } else {
                warning("Failed to load file contents for URI: %s", file.get_uri());
                return new Bytes(new uint8[0]);
            }
        } catch (Error e) {
            warning("Error loading file contents: %s", e.message);
            return new Bytes(new uint8[0]);
        }
    }

    public static bool create_thumbnail(string file_path, int size) {
        try {
            var file = File.new_for_path(file_path);
            var file_info = file.query_info(FileAttribute.STANDARD_CONTENT_TYPE, FileQueryInfoFlags.NONE);
            var mime_type = file_info.get_content_type();

            Gdk.Pixbuf? pixbuf = null;

            if (mime_type.has_prefix("image/")) {
                pixbuf = new Gdk.Pixbuf.from_file(file_path);
            } else if (mime_type.has_prefix("video/")) {
                // TODO
            } else if (mime_type.has_prefix("application/pdf")) {
                // TODO
            } else if (mime_type == "text/plain") {
                pixbuf = create_text_thumbnail(file_path);
            } else {
            }

            if (pixbuf == null) {
                return false;
            }

            int width, height;
            calculate_dimensions(pixbuf.get_width(), pixbuf.get_height(), size, out width, out height);
            var scaled = pixbuf.scale_simple(width, height, Gdk.InterpType.BILINEAR);

            var uri = file.get_uri();
            var md5 = GLib.Checksum.compute_for_string(GLib.ChecksumType.MD5, uri);

            var cache_dir = Path.build_filename(Environment.get_user_cache_dir(), "thumbnails", "large");
            var thumb_path = Path.build_filename(cache_dir, md5 + ".png");

            DirUtils.create_with_parents(cache_dir, 0755);

            scaled.save(thumb_path, "png");

            return true;
        } catch (Error e) {
            warning("Error creating thumbnail: %s", e.message);
            return false;
        }
    }

    private static Gdk.Pixbuf? create_text_thumbnail(string file_path) {
        try {
            var surface = new Cairo.ImageSurface(Cairo.Format.ARGB32, 256, 256);
            var context = new Cairo.Context(surface);

            context.set_source_rgb(1, 1, 1);
            context.paint();

            context.set_source_rgb(0, 0, 0);
            context.select_font_face("Sans", Cairo.FontSlant.NORMAL, Cairo.FontWeight.NORMAL);
            context.set_font_size(12);

            var file = File.new_for_path(file_path);
            var dis = new DataInputStream(file.read());
            string line;
            int y = 20;
            while ((line = dis.read_line()) != null && y < 240) {
                context.move_to(10, y);
                context.show_text(line);
                y += 20;
            }

            return Gdk.pixbuf_get_from_surface(surface, 0, 0, 256, 256);
        } catch (Error e) {
            warning("Error creating text thumbnail: %s", e.message);
            return null;
        }
    }

    public static Gdk.Monitor? get_current_monitor(Gtk.Window window) {
        unowned Gdk.Surface? surface = window.get_surface();
        if (surface == null) {
            return null;
        }
        Gdk.Display? display = surface.get_display();
        if (display == null) {
            return null;
        }
        var monitor = display.get_monitor_at_surface(surface);
        if (monitor != null) {
            return monitor;
        }
        message("default monitor not found");

        unowned GLib.ListModel monitor_list = display.get_monitors();
        uint n_monitors = monitor_list.get_n_items();

        if (n_monitors == 0) {
            message("No monitors found");
            return null;
        }
        return (monitor_list.get_item(0) as Gdk.Monitor);

    }

    public static Gdk.Rectangle? get_current_display_size(Gtk.Window window) {
        unowned Gdk.Surface? surface = window.get_surface();
        if (surface == null) {
            return null;
        }
        Gdk.Display? display = surface.get_display();
        if (display == null) {
            return null;
        }

        unowned GLib.ListModel monitor_list = display.get_monitors();
        uint n_monitors = monitor_list.get_n_items();

        if (n_monitors == 0) {
            message("No monitors found");
            return null;
        }
        Gdk.Monitor? monitor = display.get_monitor_at_surface(surface)
            ?? (monitor_list.get_item(0) as Gdk.Monitor);

        if (monitor == null) {
            message("Failed to get monitor");
            return null;
        }
        return monitor.get_geometry();
    }




    private static string strip_desktop_extension(string? id) {
        if (id == null) {
            return "unknown";
        }
        return id.has_suffix(".desktop") ? id[0:-8] : id;
    }

    public static string? find_desktop_file(string app_id, string window_title) {
        string[] search_paths = {
            Path.build_filename(Environment.get_home_dir(), ".local", "share", "applications"),
            "/usr/local/share/applications",
            "/usr/share/applications",
        };

        string? best_match = null;
        int best_score = -1;



        foreach (string path in search_paths) {
            try {
                Dir dir = Dir.open(path, 0);
                string? name = null;
                while ((name = dir.read_name()) != null) {
                    if (!name.has_suffix(".desktop")) {
                        continue;
                    }
                    string full_path = Path.build_filename(path, name);
                    string base_name = name.substring(0, name.length - 8);
                    // message("base_name: %s, app_id: %s", base_name, app_id);

                    int score = score_desktop_file(full_path, base_name, app_id, window_title);
                    if (score > best_score) {
                        // message("Got new best match for %s: %i, app_id: %s, window_title: %s", full_path, score, app_id, window_title);
                        best_score = score;
                        best_match = full_path;
                    }
                }
            } catch (Error e) { }
        }

        // message("returning %s with score: %i", best_match, best_score);
        return best_match;
    }

    private static int score_desktop_file(string file_path, string base_name, string app_id, string window_title) {
        int score = 0;

        if (app_id.contains(base_name)) {
            score += 4;
        }

        try {
            var key_file = new KeyFile();
            key_file.load_from_file(file_path, KeyFileFlags.NONE);

            string? exec = key_file.get_string("Desktop Entry", "Exec");
            string? icon = key_file.get_string("Desktop Entry", "Icon");
            string? name = key_file.get_string("Desktop Entry", "Name");

            if (exec != null && exec.down().contains(app_id.down())) {
                score += 2;
            }
            if (icon != null && icon.down().contains(app_id.down())) {
                score += 1;
            }
            if (name != null) {
                if (name.down().contains(app_id.down())) {
                    score += 0;
                }
                if (window_title != "" && name.down().contains(window_title.down())) {
                    score += 0;
                }
            }
        } catch (Error e) {
            // ignore missing icon warning
            // warning("Error reading desktop file %s: %s", file_path, e.message);
        }

        return score > 0 ? score : -1;
    }

    public static bool array_contains(string[] lst, string needle) {
        for (int i = 0; i < lst.length; i++) {
            if (needle == lst[i]) {
                return true;
            }
        }
        return false;
    }

    public static string gtk_ls_to_string(GtkLayerShell.Edge edge) {
        switch (edge) {
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


    public static Gtk.Orientation edge_to_orientation(GtkLayerShell.Edge edge) {
        switch (edge) {
            case GtkLayerShell.Edge.TOP:
            case GtkLayerShell.Edge.BOTTOM:
                return Gtk.Orientation.HORIZONTAL;
            case GtkLayerShell.Edge.LEFT:
            case GtkLayerShell.Edge.RIGHT:
            default:
                return Gtk.Orientation.VERTICAL;
        }
    }

    public static Gtk.PositionType orientation_to_position(GtkLayerShell.Edge edge) {
        switch (edge) {
            case GtkLayerShell.Edge.BOTTOM:
                return Gtk.PositionType.TOP;
            case GtkLayerShell.Edge.LEFT:
                return Gtk.PositionType.RIGHT;
            case GtkLayerShell.Edge.RIGHT:
                return Gtk.PositionType.LEFT;
            default:
                return Gtk.PositionType.TOP;
        }
    }
}
