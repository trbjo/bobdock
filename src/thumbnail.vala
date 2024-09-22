public class Thumbnails {
    private static Thumbnails? instance = null;
    public static int size { get; private set; }
    private static Gdk.Paintable checkerboard;

    private Thumbnails(string file_attribute) {
        size = get_size_for_attribute(file_attribute);
        checkerboard = create_checkerboard(size);
    }

    public static Thumbnails get_instance(string file_attribute) {
        if (instance == null) {
            instance = new Thumbnails(file_attribute);
        }
        return instance;
    }

    private static int get_size_for_attribute(string attribute) {
        switch (attribute) {
            case FileAttribute.THUMBNAIL_PATH_XXLARGE:
                return 1024;
            case FileAttribute.THUMBNAIL_PATH_XLARGE:
                return 512;
            case FileAttribute.THUMBNAIL_PATH_LARGE:
                return 256;
            case FileAttribute.THUMBNAIL_PATH_NORMAL:
            default:
                return 128;
        }
    }

    public ThumbnailContainer create_thumbnail(Gdk.Paintable paintable, File file, bool is_thumbnail, int scale_factor) {
        return new ThumbnailContainer(paintable, file, is_thumbnail, scale_factor);
    }

    public class ThumbnailContainer : Gtk.Widget, MouseAble {
        public ThumbnailWidget thumbnail;
        private static int size_at_scale;
        public File file;
        private bool is_dir;

        public bool handle_click() {
            try {
                GLib.AppInfo.launch_default_for_uri(file.get_uri(), null);
                return true;
            } catch (Error e) {
                warning("Failed to launch URI: %s", e.message);
                return false;
            }
        }

        protected bool can_handle_mime_type(File file, string mime_type) {
            return this.is_dir;
        }

        public bool handle_dropped_file(File foreign_file) {
            if (!is_dir) {
                return false;
            }
            try {
                var dest_file = file.get_child(foreign_file.get_basename());
                file.move(dest_file, FileCopyFlags.NONE);
                queue_draw();
                return true;
            } catch (Error e) {
                warning("Failed to move file %s to folder %s: %s", file.get_path(), file.get_path(), e.message);
            }
            return false;
        }

        public bool handle_dropped_item(DockItem item, uint current_drop_target_id) {
            return false;
        }

        public ThumbnailContainer(Gdk.Paintable paintable, File file, bool is_thumbnail, int scale_factor) {
            size_at_scale = size / scale_factor;
            thumbnail = new ThumbnailWidget(paintable, is_thumbnail);
            thumbnail.set_parent(this);
            this.is_dir = (GLib.FileUtils.test(file.get_path(), GLib.FileTest.IS_DIR));
            this.file = file;
        }

        public override void dispose() {
            thumbnail.unparent();
            base.dispose();
        }

        public override void measure(Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
            minimum = natural = size_at_scale;
            minimum_baseline = natural_baseline = -1;
        }

        public override void size_allocate(int width, int height, int baseline) {
            int child_width, child_height;
            thumbnail.measure(Gtk.Orientation.HORIZONTAL, -1, null, out child_width, null, null);
            thumbnail.measure(Gtk.Orientation.VERTICAL, -1, null, out child_height, null, null);
            var transform = new Gsk.Transform();
            double x = 0.0;
            double y = 0.0;
            double _child_width = (double)child_width;
            double _child_height = (double)child_height;
            if (child_width > child_height) {
                y = (_child_width - _child_width / thumbnail.aspect_ratio) / 2.0f;
            } else if (child_width < child_height) {
                x = (_child_height - _child_height * thumbnail.aspect_ratio) / 2.0f;
            }

            float factor_h = ((float)width) / ((float)child_width);
            float factor_v = ((float)height) / ((float)child_height);
            float factor = float.min(factor_h, factor_v) ;

            // center the icon in relationship to itself.
            transform = transform.scale(factor, factor);
            transform = transform.translate(Graphene.Point() { x = (float)x, y = (float)y });
            thumbnail.allocate(child_width, child_height, baseline, transform);
        }

        public class ThumbnailWidget : Gtk.Widget {
            public Gdk.Paintable paintable;
            private int width = -1;
            private int height = -1;
            private bool is_thumbnail;
            public double aspect_ratio;

            public ThumbnailWidget(Gdk.Paintable paintable, bool thumbnail) {
                Object(overflow: Gtk.Overflow.HIDDEN);
                this.paintable = paintable;
                this.is_thumbnail = thumbnail;

                int intrinsic_width = paintable.get_intrinsic_width();
                int intrinsic_height = paintable.get_intrinsic_height();

                aspect_ratio = paintable.get_intrinsic_aspect_ratio();

                if (intrinsic_width > size_at_scale || intrinsic_height > size_at_scale) {
                    if (intrinsic_width > intrinsic_height) {
                        this.width = size_at_scale;
                        this.height = (int)(size_at_scale / aspect_ratio);
                    } else {
                        this.height = size_at_scale;
                        this.width = (int)(size_at_scale * aspect_ratio);
                    }
                } else {
                    this.width = intrinsic_width;
                    this.height = intrinsic_height;
                }

                if (thumbnail) {
                    add_css_class("thumbnail-widget");
                }
            }


            public override void measure(Gtk.Orientation orientation, int for_size, out int minimum, out int natural, out int minimum_baseline, out int natural_baseline) {
                minimum = natural = orientation == Gtk.Orientation.HORIZONTAL ? width : height;
                minimum_baseline = natural_baseline = -1;
            }

            public override void snapshot(Gtk.Snapshot snapshot) {
                snapshot.save();
                if (is_thumbnail) {
                    checkerboard.snapshot(snapshot, width, height);
                }
                paintable.snapshot(snapshot, width, height);
                snapshot.restore();
            }
        }
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
