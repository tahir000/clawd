import Cocoa
import ApplicationServices

/// Claude penceresindeki mesaj kutusunun (yazı alanının) yerini Erişilebilirlik arayüzüyle bulur.
/// Yalnızca öğelerin türünü, konumunu ve boyutunu okur; yazılanları okumaz, hiçbir şeye basmaz.
/// Kullanıcının Sistem Ayarları'ndan Clawd'a Erişilebilirlik izni vermesi gerekir.
final class KutuIzleyici {
    private let kuyruk = DispatchQueue(label: "clawd.kutu", qos: .utility)
    private var mesgul = false                 // yalnızca ana iş parçacığında okunur ve yazılır
    private var onbellek: AXUIElement?         // bulunan yazı alanı
    private var onbellekPid: pid_t = 0
    private var bayrakPid: pid_t = 0           // erişilebilirlik ağacını bizim açtığımız Claude süreci
    private var sonArama: Double = -10
    private var basarisiz = 0
    private var sonOdakBakisi: Double = -10

    /// Sayfanın içi görünmediğinde isabet eden kabuk öğeleri.
    private let kabukRolleri: Set<String> = [
        "AXApplication", "AXWindow", "AXWebArea", "AXScrollArea", "AXGroup", "AXSplitGroup", "AXUnknown",
    ]

    static var izinVar: Bool { AXIsProcessTrusted() }

    /// Sistemin izin penceresini gösterir; izni kullanıcı Sistem Ayarları'ndan kendisi verir.
    static func izinIste() {
        let secenek = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(secenek)
    }

    /// `pencere`: Claude penceresi, ekranın sol üst köşesine göre. Sonuç da aynı koordinattadır.
    /// Ana iş parçacığından çağrılır; arama arka planda yapılır, `tamam` ana iş parçacığında döner.
    func yokla(pid: pid_t, pencere: CGRect, tamam: @escaping (CGRect?, String) -> Void) {
        if mesgul { return }
        mesgul = true
        kuyruk.async { [self] in
            let sonuc = ara(pid: pid, pencere: pencere)
            DispatchQueue.main.async {
                self.mesgul = false
                tamam(sonuc.0, sonuc.1)
            }
        }
    }

    /// Ağacı biz açtıysak eski haline döndürür (izleme kapatılınca ve çıkarken).
    func birak(bekle: Bool = false) {
        let temizle: () -> Void = { [self] in
            if bayrakPid != 0 {
                let uyg = AXUIElementCreateApplication(bayrakPid)
                AXUIElementSetMessagingTimeout(uyg, 0.3)
                AXUIElementSetAttributeValue(uyg, "AXManualAccessibility" as CFString, kCFBooleanFalse)
                bayrakPid = 0
            }
            onbellek = nil
            sonArama = -10
            basarisiz = 0
        }
        if bekle { kuyruk.sync { temizle() } } else { kuyruk.async { temizle() } }
    }

    // MARK: Arama (arka plan kuyruğunda)

    private func ara(pid: pid_t, pencere: CGRect) -> (CGRect?, String) {
        let uyg = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(uyg, 0.3)
        if pid != onbellekPid {
            onbellek = nil
            onbellekPid = pid
            basarisiz = 0
            sonArama = -10
        }

        // Bilinen yazı alanı duruyorsa yalnızca yeri sorulur (iki küçük sorgu)
        let simdi = CACurrentMediaTime()
        if let e = onbellek {
            if let f = cerceve(e), uygun(f, pencere) {
                // Arada bir klavye odağına bakılır: başka bir mesaj kutusuna geçildiyse (bölünmüş görünüm) Clawd da geçer
                if simdi - sonOdakBakisi > 2 {
                    sonOdakBakisi = simdi
                    if let o = oge(uyg, kAXFocusedUIElementAttribute), let a = aday(o, pencere, derinlik: 3), !CFEqual(a.0, e) {
                        onbellek = a.0
                        return (a.1, "odak degisti")
                    }
                }
                return (f, "onbellek")
            }
            onbellek = nil
        }

        if simdi - sonArama < (basarisiz >= 3 ? 5.0 : 1.5) { return (nil, "bekliyor") }
        sonArama = simdi

        // 1) Klavye odağındaki öğe çoğu zaman mesaj kutusudur
        if let o = oge(uyg, kAXFocusedUIElementAttribute), let a = aday(o, pencere, derinlik: 3) {
            onbellek = a.0
            basarisiz = 0
            return (a.1, "odak")
        }

        // 2) Pencerenin alt ve orta kısmındaki noktalarda ne olduğuna bakılır
        var acik = false
        let xs: [CGFloat] = [0.5, 0.6, 0.4, 0.7, 0.3]
        var ys: [CGFloat] = stride(from: CGFloat(30), through: 210, by: 20).map { pencere.maxY - $0 }
        ys += [0.6, 0.55, 0.5, 0.45].map { pencere.minY + pencere.height * $0 }
        for y in ys {
            for x in xs {
                var el: AXUIElement?
                let kod = AXUIElementCopyElementAtPosition(uyg, Float(pencere.minX + pencere.width * x), Float(y), &el)
                if kod == .cannotComplete { return (nil, "yanit yok") }
                guard kod == .success, let e = el else { continue }
                if !acik, let r = metin(e, kAXRoleAttribute), !kabukRolleri.contains(r) { acik = true }
                if let a = aday(e, pencere, derinlik: 8) {
                    onbellek = a.0
                    basarisiz = 0
                    return (a.1, "nokta")
                }
            }
        }
        basarisiz += 1

        // 3) Sayfanın içi hiç görünmüyorsa Claude'un erişilebilirlik ağacı kapalıdır; bir kez açılır
        if !acik && bayrakPid != pid {
            let kod = AXUIElementSetAttributeValue(uyg, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            bayrakPid = pid
            basarisiz = 0
            sonArama = simdi - 0.8
            return (nil, "agac acildi (\(kod.rawValue))")
        }
        return (nil, acik ? "kutu yok" : "agac kapali")
    }

    /// Öğenin kendisi ya da yakın atalarından biri geniş bir yazı alanıysa onu döndürür.
    private func aday(_ ilk: AXUIElement, _ pencere: CGRect, derinlik: Int) -> (AXUIElement, CGRect)? {
        var e = ilk
        for _ in 0...derinlik {
            if let r = metin(e, kAXRoleAttribute), r == "AXTextArea" || r == "AXTextField",
               let f = cerceve(e), uygun(f, pencere) {
                return (e, f)
            }
            guard let ust = oge(e, kAXParentAttribute) else { return nil }
            e = ust
        }
        return nil
    }

    private func uygun(_ f: CGRect, _ pencere: CGRect) -> Bool {
        f.width >= 240 && f.height >= 14 && f.height < pencere.height * 0.7
            && pencere.insetBy(dx: -4, dy: -4).contains(f)
    }

    private func metin(_ e: AXUIElement, _ ad: String) -> String? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, ad as CFString, &v) == .success else { return nil }
        return v as? String
    }

    private func oge(_ e: AXUIElement, _ ad: String) -> AXUIElement? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, ad as CFString, &v) == .success, let d = v,
              CFGetTypeID(d) == AXUIElementGetTypeID() else { return nil }
        return (d as! AXUIElement)
    }

    private func cerceve(_ e: AXUIElement) -> CGRect? {
        var p: CFTypeRef?
        var s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &s) == .success,
              let pd = p, let sd = s,
              CFGetTypeID(pd) == AXValueGetTypeID(), CFGetTypeID(sd) == AXValueGetTypeID() else { return nil }
        var nokta = CGPoint.zero
        var boyut = CGSize.zero
        guard AXValueGetValue(pd as! AXValue, .cgPoint, &nokta),
              AXValueGetValue(sd as! AXValue, .cgSize, &boyut) else { return nil }
        return CGRect(origin: nokta, size: boyut)
    }
}
