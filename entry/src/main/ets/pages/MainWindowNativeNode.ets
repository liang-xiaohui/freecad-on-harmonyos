interface WindowNativeNodeCreateInfo {
  xComponentId: string
  onAppear: () => void
  onAttach: () => void
  onDisAppear: () => void
}

let mainWindowNativeNodeLocalStorage = LocalStorage.getShared();

@Entry(mainWindowNativeNodeLocalStorage)
@Component
struct WindowNativeNode {
  @LocalStorageLink('createInfo') private createInfo: WindowNativeNodeCreateInfo | undefined = undefined
  @LocalStorageLink('freecadGuiReady') private freecadGuiReady: boolean = false

  build() {
    Stack() {
      if (this.createInfo !== undefined) {
        XComponent({
          type: XComponentType.NODE,
          id: this.createInfo.xComponentId,
          libraryname: 'qohos'
        })
  	    .onAttach(this.createInfo.onAttach)
  	    .onAppear(this.createInfo.onAppear)
	    .onDisAppear(this.createInfo.onDisAppear)
	    .width('100%')
	    .height('100%')
          // Hiding an XComponent destroys its native surface and blocks Qt's
          // startup. Keep it attached and rendering, but move its separately
          // composited surface off screen until FreeCAD publishes readiness.
          .translate({ x: this.freecadGuiReady ? 0 : -10000, y: 0 })
      }

    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.Center)
    .backgroundColor(Color.Transparent)
  }
}
