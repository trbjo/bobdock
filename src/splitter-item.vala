public class Splitter : DockItem {
    public signal int folder_dropped(FolderItem folder);

    public Splitter() {
        Object(label: "", icon_name: "user-bookmarks");
        css_classes = {"splitter"};
        this.visible = false;
    }

    public override bool handle_click() { return true; }

    protected override bool can_handle_mime_type(File file, string mime_type) {
        return mime_type == "inode/directory";
    }

    public override bool handle_dropped_file(File file) {
        if (file.query_file_type(FileQueryInfoFlags.NONE) == FileType.DIRECTORY) {
            var folder_name = file.get_basename();
            var folder_path = file.get_path();
            folder_dropped(new FolderItem(folder_name, folder_path));
            return true;
        }
        return false;
    }
}
