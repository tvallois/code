/*
 * Copyright (C) 2011-2012 Lucas Baudin <xapantu@gmail.com>
 *               2013      Mario Guerriero <mario@elementaryos.org>
 *
 * This file is part of Code.
 *
 * Code is free software: you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * Code is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

namespace Scratch.Widgets {
    public class SearchBar : Gtk.FlowBox {
        public weak MainWindow window { get; construct; }

        private Gtk.Button tool_arrow_up;
        private Gtk.Button tool_arrow_down;

        /**
         * Is the search cyclic? e.g., when you are at the bottom, if you press
         * "Down", it will go at the start of the file to search for the content
         * of the search entry.
         **/
        public Gtk.ToggleButton tool_cycle_search { get; construct; }
        private Gtk.ToggleButton case_sensitive_button;
        private Gtk.ToggleButton tool_regex_button;

        public Gtk.SearchEntry search_entry;
        public Gtk.SearchEntry replace_entry;

        private Gtk.Label search_occurence_count_label;

        private Gtk.Button replace_tool_button;
        private Gtk.Button replace_all_tool_button;

        private Scratch.Widgets.SourceView? text_view = null;
        private Gtk.TextBuffer? text_buffer = null;
        private Gtk.SourceSearchContext search_context = null;

        public signal void search_empty ();

        private uint update_search_label_timeout_id = 0;

        /**
         * Create a new SearchBar widget.
         *
         * following actions : Fetch, ShowGoTo, ShowReplace, or null.
         **/
        public SearchBar (MainWindow window) {
            Object (window: window);
        }

        construct {
            get_style_context ().add_class ("search-bar");

            search_entry = new Gtk.SearchEntry ();
            search_entry.hexpand = true;
            search_entry.placeholder_text = _("Find");

            search_occurence_count_label = new Gtk.Label (_("no results")) {
                margin_start = 4
            };

            var app_instance = (Scratch.Application) GLib.Application.get_default ();

            tool_arrow_down = new Gtk.Button.from_icon_name ("go-down-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
            tool_arrow_down.clicked.connect (search_next);
            tool_arrow_down.sensitive = false;
            tool_arrow_down.tooltip_markup = Granite.markup_accel_tooltip (
                app_instance.get_accels_for_action (
                    Scratch.MainWindow.ACTION_PREFIX + Scratch.MainWindow.ACTION_FIND_NEXT
                ),
                _("Search next")
            );
            tool_arrow_down.set_margin_start (4);

            tool_arrow_up = new Gtk.Button.from_icon_name ("go-up-symbolic", Gtk.IconSize.SMALL_TOOLBAR);
            tool_arrow_up.clicked.connect (search_previous);
            tool_arrow_up.sensitive = false;
            tool_arrow_up.tooltip_markup = Granite.markup_accel_tooltip (
                app_instance.get_accels_for_action (
                    Scratch.MainWindow.ACTION_PREFIX + Scratch.MainWindow.ACTION_FIND_PREVIOUS
                ),
                _("Search previous")
            );

            tool_cycle_search = new Gtk.ToggleButton () {
                image = new Gtk.Image.from_icon_name ("media-playlist-repeat-symbolic", Gtk.IconSize.SMALL_TOOLBAR),
                tooltip_text = _("Cyclic Search")
            };
            tool_cycle_search.clicked.connect (on_search_entry_text_changed);

            case_sensitive_button = new Gtk.ToggleButton () {
                image = new Gtk.Image.from_icon_name ("font-select-symbolic", Gtk.IconSize.SMALL_TOOLBAR)
            };
            case_sensitive_button.bind_property (
                "active",
                case_sensitive_button, "tooltip-text",
                BindingFlags.DEFAULT | BindingFlags.SYNC_CREATE, // Need to SYNC_CREATE so tooltip present before toggled
                (binding, active_val, ref tooltip_val) => {
                    ((Gtk.Widget)(binding.target)).set_tooltip_text ( //tooltip_val.set_string () does not work (?)
                        active_val.get_boolean () ? _("Case Sensitive") : _("Case Insensitive")
                    );
                }
            );
            case_sensitive_button.clicked.connect (on_search_entry_text_changed);

            tool_regex_button = new Gtk.ToggleButton () {
                image = new Gtk.Image.from_icon_name ("text-html-symbolic", Gtk.IconSize.SMALL_TOOLBAR),
                tooltip_text = _("Use regular expressions")
            };
            tool_regex_button.clicked.connect (on_search_entry_text_changed);

            var search_grid = new Gtk.Grid ();
            search_grid.margin = 3;
            search_grid.get_style_context ().add_class (Gtk.STYLE_CLASS_LINKED);
            search_grid.add (search_entry);
            search_grid.add (search_occurence_count_label);
            search_grid.add (tool_arrow_down);
            search_grid.add (tool_arrow_up);
            search_grid.add (tool_cycle_search);
            search_grid.add (case_sensitive_button);
            search_grid.add (tool_regex_button);

            var search_flow_box_child = new Gtk.FlowBoxChild ();
            search_flow_box_child.can_focus = false;
            search_flow_box_child.add (search_grid);

            replace_entry = new Gtk.SearchEntry ();
            replace_entry.hexpand = true;
            replace_entry.placeholder_text = _("Replace With");
            replace_entry.set_icon_from_icon_name (Gtk.EntryIconPosition.PRIMARY, "edit-symbolic");

            replace_tool_button = new Gtk.Button.with_label (_("Replace"));
            replace_tool_button.clicked.connect (on_replace_entry_activate);

            replace_all_tool_button = new Gtk.Button.with_label (_("Replace all"));
            replace_all_tool_button.clicked.connect (on_replace_all_entry_activate);

            var replace_grid = new Gtk.Grid ();
            replace_grid.margin = 3;
            replace_grid.get_style_context ().add_class (Gtk.STYLE_CLASS_LINKED);
            replace_grid.add (replace_entry);
            replace_grid.add (replace_tool_button);
            replace_grid.add (replace_all_tool_button);

            var replace_flow_box_child = new Gtk.FlowBoxChild ();
            replace_flow_box_child.can_focus = false;
            replace_flow_box_child.add (replace_grid);

            // Connecting to some signals
            search_entry.changed.connect (on_search_entry_text_changed);
            search_entry.key_press_event.connect (on_search_entry_key_press);
            search_entry.focus_in_event.connect (on_search_entry_focused_in);
            search_entry.search_changed.connect (update_search_occurence_label);
            search_entry.icon_release.connect ((p0, p1) => {
                if (p0 == Gtk.EntryIconPosition.PRIMARY) {
                    search_next ();
                }
            });
            replace_entry.activate.connect (on_replace_entry_activate);
            replace_entry.key_press_event.connect (on_replace_entry_key_press);

            var entry_path = new Gtk.WidgetPath ();
            entry_path.append_type (typeof (Gtk.Widget));

            var entry_context = new Gtk.StyleContext ();
            entry_context.set_path (entry_path);
            entry_context.add_class ("entry");

            selection_mode = Gtk.SelectionMode.NONE;
            column_spacing = 6;
            max_children_per_line = 2;
            add (search_flow_box_child);
            add (replace_flow_box_child);

            update_replace_tool_sensitivities (false);
        }

        public void set_text_view (Scratch.Widgets.SourceView? text_view) {
            cancel_update_search_occurence_label ();
            this.text_view = text_view;

            if (text_view == null) {
                warning ("No SourceView is associated with SearchManager!");
                search_context = null;
                return;
            } else if (this.text_buffer != null) {
                this.text_buffer.changed.disconnect (on_text_buffer_changed);
            }

            this.text_buffer = text_view.get_buffer ();
            this.text_buffer.changed.connect (on_text_buffer_changed);
            this.search_context = new Gtk.SourceSearchContext (text_buffer as Gtk.SourceBuffer, null);
            search_context.settings.wrap_around = tool_cycle_search.active;
            search_context.settings.regex_enabled = tool_regex_button.active;
            search_context.settings.search_text = search_entry.text;
        }

        private void on_text_buffer_changed () {
            update_search_occurence_label ();
            update_tool_arrows ();
            bool matches = has_matches ();
            update_replace_tool_sensitivities (matches);
        }

        private void on_replace_entry_activate () {
            if (text_buffer == null) {
                warning ("No valid buffer to replace");
                return;
            }

            Gtk.TextIter? start_iter, end_iter;
            text_buffer.get_iter_at_offset (out start_iter, text_buffer.cursor_position);

            if (search_for_iter (start_iter, out end_iter)) {
                string replace_string = replace_entry.text;
                try {
                    cancel_update_search_occurence_label ();
                    search_context.replace (start_iter, end_iter, replace_string, replace_string.length);
                    bool matches = search ();
                    update_replace_tool_sensitivities (matches);
                    update_tool_arrows ();
                    update_search_occurence_label ();
                    debug ("Replaced \"%s\" with \"%s\"", search_entry.text, replace_entry.text);
                } catch (Error e) {
                    critical (e.message);
                }
            }
        }

        private void on_replace_all_entry_activate () {
            if (text_buffer == null || this.window.get_current_document () == null) {
                debug ("No valid buffer to replace");
                return;
            }

            string replace_string = replace_entry.text;
            this.window.get_current_document ().toggle_changed_handlers (false);
            try {
                cancel_update_search_occurence_label ();
                search_context.replace_all (replace_string, replace_string.length);
                update_tool_arrows ();
                update_search_occurence_label ();
                update_replace_tool_sensitivities (false);
            } catch (Error e) {
                critical (e.message);
            }

            this.window.get_current_document ().toggle_changed_handlers (true);
        }

        public void set_search_string (string to_search) {
            search_entry.text = to_search;
        }

        private void on_search_entry_text_changed () {
            if (search_context == null) { // This can happen during start up
                debug ("search entry changed with null context");
                return;
            }

            var search_string = search_entry.text;
            search_context.settings.search_text = search_string;
            bool case_sensitive = is_case_sensitive (search_string);
            search_context.settings.case_sensitive = case_sensitive;
            search_context.settings.regex_enabled = tool_regex_button.active;

            bool matches = search ();
            update_replace_tool_sensitivities (matches);
            update_search_occurence_label ();
            update_tool_arrows ();

            if (search_entry.text == "") {
                search_empty ();
            }
        }

        private void update_replace_tool_sensitivities (bool matches) {
            replace_tool_button.sensitive = matches && search_entry.text != "";
            replace_all_tool_button.sensitive = matches && search_entry.text != "";
        }

        private bool on_search_entry_focused_in (Gdk.EventFocus event) {
            if (text_buffer == null) {
                return false;
            }

            Gtk.TextIter? iter, start_iter, end_iter;
            text_buffer.get_iter_at_offset (out iter, text_buffer.cursor_position);
            end_iter = iter;

            bool found = search_context.forward (iter, out start_iter, out end_iter, null);
            if (found) {
                search_entry.get_style_context ().remove_class (Gtk.STYLE_CLASS_ERROR);
                search_entry.primary_icon_name = "edit-find-symbolic";
                return true;
            } else {
                if (search_entry.text != "") {
                    search_entry.get_style_context ().add_class (Gtk.STYLE_CLASS_ERROR);
                    search_entry.primary_icon_name = "dialog-error-symbolic";
                }

                return false;
            }
        }

        public bool search () {
            if (search_context == null) {
                return false;
            }

            search_context.highlight = false;

            if (!has_matches ()) {
                debug ("Can't search anything in a non-existent buffer and/or without anything to search.");
                search_entry.primary_icon_name = "edit-find-symbolic";
                return false;
            }

            search_context.highlight = true;

            Gtk.TextIter? start_iter, end_iter;
            text_buffer.get_iter_at_offset (out start_iter, text_buffer.cursor_position);

            if (search_for_iter (start_iter, out end_iter)) {
                search_entry.get_style_context ().remove_class (Gtk.STYLE_CLASS_ERROR);
                search_entry.primary_icon_name = "edit-find-symbolic";
            } else {
                text_buffer.get_start_iter (out start_iter);
                if (search_for_iter (start_iter, out end_iter)) {
                    search_entry.get_style_context ().remove_class (Gtk.STYLE_CLASS_ERROR);
                    search_entry.primary_icon_name = "edit-find-symbolic";
                } else {
                    debug ("Not found: \"%s\"", search_entry.text);
                    start_iter.set_offset (-1);
                    text_buffer.select_range (start_iter, start_iter);
                    search_entry.get_style_context ().add_class (Gtk.STYLE_CLASS_ERROR);
                    search_entry.primary_icon_name = "dialog-error-symbolic";
                    return false;
                }
            }

            return true;
        }

        public void highlight_none () {
            if (search_context != null) {
                search_context.highlight = false;
            }
        }

        private bool has_matches () {
            if (text_buffer == null || search_entry.text == "") {
                return false;
            }

            bool has_wrapped_around;
            Gtk.TextIter? start_iter, end_iter;
            text_buffer.get_start_iter (out start_iter);
            return search_context.forward (start_iter, out start_iter, out end_iter, out has_wrapped_around);
        }

        private bool search_for_iter (Gtk.TextIter? start_iter, out Gtk.TextIter? end_iter) {
            end_iter = start_iter;

            if (search_context == null) {
                critical ("Trying to search forwards with no search context");
                return false;
            }

            bool has_wrapped_around;
            bool found = search_context.forward (start_iter, out start_iter, out end_iter, out has_wrapped_around);
            if (found) {
                text_buffer.select_range (start_iter, end_iter);
                if (has_wrapped_around) {
                    start_iter.backward_lines (3);
                } else {
                    start_iter.forward_lines (3);
                }
                text_view.scroll_to_iter (start_iter, 0, false, 0, 0);
            }

            return found;
        }

        private bool search_for_iter_backward (Gtk.TextIter? start_iter, out Gtk.TextIter? end_iter) {
            end_iter = start_iter;

            if (search_context == null) {
                critical ("Trying to search backwards with no search context");
                return false;
            }

            bool has_wrapped_around;
            bool found = search_context.backward (start_iter, out start_iter, out end_iter, out has_wrapped_around);
            if (found) {
                text_buffer.select_range (start_iter, end_iter);
                if (has_wrapped_around) {
                    start_iter.forward_lines (3);
                } else {
                    start_iter.backward_lines (3);
                }
                text_view.scroll_to_iter (start_iter, 0, false, 0, 0);
            }
            return found;
        }

        public void search_previous () {
            /* Get selection range */
            Gtk.TextIter? start_iter, end_iter;
            if (text_buffer != null) {
                text_buffer.get_selection_bounds (out start_iter, out end_iter);
                if (!search_for_iter_backward (start_iter, out end_iter) && tool_cycle_search.active) {
                    text_buffer.get_end_iter (out start_iter);
                    search_for_iter_backward (start_iter, out end_iter);
                }

                update_tool_arrows ();
                update_search_occurence_label ();
            }
        }

        public void search_next () {
            /* Get selection range */
            Gtk.TextIter? start_iter, end_iter, end_iter_tmp;
            if (text_buffer != null) {
                text_buffer.get_selection_bounds (out start_iter, out end_iter);
                if (!search_for_iter (end_iter, out end_iter_tmp) && tool_cycle_search.active) {
                    text_buffer.get_start_iter (out start_iter);
                    search_for_iter (start_iter, out end_iter);
                }

                update_tool_arrows ();
                update_search_occurence_label ();
            }
        }

        private void update_tool_arrows () {
            /* We don't need to compute the sensitive states of these widgets
             * if they don't exist. */
             if (tool_arrow_up != null && tool_arrow_down != null) {
                if (search_entry.text == "") {
                    tool_arrow_up.sensitive = false;
                    tool_arrow_down.sensitive = false;
                } else if (text_buffer != null) {
                    if (tool_cycle_search.active) {
                        tool_arrow_down.sensitive = true;
                        tool_arrow_up.sensitive = true;
                        return;
                    }

                    Gtk.TextIter? start_iter, end_iter;
                    Gtk.TextIter? tmp_start_iter, tmp_end_iter;

                    bool is_in_start, is_in_end;

                    text_buffer.get_start_iter (out tmp_start_iter);
                    text_buffer.get_end_iter (out tmp_end_iter);

                    text_buffer.get_selection_bounds (out start_iter, out end_iter);

                    is_in_start = start_iter.compare (tmp_start_iter) == 0;
                    is_in_end = end_iter.compare (tmp_end_iter) == 0;

                    if (!is_in_end) {
                        tool_arrow_down.sensitive = search_context.forward (
                            end_iter, out tmp_start_iter, out tmp_end_iter, null
                        );
                    } else {
                        tool_arrow_down.sensitive = false;
                    }

                    if (!is_in_start) {
                        tool_arrow_up.sensitive = search_context.backward (
                            start_iter, out tmp_start_iter, out end_iter, null
                        );
                    } else {
                        tool_arrow_up.sensitive = false;
                    }
                }
            }
        }

        private bool on_search_entry_key_press (Gdk.EventKey event) {
            /* We don't need to perform search if there is nothing to search... */
            if (search_entry.text == "") {
                return false;
            }

            string key = Gdk.keyval_name (event.keyval);
            if (Gdk.ModifierType.SHIFT_MASK in event.state) {
                key = "<Shift>" + key;
            }

            switch (key) {
                case "<Shift>Return":
                case "Up":
                    search_previous ();
                    return true;
                case "Return":
                case "Down":
                    search_next ();
                    return true;
                case "Escape":
                    text_view.grab_focus ();
                    return true;
                case "Tab":
                    if (search_entry.is_focus) {
                        replace_entry.grab_focus ();
                    }

                    return true;
            }

            return false;
        }

        private bool on_replace_entry_key_press (Gdk.EventKey event) {
            /* We don't need to perform search if there is nothing to search… */
            if (search_entry.text == "") {
                return false;
            }

            switch (Gdk.keyval_name (event.keyval)) {
                case "Up":
                    search_previous ();
                    return true;
                case "Down":
                    search_next ();
                    return true;
                case "Escape":
                    text_view.grab_focus ();
                    return true;
                case "Tab":
                    if (replace_entry.is_focus) {
                        search_entry.grab_focus ();
                    }

                    return true;
            }

            return false;
        }

        private bool is_case_sensitive (string search_string) {
            return case_sensitive_button.active ||
                   !((search_string.up () == search_string) || (search_string.down () == search_string));
        }

        private void cancel_update_search_occurence_label () {
            if (update_search_label_timeout_id > 0) {
                Source.remove (update_search_label_timeout_id);
                update_search_label_timeout_id = 0;
            }
        }

        private void update_search_occurence_label () {
            cancel_update_search_occurence_label ();
            update_search_label_timeout_id = Timeout.add (100, () => {
                update_search_label_timeout_id = 0;
                if (search_context == null) {
                    warning ("update occurrence with null context");
                    return Source.REMOVE;
                }

                Gtk.TextIter? iter, start_iter, end_iter;
                text_buffer.get_iter_at_offset (out iter, text_buffer.cursor_position);

                int count_of_search = search_context.get_occurrences_count ();

                int location_of_search = -1;
                bool found = search_context.forward (iter, out start_iter, out end_iter, null);
                if (count_of_search > 0 && found) {
                    location_of_search = search_context.get_occurrence_position (start_iter, end_iter);
                }

                if (count_of_search > 0 && location_of_search > 0) {
                    search_occurence_count_label.label = _("%d of %d").printf (location_of_search, count_of_search);
                } else if (count_of_search == -1 && search_occurence_count_label.label != _("no results")) {
                    //We don't want to flicker back to no results while we're still searching but we have previous results
                } else {
                    search_occurence_count_label.label = _("no results");
                }

                return Source.REMOVE;
            });

        }
    }
}
