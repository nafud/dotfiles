# copy_and_collapse — Sublime's own copy, then the caret moves to the
# end of each copied selection. Sublime keeps the selection after a
# copy, so Ctrl+C, Ctrl+V replaces the selected text with an identical
# copy and looks like a paste that did nothing; with the selection
# collapsed the paste inserts beside the original. Copy itself is
# untouched (clipboard, history, an empty selection copying the whole
# line), only what is selected afterwards changes. Bound to Ctrl+C in
# Default (Linux).sublime-keymap.
import sublime
import sublime_plugin


def collapsed(regions):
    """Each non-empty region as a caret at its end; carets stay put."""
    return [sublime.Region(r.end(), r.end()) if not r.empty() else r for r in regions]


class CopyAndCollapseCommand(sublime_plugin.TextCommand):
    def run(self, edit):
        self.view.run_command("copy")
        carets = collapsed(list(self.view.sel()))
        self.view.sel().clear()
        self.view.sel().add_all(carets)
