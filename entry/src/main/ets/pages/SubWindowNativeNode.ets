import hilog from '@ohos.hilog';
import {LOG_DOMAIN, LOG_TAG} from '../common/QtAppConstants';

interface SubWindowNativeNodeCreateInfo {
  xComponentId: string
  onAppear: () => void
  onDisAppear: () => void
}

let subWindowNativeNodeLocalStorage = LocalStorage.getShared();

@Entry(subWindowNativeNodeLocalStorage)
@Component
struct SubWindowNativeNode {
  @LocalStorageLink('createInfo') private createInfo: SubWindowNativeNodeCreateInfo | undefined = undefined

  // 诊断：本页面铺满子窗口的客户区，所以这里量到的尺寸（vp）就是窗口管理器实际
  // 给出的客户区大小。QPA 创建子窗口时也会打印一行 "SubWindowCreate:"（见
  // patches/qt-6.8-ohos/20-scale-frame-margins-by-ohos-density.patch），两者相减
  // 即可得到系统真实装饰高度，用来判断 Qt 侧 frame margins 是否吻合。
  private logClientArea(newArea: Area): void {
    const info = this.createInfo
    if (info === undefined) {
      return
    }
    hilog.info(LOG_DOMAIN, LOG_TAG,
      'SubWindowNativeNode: xComponentId=%{public}s clientAreaVp=%{public}sx%{public}s',
      info.xComponentId, newArea.width.toString(), newArea.height.toString())
  }

  build() {
    Stack() {
      if (this.createInfo !== undefined) {
        XComponent({
          type: XComponentType.NODE,
          id: this.createInfo.xComponentId,
          libraryname: 'qohos'
        })
        .onAppear(this.createInfo.onAppear)
        .onDisAppear(this.createInfo.onDisAppear)
        .width('100%')
        .height('100%')
        .onAreaChange((_oldArea: Area, newArea: Area) => { this.logClientArea(newArea) })
      }
    }
    .width('100%')
    .height('100%')
  }
}
