@Entry
@Component
struct StartupSplash {
  build() {
    Stack() {
      Image($r('app.media.freecadsplash'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Fill)
        .interpolation(ImageInterpolation.High)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
