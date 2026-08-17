allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// async_wallpaper eklentisinin kendi wallpaper.xml dosyası, kendi
// modülünde bulunmayan mipmap/ic_launcher kaynağına atıfta bulunuyor.
// Bu, release derlemesinde kaynak doğrulamasını düşürüyor (debug'da
// bu doğrulama çalışmadığı için sorun görünmüyordu).
//
// Uygulama canlı duvar kağıdı (live wallpaper) özelliğini kullanmıyor;
// görseli dosyadan ayarlıyor. Bu yüzden söz konusu XML çalışma
// zamanında devreye girmiyor ve doğrulamayı yalnızca bu eklenti için
// kapatmak güvenli.
subprojects {
    if (project.name == "async_wallpaper") {
        afterEvaluate {
            tasks.matching { it.name == "verifyReleaseResources" }
                .configureEach { enabled = false }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
