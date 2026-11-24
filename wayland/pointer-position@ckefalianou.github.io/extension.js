import Gio from 'gi://Gio';
import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const BUS_NAME = 'io.github.ckefalianou.PointerPosition';
const OBJECT_PATH = '/io/github/ckefalianou/PointerPosition';
const INTERFACE_XML = `
<node>
  <interface name="io.github.ckefalianou.PointerPosition">
    <method name="GetVirtualPointer">
      <arg type="s" direction="out" name="connector"/>
      <arg type="i" direction="out" name="x"/>
      <arg type="i" direction="out" name="y"/>
      <arg type="i" direction="out" name="width"/>
      <arg type="i" direction="out" name="height"/>
    </method>
  </interface>
</node>`;

/**
 * Answers only while the pointer is on a virtual monitor, so the rest of the desktop stays private.
 */
class PointerService {
    GetVirtualPointer() {
        const index = global.display.get_current_monitor();
        const logicalMonitor = global.backend.get_monitor_manager()
            .get_logical_monitors()
            .find(monitor => monitor.get_number() === index);
        const virtualMonitor = logicalMonitor?.get_monitors().find(monitor => monitor.is_virtual());

        if (!virtualMonitor) {
            return ['', 0, 0, 0, 0];
        }

        const [pointerX, pointerY] = global.get_pointer();
        const area = global.display.get_monitor_geometry(index);

        return [virtualMonitor.get_connector(), pointerX - area.x, pointerY - area.y, area.width, area.height];
    }
}

/**
 * Wayland apps cannot read the pointer position, so the shell shares it on the session bus.
 */
export default class PointerPositionExtension extends Extension {
    enable() {
        this._exportedObject = Gio.DBusExportedObject.wrapJSObject(INTERFACE_XML, new PointerService());
        this._exportedObject.export(Gio.DBus.session, OBJECT_PATH);
        this._nameId = Gio.DBus.session.own_name(
            BUS_NAME,
            Gio.BusNameOwnerFlags.DO_NOT_QUEUE,
            null,
            () => console.warn(`${this.uuid}: another process owns ${BUS_NAME}, so the viewer cannot reach this extension.`)
        );
    }

    disable() {
        if (this._nameId) {
            Gio.bus_unown_name(this._nameId);
            this._nameId = 0;
        }

        if (this._exportedObject) {
            this._exportedObject.unexport();
            this._exportedObject = null;
        }
    }
}
