from krita import DockWidgetFactory, DockWidgetFactoryBase, Extension, Krita

from .ui import NAILauncherBridgeDocker


class NAILauncherBridgeExtension(Extension):
    def __init__(self, parent) -> None:
        super().__init__(parent)

    def setup(self) -> None:
        return

    def createActions(self, window) -> None:
        return


app = Krita.instance()
app.addExtension(NAILauncherBridgeExtension(app))
app.addDockWidgetFactory(
    DockWidgetFactory(
        "nai_launcher_bridge",
        DockWidgetFactoryBase.DockRight,
        NAILauncherBridgeDocker,
    )
)
