@Entry
@Component
struct StartupSplash {
  @StorageProp('freecadSplashIndex') private splashIndex: number = 0;

  private getSplashImage(): Resource {
    switch (this.splashIndex) {
      case 1:
        return $r('app.media.freecadsplash1');
      case 2:
        return $r('app.media.freecadsplash2');
      case 3:
        return $r('app.media.freecadsplash3');
      case 4:
        return $r('app.media.freecadsplash4');
      case 5:
        return $r('app.media.freecadsplash5');
      case 6:
        return $r('app.media.freecadsplash6');
      case 7:
        return $r('app.media.freecadsplash7');
      case 8:
        return $r('app.media.freecadsplash8');
      case 9:
        return $r('app.media.freecadsplash9');
      case 10:
        return $r('app.media.freecadsplash10');
      case 11:
        return $r('app.media.freecadsplash11');
      case 12:
        return $r('app.media.freecadsplash12');
      default:
        return $r('app.media.freecadsplash0');
    }
  }

  build() {
    Stack() {
      Image(this.getSplashImage())
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Contain)
        .interpolation(ImageInterpolation.High)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
  }
}
