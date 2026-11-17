import Cocoa
import Darwin
import ServiceManagement

let claudeKimlik = "com.anthropic.claudefordesktop"

/// İçinde Claude Code çalıştırılabilen terminaller ve düzenleyiciler.
let terminalKimlikleri: Set<String> = [
    "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
    "net.kovidgoyal.kitty", "org.alacritty", "com.github.wez.wezterm", "com.microsoft.VSCode",
    "com.todesktop.230313mzl4w4u92", "dev.zed.Zed",
]

enum Mod: String { case bekle, oyun, calis, uyu }
enum Baglam: String { case claude, masaustu }

/// Bilgisayarda "claude" adlı bir süreç (terminaldeki Claude Code) çalışıyor mu.
func claudeSureciCalisiyor() -> Bool {
    let adet = proc_listallpids(nil, 0)
    guard adet > 0 else { return false }
    var pidler = [pid_t](repeating: 0, count: Int(adet) + 64)
    let n = proc_listallpids(&pidler, Int32(pidler.count * MemoryLayout<pid_t>.size))
    guard n > 0 else { return false }
    var ad = [CChar](repeating: 0, count: 64)
    for i in 0..<min(Int(n), pidler.count) {
        if proc_name(pidler[i], &ad, UInt32(ad.count)) > 0, String(cString: ad) == "claude" { return true }
    }
    return false
}

final class Panel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// İçeriğini bir kapanışla çizen katman (z harfleri ve parçacıklar gibi seyrek çizimler için).
final class CizimKatmani: CALayer {
    var cizici: ((CGContext) -> Void)?
    override func draw(in ctx: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        cizici?(ctx)
        NSGraphicsContext.restoreGraphicsState()
    }
    override func action(forKey event: String) -> CAAction? { nil }
}

// MARK: - Karakter görünümü

/// Clawd hazır bir resimle gösterilir: resim yalnızca görünen bir şey (yüz, kol, bacak) değişince yeniden
/// çizilir; eğilme, esneme ve adım katman dönüşümüyle yapılır. Böylece her karede çizim yapılmaz.
final class KarakterGorunum: NSView {
    weak var sahip: Uygulama?
    let kap = CALayer()
    let govde = CALayer()
    let ust = CizimKatmani()              // z harfleri
    var govdeAnahtar = ""
    var olcekAnahtar: CGFloat = 0

    // Resim alanı, karakter biriminde (gövde merkezi 0,0)
    static let govdeKutu = CGRect(x: -23, y: -16, width: 46, height: 32)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        guard let l = layer else { return }
        l.addSublayer(kap)
        let kutu = Self.govdeKutu
        govde.bounds = CGRect(origin: .zero, size: kutu.size)
        govde.anchorPoint = CGPoint(x: -kutu.minX / kutu.width, y: -kutu.minY / kutu.height)
        kap.addSublayer(govde)
        ust.cizici = { [weak self] _ in
            guard let v = self, let s = v.sahip, s.uyuyor, s.mutluluk <= 0 else { return }
            uykuHarfleri(merkez: CGPoint(x: v.bounds.midX, y: v.bounds.midY) + s.cizimKayma, olcek: s.S, zaman: s.zaman)
        }
        l.addSublayer(ust)
    }

    required init?(coder: NSCoder) { fatalError("kullanılmıyor") }

    func guncelle(poz p: Poz, kayma: CGPoint, S: CGFloat) {
        let piksel = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        if olcekAnahtar != S * piksel {
            olcekAnahtar = S * piksel
            govdeAnahtar = ""
            ust.contentsScale = piksel
        }
        if ust.frame != bounds { ust.frame = bounds }

        // Gövde resmi yalnızca görünen bir şey değişince yenilenir
        func q(_ v: CGFloat, _ k: CGFloat) -> Int { Int((v * k).rounded()) }
        let anahtar = "\(p.yuz)|\(q(p.kirpma, 4))|\(q(p.bakis.x, 6))|\(q(p.bakis.y, 6))|\(q(p.kolSol, 2))|\(q(p.kolSag, 2))|\(p.bacak.map { q($0, 2) })"
        if anahtar != govdeAnahtar {
            govdeAnahtar = anahtar
            let kutu = Self.govdeKutu
            govde.contents = goruntuUret(genislik: kutu.width, yukseklik: kutu.height, piksel: S * piksel) { c in
                c.translateBy(x: -kutu.minX, y: -kutu.minY)
                clawdCiz(c, poz: p)
            }
        }

        kap.position = CGPoint(x: bounds.midX + kayma.x, y: bounds.midY + kayma.y)
        // Basılıp esnerken ayakları (-12,5 hizası) yerinde kalır
        var t = CATransform3DMakeRotation(p.egim, 0, 0, 1)
        t = CATransform3DTranslate(t, 0, -12.5 * S * p.ezme, 0)
        t = CATransform3DScale(t, S * (1 + p.ezme), S * (1 - p.ezme), 1)
        kap.transform = t
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { sahip?.menuGoster(event, self); return }
        sahip?.fareBasildi()
    }
    override func mouseDragged(with event: NSEvent) { sahip?.fareSuruklendi() }
    override func mouseUp(with event: NSEvent) { sahip?.fareBirakildi() }
    override func rightMouseDown(with event: NSEvent) { sahip?.menuGoster(event, self) }
}

// MARK: - Sahne görünümü (iş listesi, yıldızlar, konuşma balonu)

final class SahneGorunum: NSView {
    weak var sahip: Uygulama?
    let listeKatman = CALayer()
    let parcaKatman = CizimKatmani()
    let balonKatman = CALayer()
    var listeAnahtar: [Int] = []
    var balonAnahtar = ""
    var olcekAnahtar: CGFloat = 0

    static let listeKutu = CGRect(x: -18, y: -19, width: 36, height: 38)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        guard let l = layer else { return }
        let lk = Self.listeKutu
        listeKatman.bounds = CGRect(origin: .zero, size: lk.size)
        listeKatman.anchorPoint = CGPoint(x: -lk.minX / lk.width, y: -lk.minY / lk.height)
        listeKatman.isHidden = true
        l.addSublayer(listeKatman)
        parcaKatman.frame = bounds
        parcaKatman.cizici = { [weak self] c in
            guard let s = self?.sahip else { return }
            let ko = s.sahnePencere.frame.origin
            for p in s.parcalar { parcaCiz(c, p, kayma: ko) }
        }
        l.addSublayer(parcaKatman)
        balonKatman.isHidden = true
        l.addSublayer(balonKatman)
    }

    required init?(coder: NSCoder) { fatalError("kullanılmıyor") }

    /// `merkez` görünüm koordinatındadır.
    func guncelle(satirlar: [Satir], merkez: CGPoint, S: CGFloat, alfa: CGFloat) {
        let piksel = window?.backingScaleFactor ?? 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if olcekAnahtar != S * piksel {
            olcekAnahtar = S * piksel
            listeAnahtar = []
            parcaKatman.contentsScale = piksel
        }
        let gorunur = alfa > 0.01 && !satirlar.isEmpty
        listeKatman.isHidden = !gorunur
        if gorunur {
            listeKatman.opacity = Float(alfa)
            let anahtar = satirlar.map { Int($0.belirme * 100) * 1000 + Int($0.dolu * 300) }
            if anahtar != listeAnahtar {
                listeAnahtar = anahtar
                let lk = Self.listeKutu
                listeKatman.contents = goruntuUret(genislik: lk.width, yukseklik: lk.height, piksel: S * piksel) { c in
                    gorevCiz(c, merkez: CGPoint(x: -lk.minX, y: -lk.minY), olcek: 1, satirlar: satirlar, alfa: 1)
                }
            }
            listeKatman.position = merkez
            listeKatman.transform = CATransform3DMakeScale(S, S, 1)
        }
        CATransaction.commit()
    }

    func balonGizle() {
        guard !balonKatman.isHidden else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        balonKatman.isHidden = true
        balonAnahtar = ""
        CATransaction.commit()
    }

    /// Balonu gösterir. `uc`: kuyruğun ucu, `kutuSol`: kutunun sol kenarı (ikisi de görünüm koordinatında).
    /// Balon bir kez resme çizilir; büyüme ve sönme katman dönüşümüyle yapılır.
    func balonGoster(baslik: String, satirlar: [String], olcu: CGSize, uc: CGPoint, kutuSol: CGFloat,
                     asagi: Bool, buyume: CGFloat, alfa: CGFloat) {
        let piksel = window?.backingScaleFactor ?? 2
        let pay = Balon.pay
        let ucX = (uc.x - kutuSol).rounded()            // kuyruğun kutu içindeki yeri
        let gen = olcu.width + pay * 2
        let yuk = olcu.height + Balon.kuyruk + pay * 2
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let anahtar = "\(baslik)|\(satirlar.joined(separator: "/"))|\(Int(ucX))|\(asagi)|\(piksel)"
        if anahtar != balonAnahtar {
            balonAnahtar = anahtar
            balonKatman.contents = goruntuUret(genislik: gen, yukseklik: yuk, piksel: piksel) { c in
                let kutu = CGRect(x: pay, y: asagi ? pay : pay + Balon.kuyruk, width: olcu.width, height: olcu.height)
                Balon.ciz(c, kutu: kutu, ucX: pay + ucX, asagi: asagi, baslik: baslik, satirlar: satirlar)
            }
            balonKatman.bounds = CGRect(x: 0, y: 0, width: gen, height: yuk)
            // Kuyruğun ucu katmanın dayanak noktasıdır: balon oradan büyür
            balonKatman.anchorPoint = CGPoint(x: (pay + ucX) / gen,
                                              y: asagi ? (pay + olcu.height + Balon.kuyruk) / yuk : pay / yuk)
        }
        balonKatman.isHidden = false
        balonKatman.position = uc
        balonKatman.transform = CATransform3DMakeScale(buyume, buyume, 1)
        balonKatman.opacity = Float(alfa)
        CATransaction.commit()
    }
}

// MARK: - Uygulama

final class Uygulama: NSObject, NSApplicationDelegate {
    let ayar = UserDefaults.standard

    // Ayarlar
    var S: CGFloat = 0.85
    var bosSure: Double = 180
    var dolumSuresi: Double = 9

    // Pencereler
    var karakterPencere: Panel!
    var sahnePencere: Panel!
    var karakterGorunum: KarakterGorunum!
    var sahneGorunum: SahneGorunum!
    var zamanlayici: Timer?
    var guncelFps: Double = 0

    // Durum
    var mod: Mod = .bekle
    var baglam: Baglam = .masaustu
    var claudeCerceve: CGRect?
    var claudePencereNo: CGWindowID = 0
    var sonTamTarama: Double = -10
    var sonCerceveDegisim: Double = -10
    var konum = CGPoint.zero
    var hiz = CGPoint.zero
    var ev = CGPoint.zero
    var sahneEv = CGPoint.zero
    var hedefler: [CGPoint] = []
    var zaman: Double = 0
    var sonTik: Double = 0
    var sonEtkilesim: Double = 0
    var sonEvYoklama: Double = -10
    var sonGunluk: Double = 0
    var gunlukSayac = 0

    // Mesaj kutusunu izleme (Erişilebilirlik izniyle)
    let izleyici = KutuIzleyici()
    var kutuIzle = true
    var izinVar = false
    var claudePid: pid_t = 0
    var kutuGoreli: CGRect?            // yazı alanı, Claude penceresinin sol alt köşesine göre
    var kutuBoyut = CGSize.zero        // o ölçüm alındığındaki pencere boyutu
    var kutuZamani: Double = -10
    var kutuDurum = "-"
    var sonKutuYoklama: Double = -10
    var sonKutuDegisim: Double = -10
    var sonIzinYoklama: Double = -10

    // Fare
    var basili = false
    var surukleniyor = false
    var menuAcik = false
    var basNokta = CGPoint.zero
    var surukFark = CGPoint.zero

    // İş listesi
    var liste: [Satir] = []
    var aktifSatir = 0
    var listeAlfa: CGFloat = 1
    var listeSoluyor = false
    var calisiyor = false

    // Canlandırma
    var parcalar: [Parca] = []
    var parcaCizili = false
    var uykuCizili = false
    var poz = Poz()
    var cizimKayma = CGPoint.zero
    var faz: CGFloat = 0
    var adimFaz: CGFloat = 0
    var egim: CGFloat = 0
    var bakis = CGPoint.zero
    var mutluluk: CGFloat = 0
    var takla: CGFloat = 0
    var taklaYon: CGFloat = 1
    var inis: CGFloat = 0
    var sonrakiKirpma: Double = 2
    var uyuyor = false

    // Konuşma balonu ve öneriler
    var balonAcik = false
    var balonYas: CGFloat = 0
    var balonOmur: CGFloat = 4.5
    var balonBaslik = ""
    var balonSatirlar: [String] = []
    var balonOlcu = CGSize.zero
    var ipucuAcik = true
    var kodAcik = false                 // Claude Code önde
    var claudeSureciVar = false
    var sozSira = 0
    var ipucuSira = 0
    var tikSayac = 0
    var sonrakiIpucu: Double = -1
    var sonIpucu: Double = -100
    var sonSurecBakisi: Double = -100
    var ipucuAraligi: Double = 120

    var karakterKenar: CGFloat { max(96, (120 * S).rounded()) }
    var sahneBoyut: CGSize { CGSize(width: 470, height: 300) }     // konuşma balonu sığsın diye geniş

    // MARK: Başlangıç

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let kimlik = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: kimlik).count > 1 {
            NSApp.terminate(nil)
            return
        }
        ayar.register(defaults: ["bosSure": 180.0, "dolumSuresi": 9.0, "olcek": 0.85, "kutuIzle": true,
                                 "ipucu": true, "ipucuAralik": 120.0])
        S = sinirla(CGFloat(ayar.double(forKey: "olcek")), 0.5, 2)
        bosSure = max(3, ayar.double(forKey: "bosSure"))
        dolumSuresi = max(0.3, ayar.double(forKey: "dolumSuresi"))
        kutuIzle = ayar.bool(forKey: "kutuIzle")
        ipucuAcik = ayar.bool(forKey: "ipucu")
        ipucuAraligi = max(10, ayar.double(forKey: "ipucuAralik"))
        ipucuSira = Int.random(in: 0..<ipuclari.count)      // her açılışta başka bir öneriden başlar
        sozSira = Int.random(in: 0..<sozler.count)
        izinVar = kutuIzle && KutuIzleyici.izinVar
        if kutuIzle && !izinVar && !ayar.bool(forKey: "izinSoruldu") {
            // İzin penceresi bir kez kendiliğinden çıkar; sonrası için menüde "Erişilebilirlik iznini ver" var
            ayar.set(true, forKey: "izinSoruldu")
            KutuIzleyici.izinIste()
        }

        senaryoOku()
        pencereleriKur()
        evGuncelle()
        sahneEv = ev
        konum = ev + CGPoint(x: -150, y: 0)
        sonTik = CACurrentMediaTime()
        sonEtkilesim = sonTik

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(onUygulamaDegisti),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        fpsAyarla(60)
    }

    func applicationWillTerminate(_ notification: Notification) {
        izleyici.birak(bekle: true)
    }

    func panelYap(_ boyut: CGSize) -> Panel {
        let p = Panel(contentRect: NSRect(origin: .zero, size: boyut),
                      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.isMovable = false
        p.ignoresMouseEvents = true
        return p
    }

    func pencereleriKur() {
        let k = karakterKenar
        karakterPencere = panelYap(CGSize(width: k, height: k))
        karakterGorunum = KarakterGorunum(frame: NSRect(x: 0, y: 0, width: k, height: k))
        karakterGorunum.sahip = self
        karakterPencere.contentView = karakterGorunum

        // Sahne üsttedir: konuşma balonu Clawd'ın önünde durur. Tıklamayı geçirdiği için Clawd yine tıklanır.
        sahnePencere = panelYap(sahneBoyut)
        sahnePencere.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        sahneGorunum = SahneGorunum(frame: NSRect(origin: .zero, size: sahneBoyut))
        sahneGorunum.sahip = self
        sahnePencere.contentView = sahneGorunum

        karakterPencere.orderFrontRegardless()
        sahnePencere.orderFrontRegardless()
    }

    func fpsAyarla(_ fps: Double) {
        guard fps != guncelFps else { return }
        guncelFps = fps
        zamanlayici?.invalidate()
        let t = Timer(timeInterval: 1.0 / fps, repeats: true) { [weak self] _ in self?.tik() }
        t.tolerance = 0.15 / fps
        RunLoop.main.add(t, forMode: .common)
        zamanlayici = t
    }

    @objc func onUygulamaDegisti() {
        sonTamTarama = -10
        evGuncelle()
        fpsAyarla(60)
    }

    // MARK: Ev (Clawd'ın durduğu yer)

    func anaEkran() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
    }

    func uygunCerceve(_ w: [String: Any], _ pid: pid_t) -> CGRect? {
        guard (w[kCGWindowOwnerPID as String] as? Int32) == pid,
              (w[kCGWindowLayer as String] as? Int) == 0,
              let b = w[kCGWindowBounds as String] as? NSDictionary,
              let r = CGRect(dictionaryRepresentation: b as CFDictionary),
              r.width > 420, r.height > 320 else { return nil }
        return r
    }

    /// Öndeki Claude penceresi, Cocoa koordinatlarında (sol alt köşe başlangıç).
    /// Bütün pencereleri taramak pahalı olduğu için saniyede bir yapılır; arada yalnızca bilinen pencere sorulur.
    func claudePenceresi(pid: pid_t) -> CGRect? {
        let simdi = CACurrentMediaTime()
        let anaYukseklik = NSScreen.screens.first?.frame.height ?? 0
        func cevir(_ r: CGRect) -> CGRect { CGRect(x: r.minX, y: anaYukseklik - r.maxY, width: r.width, height: r.height) }

        if claudePencereNo != 0, simdi - sonTamTarama < 1.0,
           let l = CGWindowListCopyWindowInfo([.optionIncludingWindow], claudePencereNo) as? [[String: Any]],
           let w = l.first, (w[kCGWindowIsOnscreen as String] as? Bool) == true, let r = uygunCerceve(w, pid) {
            return cevir(r)
        }
        sonTamTarama = simdi
        claudePencereNo = 0
        guard let liste = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        for w in liste {
            if let r = uygunCerceve(w, pid) {
                claudePencereNo = (w[kCGWindowNumber as String] as? UInt32) ?? 0
                return cevir(r)
            }
        }
        return nil
    }

    func evGuncelle() {
        let on = NSWorkspace.shared.frontmostApplication
        var yeni = baglam
        var cerceve: CGRect? = nil
        if let on = on, on.bundleIdentifier == claudeKimlik, let c = claudePenceresi(pid: on.processIdentifier) {
            yeni = .claude
            cerceve = c
            claudePid = on.processIdentifier
        } else if ayar.bool(forKey: "claudeZorla"),
                  let cl = NSRunningApplication.runningApplications(withBundleIdentifier: claudeKimlik).first,
                  let c = claudePenceresi(pid: cl.processIdentifier) {
            yeni = .claude
            cerceve = c
            claudePid = cl.processIdentifier
        } else if on?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            cerceve = claudeCerceve
        } else {
            yeni = .masaustu
        }
        if yeni == .claude && cerceve == nil { yeni = .masaustu }
        if yeni != baglam {
            baglam = yeni
            if mod == .oyun {
                hedefler.removeAll()
                mod = .bekle
            }
        }
        if cerceve != claudeCerceve { sonCerceveDegisim = CACurrentMediaTime() }
        claudeCerceve = cerceve
        kodAcikMiBak(on)
        ev = evNoktasi()
    }

    /// Claude Code önde mi: Claude uygulaması ya da bir `claude` süreci çalışırken öne gelen bir terminal.
    /// Terminalde ne çalıştığı dışarıdan kesin bilinemez; bu bir tahmindir.
    func kodAcikMiBak(_ on: NSRunningApplication?) {
        if ayar.bool(forKey: "kodZorla") { kodAcik = true; return }
        guard let on = on else { kodAcik = false; return }
        if on.processIdentifier == ProcessInfo.processInfo.processIdentifier { return }     // kendi menümüz açıkken değişmez
        if on.bundleIdentifier == claudeKimlik { kodAcik = true; return }
        guard let kimlik = on.bundleIdentifier, terminalKimlikleri.contains(kimlik) else { kodAcik = false; return }
        let simdi = CACurrentMediaTime()
        if simdi - sonSurecBakisi > 5 {
            sonSurecBakisi = simdi              // süreç listesine seyrek bakılır
            claudeSureciVar = claudeSureciCalisiyor()
        }
        kodAcik = claudeSureciVar
    }

    /// Menü çubuğunun alt kenarı, çentiğin sol ve sağ ucu.
    func centikOlculeri(_ e: NSScreen) -> (alt: CGFloat, sol: CGFloat, sag: CGFloat) {
        let f = e.frame
        let ust = max(f.maxY - e.visibleFrame.maxY, e.safeAreaInsets.top)
        var sol = f.midX - 104
        var sag = f.midX + 104
        if let l = e.auxiliaryTopLeftArea, let r = e.auxiliaryTopRightArea, r.minX > l.maxX {
            sol = l.maxX
            sag = r.minX
        }
        return (f.maxY - ust, sol, sag)
    }

    /// Mesaj kutusu bulunamadığında kullanılan tahmin: kenar çubuğu 260, yazı alanı 644 geniş ve ortalı.
    func varsayilanClaudeMx(_ w: CGRect) -> Double {
        Double(130 + min(322, (w.width - 260) / 2 - 24) - 45)
    }

    func evNoktasi() -> CGPoint {
        if baglam == .claude, let w = claudeCerceve {
            if let k = gecerliKutu(w) {
                // Yazı alanının sağ üst köşesine göre: Clawd kutunun üst kenarına basar (yazı alanının yaklaşık 14 üstü)
                let dx = ayar.object(forKey: "kutuDx") as? Double ?? -45
                let dy = ayar.object(forKey: "kutuDy") as? Double ?? Double(14 + 12.5 * S)
                return CGPoint(x: k.maxX + CGFloat(dx), y: k.maxY + CGFloat(dy))
            }
            let mx = ayar.object(forKey: "claudeMx") as? Double ?? varsayilanClaudeMx(w)
            let dy = ayar.object(forKey: "claudeDy") as? Double ?? Double(86 + 12.5 * S)
            return CGPoint(x: sinirla(w.midX + CGFloat(mx), w.minX + 30, w.maxX - 20),
                           y: sinirla(w.minY + CGFloat(dy), w.minY + 20, w.maxY - 20))
        }
        guard let e = anaEkran() else { return CGPoint(x: 400, y: 400) }
        let f = e.frame
        let o = centikOlculeri(e)
        // Çentik varsa solunda, menü çubuğunun içinde oturur; yoksa çubuğun hemen altında
        let varsayilan = e.safeAreaInsets.top > 0
            ? CGPoint(x: o.sol - 98, y: o.alt + (f.maxY - o.alt) / 2 - 1)
            : CGPoint(x: f.midX - 60, y: o.alt - 6 - 12.5 * S)
        if let dx = ayar.object(forKey: "masaDx") as? Double, let dy = ayar.object(forKey: "masaDy") as? Double {
            let p = CGPoint(x: f.midX + CGFloat(dx), y: o.alt + CGFloat(dy))
            if NSScreen.screens.contains(where: { $0.frame.insetBy(dx: 10, dy: 10).contains(p) }) { return p }
        }
        return varsayilan
    }

    func yeriKaydet() {
        if baglam == .claude, let w = claudeCerceve {
            if let k = gecerliKutu(w) {
                ayar.set(Double(konum.x - k.maxX), forKey: "kutuDx")
                ayar.set(Double(konum.y - k.maxY), forKey: "kutuDy")
            } else {
                ayar.set(Double(konum.x - w.midX), forKey: "claudeMx")
                ayar.set(Double(konum.y - w.minY), forKey: "claudeDy")
            }
        } else if let e = anaEkran() {
            let o = centikOlculeri(e)
            ayar.set(Double(konum.x - e.frame.midX), forKey: "masaDx")
            ayar.set(Double(konum.y - o.alt), forKey: "masaDy")
        }
        ev = evNoktasi()
    }

    /// Koşu noktalarını Clawd'ın bulunduğu ekranın içinde tutar.
    func ekranaSigdir(_ p: CGPoint) -> CGPoint {
        let e = NSScreen.screens.first(where: { $0.frame.contains(ev) }) ?? anaEkran()
        guard let f = e?.frame else { return p }
        return CGPoint(x: sinirla(p.x, f.minX + 34, f.maxX - 34), y: p.y)
    }

    // MARK: Fare

    func fareBasildi() {
        basili = true
        surukleniyor = false
        basNokta = NSEvent.mouseLocation
        surukFark = konum - basNokta
    }

    func fareSuruklendi() {
        guard basili else { return }
        let f = NSEvent.mouseLocation
        if !surukleniyor && (f - basNokta).uzunluk > 4 {
            surukleniyor = true
            hedefler.removeAll()
            if !liste.isEmpty && !listeSoluyor { listeyiTopla() }
            mod = .bekle
            fpsAyarla(60)
        }
        if surukleniyor {
            konum = f + surukFark
            hiz = .zero
            pencereleriYerlestir()
        }
    }

    func fareBirakildi() {
        guard basili else { return }
        basili = false
        sonEtkilesim = CACurrentMediaTime()
        if surukleniyor {
            surukleniyor = false
            yeriKaydet()
            inis = 1
        } else {
            tiklandi()
        }
    }

    // MARK: Sözler ve öneriler

    /// Konsol görünümlü balonu açar: `baslik` komut ya da kısayoldur (boş olabilir), `metin` satırlara bölünür.
    func balonGoster(_ baslik: String, _ metin: String, _ omur: CGFloat) {
        balonBaslik = baslik
        balonSatirlar = sar(metin, 36)
        balonOlcu = Balon.olcu(baslik: baslik, satirlar: balonSatirlar)
        balonYas = 0
        balonOmur = omur
        balonAcik = true
        fpsAyarla(60)
    }

    /// Sıradaki Claude Code önerisini gösterir.
    @objc func ipucuGoster() {
        let ipucu = ipuclari[ipucuSira % ipuclari.count]
        ipucuSira += 1
        balonGoster(ipucu.0, ipucu.1, 9)
        sonIpucu = CACurrentMediaTime()
        mutluluk = max(mutluluk, 0.7)
    }

    /// Tıklanınca sevinir, bir söz söyler ve yana yana koşup geri gelir. Claude Code öndeyken her ikinci
    /// tıklamada söz yerine bir komut önerisi verir. İş listesi açıksa toplanır.
    func tiklandi() {
        sonEtkilesim = CACurrentMediaTime()
        if !liste.isEmpty && !listeSoluyor { listeyiTopla() }
        mutluluk = 1.3
        inis = 1
        tikSayac += 1
        if kodAcik && tikSayac % 2 == 0 {
            ipucuGoster()
        } else {
            balonGoster("", sozler[sozSira % sozler.count], 4.5)
            sozSira += 1
        }
        if mod == .oyun {
            takla = 1
            taklaYon = hiz.x >= 0 ? -1 : 1
        }
        mod = .oyun
        let yon: CGFloat = Bool.random() ? 1 : -1
        let a = ev + CGPoint(x: yon * rastgele(40, 70), y: 0)
        let b = ev + CGPoint(x: -yon * rastgele(25, 45), y: 0)
        hedefler = [a, b].map(ekranaSigdir) + [ev]
        fpsAyarla(60)
    }

    /// Claude Code öndeyken arada bir komut önerisi verir. Claude Code öne geldiğinde uyuyorsa ya da iş
    /// listesiyle uğraşıyorsa bırakıp uyanır.
    func oneriDongusu(_ simdi: Double) {
        guard kodAcik else {
            sonrakiIpucu = -1
            return
        }
        guard ipucuAcik else { return }
        if mod == .calis || mod == .uyu {
            if !liste.isEmpty && !listeSoluyor { listeyiTopla() }
            mod = .bekle
            sonEtkilesim = simdi
        }
        // Öne gelince ilk öneri birkaç saniye sonra; pencere sık değiştirilse de öneriler art arda yağmaz
        if sonrakiIpucu < 0 { sonrakiIpucu = max(simdi + 6, sonIpucu + 25) }
        if simdi < sonrakiIpucu || balonAcik || surukleniyor || menuAcik || basili || mod != .bekle { return }
        ipucuGoster()
        sonrakiIpucu = simdi + ipucuAraligi
    }

    // MARK: İş listesi

    func listeyeBasla() {
        liste = gorevDizilimi().map { Satir(ofset: $0) }
        aktifSatir = 0
        listeAlfa = 1
        listeSoluyor = false
        hedefler.removeAll()
        mod = .calis
    }

    /// İş listesinin merkezi: Clawd'ın solunda, tabanı ayak hizasında. Clawd menü çubuğunda oturuyorsa liste
    /// çubuğun altına asılır; yanına konsaydı menülerin üstüne binerdi.
    func listeMerkez(_ taban: CGPoint) -> CGPoint {
        if baglam == .masaustu, let e = anaEkran() {
            let alt = centikOlculeri(e).alt
            if taban.y + 13 * S > alt && taban.x > e.frame.minX && taban.x < e.frame.maxX {
                return CGPoint(x: taban.x, y: alt - 4 - 17 * S)
            }
        }
        return taban + CGPoint(x: -39 * S, y: 4.5 * S)
    }

    /// Sıradaki satırı belirtir, yazar ve işaretler. Clawd bunu durduğu yerden yapar.
    func calis(_ dt: CGFloat) {
        guard aktifSatir < liste.count else {
            mod = .uyu
            return
        }
        guard (konum - ev).uzunluk < 9, (sahneEv - ev).uzunluk < 1 else { return }
        calisiyor = true
        if liste[aktifSatir].belirme < 1 {
            liste[aktifSatir].belirme = min(1, liste[aktifSatir].belirme + dt / 0.45)
        } else {
            liste[aktifSatir].dolu += dt / CGFloat(dolumSuresi)
            if liste[aktifSatir].dolu >= 1 {
                liste[aktifSatir].dolu = 1
                aktifSatir += 1
                if aktifSatir >= liste.count {
                    mod = .uyu
                    mutluluk = 1.0
                    balonGoster("", "Liste bitti. Biraz kestireyim.", 3.5)
                }
            }
        }
    }

    /// Listeyi kapatır: satırlardan yıldız saçılır, biten satır sayısı sayaca eklenir.
    func listeyiTopla() {
        let biten = liste.filter { $0.dolu > 0.5 }.count
        let lm = listeMerkez(sahneEv)
        for s in liste where s.belirme > 0.5 {
            let m = lm + s.ofset * S
            for _ in 0..<2 {
                let a = rastgele(0, 2 * .pi)
                let v = rastgele(26, 64)
                parcalar.append(Parca(tur: .yildiz, konum: m, hiz: CGPoint(x: cos(a) * v, y: sin(a) * v + 14),
                                      omur: rastgele(0.55, 0.9), boyut: rastgele(2.6, 4.6) * S, donus: rastgele(0, 3)))
            }
        }
        if biten > 0 {
            ayar.set(ayar.integer(forKey: "biten") + biten, forKey: "biten")
            parcalar.append(Parca(tur: .yazi("+\(biten)"), konum: lm + CGPoint(x: 0, y: 26 * S),
                                  hiz: CGPoint(x: 0, y: 30), omur: 1.5, boyut: 14 * S))
        }
        listeSoluyor = true
        fpsAyarla(60)
    }

    // MARK: Menü

    func menuGoster(_ olay: NSEvent, _ gorunum: NSView) {
        let m = NSMenu()
        m.autoenablesItems = false
        let bilgi = NSMenuItem(title: "Biten iş: \(ayar.integer(forKey: "biten"))", action: nil, keyEquivalent: "")
        bilgi.isEnabled = false
        m.addItem(bilgi)
        m.addItem(.separator())

        func kalem(_ ad: String, _ eylem: Selector, _ nesne: Any? = nil, isaretli: Bool = false) -> NSMenuItem {
            let i = NSMenuItem(title: ad, action: eylem, keyEquivalent: "")
            i.target = self
            i.representedObject = nesne
            i.state = isaretli ? .on : .off
            return i
        }
        func altMenu(_ ad: String, _ alt: NSMenu) -> NSMenuItem {
            let i = NSMenuItem(title: ad, action: nil, keyEquivalent: "")
            i.submenu = alt
            return i
        }

        m.addItem(kalem("Şimdi bir öneri ver", #selector(simdiOneriVer)))
        m.addItem(kalem("Claude Code açıkken öneri ver", #selector(oneriDegistir), nil, isaretli: ipucuAcik))
        let siklik = NSMenu()
        for (ad, sn) in [("30 saniye", 30.0), ("2 dakika", 120.0), ("5 dakika", 300.0), ("15 dakika", 900.0)] {
            siklik.addItem(kalem(ad, #selector(siklikSec(_:)), sn, isaretli: abs(ipucuAraligi - sn) < 1))
        }
        m.addItem(altMenu("Öneri sıklığı", siklik))
        m.addItem(.separator())

        m.addItem(kalem("Şimdi iş listesini yap", #selector(simdiListeYap)))
        let sure = NSMenu()
        for (ad, sn) in [("1 dakika", 60.0), ("3 dakika", 180.0), ("10 dakika", 600.0), ("30 dakika", 1800.0)] {
            sure.addItem(kalem(ad, #selector(sureSec(_:)), sn, isaretli: abs(bosSure - sn) < 1))
        }
        m.addItem(altMenu("İş listesine başlama süresi", sure))
        let boyut = NSMenu()
        for (ad, o) in [("Küçük", 0.7), ("Orta", 0.85), ("Büyük", 1.1)] {
            boyut.addItem(kalem(ad, #selector(boyutSec(_:)), o, isaretli: abs(Double(S) - o) < 0.01))
        }
        m.addItem(altMenu("Boyut", boyut))
        m.addItem(kalem("Buradaki yerini sıfırla", #selector(yeriSifirla)))
        m.addItem(.separator())

        m.addItem(kalem("Claude'da mesaj kutusunu izle", #selector(kutuIzleDegistir), nil, isaretli: kutuIzle))
        if kutuIzle && !KutuIzleyici.izinVar {
            m.addItem(kalem("Erişilebilirlik iznini ver…", #selector(izinVer)))
        }
        if #available(macOS 13.0, *) {
            m.addItem(kalem("Bilgisayar açılınca başlat", #selector(giristeAc), nil,
                            isaretli: SMAppService.mainApp.status == .enabled))
        }
        m.addItem(.separator())
        m.addItem(kalem("Clawd'ı kapat", #selector(kapat)))

        menuAcik = true
        NSMenu.popUpContextMenu(m, with: olay, for: gorunum)
        menuAcik = false
    }

    @objc func simdiOneriVer() {
        sonEtkilesim = CACurrentMediaTime()
        ipucuGoster()
    }

    @objc func oneriDegistir() {
        ipucuAcik.toggle()
        ayar.set(ipucuAcik, forKey: "ipucu")
        sonrakiIpucu = -1
    }

    @objc func siklikSec(_ i: NSMenuItem) {
        guard let sn = i.representedObject as? Double else { return }
        ipucuAraligi = sn
        ayar.set(sn, forKey: "ipucuAralik")
        sonrakiIpucu = -1
    }

    @objc func simdiListeYap() {
        if !liste.isEmpty {
            listeyiTopla()
            liste.removeAll()
            listeSoluyor = false
            listeAlfa = 1
        }
        listeyeBasla()
    }

    @objc func sureSec(_ i: NSMenuItem) {
        guard let sn = i.representedObject as? Double else { return }
        bosSure = sn
        ayar.set(sn, forKey: "bosSure")
        sonEtkilesim = CACurrentMediaTime()
    }

    @objc func boyutSec(_ i: NSMenuItem) {
        guard let o = i.representedObject as? Double else { return }
        S = CGFloat(o)
        ayar.set(o, forKey: "olcek")
        let k = karakterKenar
        karakterPencere.setContentSize(CGSize(width: k, height: k))
        karakterGorunum.frame = NSRect(x: 0, y: 0, width: k, height: k)
        ev = evNoktasi()
    }

    @objc func yeriSifirla() {
        if baglam == .claude {
            for anahtar in ["claudeMx", "claudeDy", "kutuDx", "kutuDy"] { ayar.removeObject(forKey: anahtar) }
        } else {
            ayar.removeObject(forKey: "masaDx")
            ayar.removeObject(forKey: "masaDy")
        }
        ev = evNoktasi()
    }

    @objc func kutuIzleDegistir() {
        kutuIzle.toggle()
        ayar.set(kutuIzle, forKey: "kutuIzle")
        if kutuIzle {
            izinVar = KutuIzleyici.izinVar
            if !izinVar { izinVer() }
        } else {
            izleyici.birak()
            kutuGoreli = nil
            izinVar = false
        }
        ev = evNoktasi()
    }

    /// Sistemin izin penceresini ve ilgili ayar sayfasını açar; izni kullanıcı kendisi verir.
    @objc func izinVer() {
        KutuIzleyici.izinIste()
        if let u = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(u)
        }
    }

    @objc func giristeAc() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSSound.beep()
            NSLog("Açılışta başlatma ayarlanamadı: \(error.localizedDescription)")
        }
    }

    @objc func kapat() { NSApp.terminate(nil) }

    // MARK: Her karede

    func tik() {
        let simdi = CACurrentMediaTime()
        let dt = CGFloat(min(0.1, max(0.001, simdi - sonTik)))
        sonTik = simdi
        zaman += Double(dt)
        let fare = NSEvent.mouseLocation

        // Claude penceresi kıpırdıyorsa sık, duruyorsa seyrek yoklanır
        let aralik: Double = baglam == .claude ? (simdi - sonCerceveDegisim < 2 ? 0.08 : 0.4) : 0.5
        if simdi - sonEvYoklama > aralik {
            sonEvYoklama = simdi
            evGuncelle()
        }

        kutuYokla(simdi)
        oneriDongusu(simdi)

        if !senaryo.isEmpty || ayar.double(forKey: "kapanSure") > 0 { senaryoIsle() }

        calisiyor = false
        switch mod {
        case .bekle:
            // Uzun süre dokunulmadıysa iş listesine başlar; Claude Code öndeyken uyanık kalır
            if !basili && !menuAcik && simdi - sonEtkilesim > bosSure && !(kodAcik && ipucuAcik) { listeyeBasla() }
        case .calis:
            calis(dt)
        case .oyun, .uyu:
            break
        }

        hareket(dt)

        // Sahne (iş listesi) Clawd'ın evini izler; uzak bir yere geçerken liste sönüp orada yeniden belirir
        let fark = (sahneEv - ev).uzunluk
        if fark > 0.5 {
            if liste.isEmpty || fark < 80 {
                sahneEv = ev
            } else {
                listeAlfa = max(0, listeAlfa - dt / 0.15)
                if listeAlfa <= 0 { sahneEv = ev }
            }
        } else if listeSoluyor {
            listeAlfa = max(0, listeAlfa - dt / 0.45)
            if listeAlfa <= 0 {
                liste.removeAll()
                listeSoluyor = false
                listeAlfa = 1
            }
        } else if listeAlfa < 1 && (konum - ev).uzunluk < 110 {
            listeAlfa = min(1, listeAlfa + dt / 0.3)
        }

        // Parçacıklar
        if !parcalar.isEmpty {
            for i in parcalar.indices {
                parcalar[i].yas += dt
                parcalar[i].konum = parcalar[i].konum + parcalar[i].hiz * dt
                parcalar[i].hiz = parcalar[i].hiz * (1 - 1.4 * dt)
            }
            parcalar.removeAll { $0.yas >= $0.omur }
        }

        // Konuşma balonu
        if balonAcik {
            balonYas += dt
            if balonYas >= balonOmur { balonAcik = false }
        }

        pozHazirla(dt, fare)

        // Fare yalnızca Clawd'ın üstündeyken pencere tıklamayı yakalar; başka yerde alttaki uygulamaya geçer
        let uzak = fare - konum
        let duyarli = (abs(uzak.x) < 22 * S && abs(uzak.y) < 15 * S) || basili || menuAcik
        if karakterPencere.ignoresMouseEvents == duyarli { karakterPencere.ignoresMouseEvents = !duyarli }

        pencereleriYerlestir()
        karakterGorunum.guncelle(poz: poz, kayma: cizimKayma, S: S)
        let uykuGorunur = uyuyor && mutluluk <= 0
        if uykuGorunur || uykuCizili {
            karakterGorunum.ust.setNeedsDisplay()
            uykuCizili = uykuGorunur
        }
        sahneGuncelle()

        let hareketli = surukleniyor || mod == .oyun || hiz.uzunluk > 6 || !parcalar.isEmpty || takla > 0
            || (balonAcik && (balonYas < 0.3 || balonYas > balonOmur - 0.6))
        fpsAyarla(hareketli ? 60 : (uyuyor ? 10 : 30))

        if ayar.bool(forKey: "gunluk") && simdi - sonGunluk > 1 {
            sonGunluk = simdi
            let dolu = liste.map { String(format: "%.1f", Double($0.dolu)) }.joined(separator: ",")
            let kutu = kutuGoreli.map { "\(Int($0.minX)),\(Int($0.minY)),\(Int($0.width)),\(Int($0.height))" } ?? "yok"
            let pencere = claudeCerceve.map { "\(Int($0.minX)),\(Int($0.minY)),\(Int($0.width)),\(Int($0.height))" } ?? "yok"
            let balon = balonAcik ? "\"\(balonBaslik.isEmpty ? balonSatirlar.joined(separator: " ") : balonBaslik)\"" : "yok"
            gunlukYaz("mod=\(mod.rawValue) baglam=\(baglam.rawValue) claudeOnde=\(kodAcik) konum=(\(Int(konum.x)),\(Int(konum.y))) ev=(\(Int(ev.x)),\(Int(ev.y))) satir=\(aktifSatir) liste=[\(dolu)] balon=\(balon) fps=\(Int(guncelFps)) uyuyor=\(uyuyor) on=\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "-") izin=\(izinVar) kutu=\(kutuDurum) kutuGoreli=\(kutu) pencere=\(pencere)")
        }
    }

    /// Günlük satırı: -gunlukDosya verilmişse o dosyaya (en çok 4000 satır), yoksa çıktıya yazılır.
    func gunlukYaz(_ s: String) {
        guard let yol = ayar.string(forKey: "gunlukDosya") else {
            print(s)
            fflush(stdout)
            return
        }
        guard gunlukSayac < 4000, let veri = (s + "\n").data(using: .utf8) else { return }
        gunlukSayac += 1
        if let h = FileHandle(forWritingAtPath: yol) {
            h.seekToEndOfFile()
            h.write(veri)
            h.closeFile()
        } else {
            try? veri.write(to: URL(fileURLWithPath: yol))
        }
    }

    // MARK: Mesaj kutusunu izleme

    /// Son ölçüm tazeyse ya da pencere boyutu o zamandan beri değişmediyse yazı alanının ekrandaki yeri.
    func gecerliKutu(_ w: CGRect) -> CGRect? {
        guard kutuIzle, izinVar, let g = kutuGoreli else { return nil }
        guard CACurrentMediaTime() - kutuZamani < 3 || kutuBoyut == w.size else { return nil }
        return g.offsetBy(dx: w.minX, dy: w.minY)
    }

    func kutuYokla(_ simdi: Double) {
        guard kutuIzle, baglam == .claude, let w = claudeCerceve, claudePid != 0 else { return }
        if simdi - sonIzinYoklama > 2 {
            sonIzinYoklama = simdi
            izinVar = KutuIzleyici.izinVar
        }
        guard izinVar else { return }
        // Pencere ya da kutu kıpırdıyorsa sık, duruyorsa seyrek sorulur
        let aralik: Double = (simdi - sonKutuDegisim < 2 || simdi - sonCerceveDegisim < 2) ? 0.1 : 0.5
        guard simdi - sonKutuYoklama > aralik else { return }
        sonKutuYoklama = simdi
        let anaYukseklik = NSScreen.screens.first?.frame.height ?? 0
        let solUst = CGRect(x: w.minX, y: anaYukseklik - w.maxY, width: w.width, height: w.height)
        izleyici.yokla(pid: claudePid, pencere: solUst) { [weak self] sonuc, durum in
            guard let s = self else { return }
            s.kutuDurum = durum
            if durum == "bekliyor" { return }      // yeni arama zamanı gelmedi; eldeki sonuç korunur
            let yeni = sonuc.map {
                CGRect(x: $0.minX - w.minX, y: (anaYukseklik - $0.maxY) - w.minY, width: $0.width, height: $0.height)
            }
            if yeni != s.kutuGoreli { s.sonKutuDegisim = CACurrentMediaTime() }
            s.kutuGoreli = yeni
            s.kutuBoyut = w.size
            s.kutuZamani = CACurrentMediaTime()
            s.ev = s.evNoktasi()
        }
    }

    func sahneGuncelle() {
        let ko = sahnePencere.frame.origin
        sahneGorunum.guncelle(satirlar: liste, merkez: listeMerkez(sahneEv) - ko, S: S, alfa: liste.isEmpty ? 0 : listeAlfa)
        if !parcalar.isEmpty || parcaCizili {
            sahneGorunum.parcaKatman.setNeedsDisplay()
            parcaCizili = !parcalar.isEmpty
        }
        guard balonAcik else {
            sahneGorunum.balonGizle()
            return
        }
        // Balon başının üstünde durur ve yürürken peşinden gelir; üstte yer yoksa (Clawd menü çubuğundaysa) altına iner
        let govde = konum + cizimKayma
        let ekran = (NSScreen.screens.first(where: { $0.frame.contains(konum) }) ?? anaEkran())?.frame
            ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let asagi = govde.y + 16 * S + Balon.kuyruk + balonOlcu.height + 4 > ekran.maxY
        let uc = govde + CGPoint(x: 0, y: asagi ? -15 * S : 16 * S)
        // Kutu ucun hizasında ortalanır; ekrandan taşacaksa yana kayar (kuyruk kutunun köşesinden çıkamaz)
        var sol = uc.x - balonOlcu.width / 2
        sol = sinirla(sol, ekran.minX + 4, max(ekran.minX + 4, ekran.maxX - 4 - balonOlcu.width))
        let kenar = Balon.kose + Balon.kuyruk
        sol = sinirla(sol, uc.x - (balonOlcu.width - kenar), uc.x - kenar)
        let buyume = geriSekme(min(1, balonYas / 0.2))
        let alfa = balonYas > balonOmur - 0.5 ? max(0, (balonOmur - balonYas) / 0.5) : 1
        sahneGorunum.balonGoster(baslik: balonBaslik, satirlar: balonSatirlar, olcu: balonOlcu, uc: uc - ko,
                                 kutuSol: (sol - ko.x).rounded(), asagi: asagi, buyume: buyume, alfa: alfa)
    }

    /// Clawd'ı hedefine doğru yürütür: sıradaki koşu noktasına, yoksa evine.
    func hareket(_ dt: CGFloat) {
        if surukleniyor || menuAcik { return }   // menü açıkken yerinde durur
        var hedef = ev
        var son = true
        var azami: CGFloat = 900
        if let ilk = hedefler.first {
            hedef = ilk
            son = hedefler.count == 1
            azami = 430
        }
        let d = hedef - konum
        let uz = d.uzunluk
        let surat = son ? min(azami, uz * 5.5) : azami
        let istenen = d.birim * surat
        let k = 1 - exp(-dt * (son ? 7 : 4.5))
        hiz = hiz + (istenen - hiz) * k
        if uz < 0.3 && hiz.uzunluk < 2 {
            konum = hedef
            hiz = .zero
        } else {
            konum = konum + hiz * dt
        }
        if !hedefler.isEmpty && uz < (son ? 5 : 32) {
            hedefler.removeFirst()
            if hedefler.isEmpty && mod == .oyun {
                mod = .bekle
                inis = 1
            }
        }
    }

    func pozHazirla(_ dt: CGFloat, _ fare: CGPoint) {
        let surat = hiz.uzunluk
        uyuyor = mod == .uyu && (konum - ev).uzunluk < 5 && surat < 6 && !surukleniyor

        faz += dt * 2 * .pi * (surukleniyor ? 15 : (surat > 60 ? 13 : 9))
        if faz > 1000 { faz -= 1000 }
        // Adımlar gidilen yolla ilerler; tutulup taşınırken bacakları havada çırpınır
        let kosu: CGFloat = surukleniyor ? 1 : min(1, surat / 45)
        adimFaz += dt * (surukleniyor ? 26 : min(surat, 460) * 0.085)
        if adimFaz > 200 * .pi { adimFaz -= 200 * .pi }

        let hedefEgim = -sinirla(hiz.x / 520, -1, 1) * 0.36
        egim += (hedefEgim - egim) * (1 - exp(-dt * 10))
        var toplamEgim = egim
        if takla > 0 {
            takla = max(0, takla - dt / 0.55)
            let t = 1 - takla
            toplamEgim += taklaYon * 2 * .pi * (t * t * (3 - 2 * t))
        }
        if calisiyor { toplamEgim += sin(CGFloat(zaman) * 16) * 0.035 }      // yazarken hafifçe titrer

        mutluluk = max(0, mutluluk - dt)
        inis = max(0, inis - dt / 0.35)

        // Bakış: koşarken gittiği yöne, yazarken listeye, dururken fareye
        var hedefBakis = CGPoint.zero
        if surat > 50 {
            hedefBakis = hiz.birim
        } else if calisiyor, aktifSatir < liste.count {
            hedefBakis = (listeMerkez(ev) + liste[aktifSatir].ofset * S - konum).birim
        } else if !uyuyor {
            let d = fare - konum
            hedefBakis = d.birim * min(1, d.uzunluk / 90)
        }
        bakis = bakis + (hedefBakis - bakis) * (1 - exp(-dt * 12))

        var kirpma: CGFloat = 0
        if zaman > sonrakiKirpma {
            let t = (zaman - sonrakiKirpma) / 0.16
            if t >= 1 { sonrakiKirpma = zaman + Double(rastgele(2.2, 5.5)) } else { kirpma = sin(CGFloat(t) * .pi) }
        }

        var p = Poz()
        p.egim = toplamEgim
        p.bakis = bakis
        p.kirpma = kirpma
        if surukleniyor {
            p.yuz = .saskin
        } else if mutluluk > 0 {
            p.yuz = .mutlu
        } else if uyuyor {
            p.yuz = .uyku
        }
        // Kollar: sevinince sırayla havaya kalkar, şaşırınca ikisi de kalkar, yazarken sırayla tuşlara iner
        switch p.yuz {
        case .saskin:
            p.kolSol = 5
            p.kolSag = 5
        case .mutlu:
            p.kolSol = 2.5 + 2.5 * sin(faz * 0.12)
            p.kolSag = 2.5 - 2.5 * sin(faz * 0.12)
        case .uyku:
            break
        case .normal:
            if calisiyor {
                p.kolSol = -1.8 * sin(faz * 0.2)
                p.kolSag = 1.8 * sin(faz * 0.2)
            } else {
                let salinim = sinirla(-hiz.x / 300, -1.2, 1.2) * 0.6
                p.kolSol = salinim
                p.kolSag = -salinim
            }
        }
        // Bacaklar: yürürken çiftler sırayla kalkar
        p.bacak = (0..<4).map { i in kosu * max(0, sin(adimFaz + (i % 2 == 0 ? 0 : .pi))) * 2.8 }

        if uyuyor {
            p.ezme = sin(CGFloat(zaman) * 1.7) * 0.03
        } else if inis > 0 {
            p.ezme = sin(inis * .pi) * 0.10
        } else if mutluluk > 0.9 && mutluluk <= 1.3 {
            p.ezme = -sin((1.3 - mutluluk) / 0.4 * .pi) * 0.08
        } else {
            p.ezme = sin(CGFloat(zaman) * 2.2) * 0.018        // dururken soluk alıp verir
        }
        poz = p

        // Yürürken adım adım hafifçe yükselir
        var kayma = CGPoint.zero
        if !surukleniyor { kayma.y += abs(sin(adimFaz)) * 1.4 * S * kosu }
        cizimKayma = kayma
    }

    func pencereleriYerlestir() {
        let k = karakterKenar
        let o = CGPoint(x: ((konum.x - k / 2) * 2).rounded() / 2, y: ((konum.y - k / 2) * 2).rounded() / 2)
        if karakterPencere.frame.origin != o { karakterPencere.setFrameOrigin(o) }
        let b = sahneBoyut
        let so = CGPoint(x: (sahneEv.x - b.width / 2).rounded(), y: (sahneEv.y - b.height / 2).rounded())
        if sahnePencere.frame.origin != so { sahnePencere.setFrameOrigin(so) }
    }

    // MARK: Deneme kancaları (yalnızca komut satırından): -kapanSure 30 -senaryo "8:tikla,20:liste"

    var senaryo: [(Double, String)] = []

    func senaryoOku() {
        guard let s = ayar.string(forKey: "senaryo") else { return }
        for parca in s.split(separator: ",") {
            let ikili = parca.split(separator: ":")
            if ikili.count == 2, let t = Double(ikili[0]) { senaryo.append((t, String(ikili[1]))) }
        }
    }

    func senaryoIsle() {
        while let ilk = senaryo.first, zaman >= ilk.0 {
            senaryo.removeFirst()
            print("senaryo: \(ilk.1)")
            switch ilk.1 {
            case "tikla": tiklandi()
            case "liste": simdiListeYap()
            case "ipucu": simdiOneriVer()
            case "goruntu": pencereGoruntusu()
            default: break
            }
        }
        let kapan = ayar.double(forKey: "kapanSure")
        if kapan > 0 && zaman > kapan { NSApp.terminate(nil) }
    }

    /// Canlı pencerelerin katman ağacını resme çevirir (deneme için): -goruntuYolu ile verilen klasöre yazar.
    func pencereGoruntusu() {
        guard let klasor = ayar.string(forKey: "goruntuYolu") else { return }
        CATransaction.flush()
        for (ad, v) in [("karakter", karakterGorunum as NSView), ("sahne", sahneGorunum as NSView)] {
            guard let l = v.layer else { continue }
            let img = goruntuUret(genislik: v.bounds.width, yukseklik: v.bounds.height, piksel: 3) { c in
                c.setFillColor(renk(245, 244, 240))
                c.fill(v.bounds)
                l.render(in: c)
            }
            if let img = img {
                let rep = NSBitmapImageRep(cgImage: img)
                let yol = "\(klasor)/\(ad)-\(Int(zaman * 10)).png"
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: yol))
            }
        }
    }
}
