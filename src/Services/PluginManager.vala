// -*- Mode: vala; indent-tabs-mode: nil; tab-width: 4 -*-
/***
  BEGIN LICENSE

  Copyright (C) 2013 Mario Guerriero <mario@elementaryos.org>
  This program is free software: you can redistribute it and/or modify it
  under the terms of the GNU Lesser General Public License version 3, as published
  by the Free Software Foundation.

  This program is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranties of
  MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
  PURPOSE.  See the GNU General Public License for more details.

  You should have received a copy of the GNU General Public License along
  with this program.  If not, see <http://www.gnu.org/licenses/>

  END LICENSE
***/

namespace Scratch.Services {
    public class Interface : GLib.Object {

        public PluginsManager manager;

        // Signals
        public signal void hook_window (Scratch.MainWindow window);
        public signal void hook_share_menu (Gtk.Menu menu);
        public signal void hook_toolbar (Scratch.Widgets.HeaderBar toolbar);
        public signal void hook_notebook_sidebar (Gtk.Notebook notebook);
        public signal void hook_notebook_bottom (Gtk.Notebook notebook);
        public signal void hook_document (Scratch.Services.Document doc);
        public signal void hook_preferences_dialog (Scratch.Dialogs.Preferences dialog);

        public Scratch.TemplateManager template_manager { private set; get; }

        public Interface (PluginsManager manager) {
            this.manager = manager;

            template_manager = new Scratch.TemplateManager ();
        }

        public Document open_file (File file) {
            var doc = new Document (manager.window.actions, file);
            manager.window.open_document (doc);
            return doc;
        }

        public void close_document (Document doc) {
            manager.window.close_document.begin (doc);
        }
    }


    public class PluginsManager : GLib.Object {
        Peas.Engine engine;
        Peas.ExtensionSet exts;
        Peas.Engine engine_core;
        Peas.ExtensionSet exts_core;

        string settings_field;

        public Interface plugin_iface { private set; public get; }

        public weak MainWindow window;

        // Signals
        public signal void hook_window (Scratch.MainWindow window);
        public signal void hook_share_menu (Gtk.Menu menu);
        public signal void hook_toolbar (Scratch.Widgets.HeaderBar toolbar);
        public signal void hook_notebook_bottom (Gtk.Notebook notebook);
        public signal void hook_document (Scratch.Services.Document doc);
        public signal void hook_preferences_dialog (Scratch.Dialogs.Preferences dialog);

        public signal void extension_added (Peas.PluginInfo info);
        public signal void extension_removed (Peas.PluginInfo info);

        public PluginsManager (MainWindow window, string? set_name = null) {
            this.window = window;

            settings_field = "plugins-enabled";

            plugin_iface = new Interface (this);

            /* Let's init the engine */
            engine = Peas.Engine.get_default ();
            engine.enable_loader ("python");
            engine.add_search_path (Constants.PLUGINDIR, null);
            Scratch.settings.bind ("plugins-enabled", engine, "loaded-plugins", SettingsBindFlags.DEFAULT);

            /* Our extension set */
            exts = new Peas.ExtensionSet (engine, typeof (Peas.Activatable), "object", plugin_iface, null);

            exts.extension_added.connect ((info, ext) => {
                ((Peas.Activatable)ext).activate ();
                extension_added (info);
            });
            exts.extension_removed.connect ((info, ext) => {
                ((Peas.Activatable)ext).deactivate ();
                extension_removed (info);
            });
            exts.foreach (on_extension_foreach);

            if (set_name != null) {
                /* The core now */
                engine_core = new Peas.Engine ();
                engine_core.enable_loader ("python");
                engine_core.add_search_path (Constants.PLUGINDIR + "/" + set_name + "/", null);

                var core_list = engine_core.get_plugin_list ().copy ();
                string[] core_plugins = new string[core_list.length ()];
                for (int i = 0; i < core_list.length (); i++) {
                    core_plugins[i] = core_list.nth_data (i).get_module_name ();

                }
                engine_core.loaded_plugins = core_plugins;

                /* Our extension set */
                exts_core = new Peas.ExtensionSet (engine_core, typeof (Peas.Activatable), "object", plugin_iface, null);

                exts_core.foreach (on_extension_foreach);
            }

            // Connect managers signals to interface's signals
            this.hook_window.connect ((w) => {
                plugin_iface.hook_window (w);
            });

            this.hook_share_menu.connect ((m) => {
                plugin_iface.hook_share_menu (m);
            });
            this.hook_toolbar.connect ((t) => {
                plugin_iface.hook_toolbar (t);
            });
            this.hook_notebook_bottom.connect ((n) => {
                plugin_iface.hook_notebook_bottom (n);
            });
            this.hook_document.connect ((d) => {
                plugin_iface.hook_document (d);
            });
            this.hook_preferences_dialog.connect ((d) => {
                plugin_iface.hook_preferences_dialog (d);
            });
        }

        void on_extension_foreach (Peas.ExtensionSet set, Peas.PluginInfo info, Peas.Extension extension) {
            ((Peas.Activatable)extension).activate ();
        }

        public Gtk.Widget get_view () {
            var view = new PeasGtk.PluginManager (engine);
            var bottom_box = view.get_children ().nth_data (1);
            bottom_box.no_show_all = true;
            return view;
        }

        public void deactivate_plugins () {
            exts.foreach (extension_deactivate);
            exts_core.foreach (extension_deactivate);
        }

        private void extension_deactivate (Peas.ExtensionSet set, Peas.PluginInfo info, Peas.Extension extension) {
            ((Peas.Activatable)extension).deactivate ();
        }

    }
}
