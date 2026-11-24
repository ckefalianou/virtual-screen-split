import Gio from 'gi://Gio';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const BUS_NAME = 'local.VirtualMonitor.PointerPosition';
const OBJECT_PATH = '/local/VirtualMonitor/PointerPosition';
const INTERFACE_XML = `
<node>
  <interface name="local.VirtualMonitor.PointerPosition">
    <method name="Get">
      <arg type="i" direction="out" name="x"/>
      <arg type="i" direction="out" name="y"/>
    </method>
  </interface>
</node>`;

/**
 * Wayland apps cannot read the global pointer position, so the shell shares it on the session bus.
 */
export default class PointerPositionExtension extends Extension {
    enable() {
        this._exportedObject = Gio.DBusExportedObject.wrapJSObject(INTERFACE_XML, this);
        this._exportedObject.export(Gio.DBus.session, OBJECT_PATH);
        this._busNameId = Gio.bus_own_name(Gio.BusType.SESSION, BUS_NAME, Gio.BusNameOwnerFlags.NONE, null, null, null);
    }

    disable() {
        Gio.bus_unown_name(this._busNameId);
        this._exportedObject.unexport();
        this._exportedObject = null;
    }

    Get() {
        const [x, y] = global.get_pointer();
        return [x, y];
    }
}
