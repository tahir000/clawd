import Cocoa

// Clawd: ekranda duran minik masaüstü karakteri (Claude Code'un maskotundan esinlenen hayran çalışması).
//   Clawd                       uygulamayı başlatır
//   Clawd --simge dosya.png     uygulama simgesini çizer
//   Clawd --goruntu dosya.png   çizimlerin toplu önizlemesini kaydeder

func bitmapCiz(genislik: Int, yukseklik: Int, carpan: CGFloat, yol: String, _ ciz: (CGContext) -> Void) {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(CGFloat(genislik) * carpan), pixelsHigh: Int(CGFloat(yukseklik) * carpan),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let g = NSGraphicsContext(bitmapImageRep: rep) else { return }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = g
    let c = g.cgContext
    c.scaleBy(x: carpan, y: carpan)
    ciz(c)
    NSGraphicsContext.restoreGraphicsState()
    if let veri = rep.representation(using: .png, properties: [:]) {
        try? veri.write(to: URL(fileURLWithPath: yol))
    }
}

func simgeKaydet(_ yol: String) {
    bitmapCiz(genislik: 1024, yukseklik: 1024, carpan: 1, yol: yol) { c in
        let kutu = CGRect(x: 100, y: 100, width: 824, height: 824)
        let yuvarlak = CGPath(roundedRect: kutu, cornerWidth: 186, cornerHeight: 186, transform: nil)
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: renk(0, 0, 0, 0.28))
        c.addPath(yuvarlak)
        c.setFillColor(renk(38, 36, 34))
        c.fillPath()
        c.restoreGState()
        c.saveGState()
        c.addPath(yuvarlak)
        c.clip()
        if let uzay = CGColorSpace(name: CGColorSpace.sRGB),
           let g = CGGradient(colorsSpace: uzay, colors: [renk(50, 47, 44), renk(26, 24, 22)] as CFArray, locations: [0, 1]) {
            c.drawLinearGradient(g, start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
        }
        c.restoreGState()
        clawdTam(c, merkez: CGPoint(x: 512, y: 512), olcek: 16.5, poz: Poz())
    }
}

/// Balonu, kuyruğunun ucu `uc` noktasına gelecek biçimde çizer (önizleme için).
func balonOnizle(_ c: CGContext, uc: CGPoint, baslik: String, metin: String, asagi: Bool = false) {
    let satirlar = sar(metin, 36)
    let olcu = Balon.olcu(baslik: baslik, satirlar: satirlar)
    let kutu = CGRect(x: uc.x - olcu.width / 2, y: asagi ? uc.y - Balon.kuyruk - olcu.height : uc.y + Balon.kuyruk,
                      width: olcu.width, height: olcu.height)
    Balon.ciz(c, kutu: kutu, ucX: uc.x, asagi: asagi, baslik: baslik, satirlar: satirlar)
}

func goruntuKaydet(_ yol: String) {
    bitmapCiz(genislik: 960, yukseklik: 560, carpan: 2, yol: yol) { c in
        c.setFillColor(renk(250, 249, 245))
        c.fill(CGRect(x: 0, y: 0, width: 480, height: 560))
        c.setFillColor(renk(38, 38, 36))
        c.fill(CGRect(x: 480, y: 0, width: 480, height: 560))
        for xo in [CGFloat(0), 480] {
            // Üst sıra: yüz ifadeleri
            var p = Poz()
            clawdTam(c, merkez: CGPoint(x: xo + 65, y: 500), olcek: 2.2, poz: p)
            p.yuz = .mutlu
            p.kolSol = 5
            p.kolSag = 0.5
            clawdTam(c, merkez: CGPoint(x: xo + 180, y: 500), olcek: 2.2, poz: p)
            p = Poz()
            p.yuz = .saskin
            p.kolSol = 5
            p.kolSag = 5
            clawdTam(c, merkez: CGPoint(x: xo + 295, y: 500), olcek: 2.2, poz: p)
            p = Poz()
            p.yuz = .uyku
            clawdTam(c, merkez: CGPoint(x: xo + 410, y: 500), olcek: 2.2, poz: p)
            uykuHarfleri(merkez: CGPoint(x: xo + 410, y: 500), olcek: 2.2, zaman: 0.5)

            // İkinci sıra: yana bakış, göz kırpma, yürürken, yazarken
            p = Poz()
            p.bakis = CGPoint(x: -1, y: -0.4)
            clawdTam(c, merkez: CGPoint(x: xo + 65, y: 410), olcek: 2.2, poz: p)
            p = Poz()
            p.kirpma = 0.85
            clawdTam(c, merkez: CGPoint(x: xo + 180, y: 410), olcek: 2.2, poz: p)
            p = Poz()
            p.egim = -0.12
            p.bakis = CGPoint(x: 1, y: 0)
            p.bacak = [2.6, 0, 2.6, 0]
            clawdTam(c, merkez: CGPoint(x: xo + 295, y: 410), olcek: 2.2, poz: p)
            p = Poz()
            p.bakis = CGPoint(x: -1, y: -0.2)
            p.kolSol = -1.6
            p.kolSag = 1.6
            clawdTam(c, merkez: CGPoint(x: xo + 410, y: 410), olcek: 2.2, poz: p)

            // Gerçek boyut (0,85): iş listesinin aşamaları ve üç boyut
            let s: CGFloat = 0.85
            var g1 = gorevDizilimi().map { Satir(ofset: $0) }
            g1[0].belirme = 1; g1[0].dolu = 1
            g1[1].belirme = 1; g1[1].dolu = 1
            g1[2].belirme = 1; g1[2].dolu = 0.5
            g1[3].belirme = 0.6
            gorevCiz(c, merkez: CGPoint(x: xo + 75 - 39 * s, y: 322 + 4.5 * s), olcek: s, satirlar: g1, alfa: 1)
            p = Poz()
            p.bakis = CGPoint(x: -1, y: -0.1)
            p.kolSol = 1.6
            p.kolSag = -1.6
            clawdTam(c, merkez: CGPoint(x: xo + 75, y: 322), olcek: s, poz: p)
            let g2 = gorevDizilimi().map { Satir(ofset: $0, belirme: 1, dolu: 1) }
            gorevCiz(c, merkez: CGPoint(x: xo + 185 - 39 * s, y: 322 + 4.5 * s), olcek: s, satirlar: g2, alfa: 1)
            p = Poz()
            p.yuz = .uyku
            clawdTam(c, merkez: CGPoint(x: xo + 185, y: 322), olcek: s, poz: p)
            uykuHarfleri(merkez: CGPoint(x: xo + 185, y: 322), olcek: s, zaman: 0.5)
            for (i, o) in [CGFloat(0.7), 0.85, 1.1].enumerated() {
                clawdTam(c, merkez: CGPoint(x: xo + 290 + CGFloat(i) * 62, y: 320), olcek: o, poz: Poz())
            }
            var yildiz = Parca(tur: .yildiz, konum: CGPoint(x: xo + 255, y: 330), hiz: .zero, omur: 1, boyut: 3.6)
            yildiz.yas = 0.3
            parcaCiz(c, yildiz, kayma: .zero)
            var yazi = Parca(tur: .yazi("+5"), konum: CGPoint(x: xo + 240, y: 350), hiz: .zero, omur: 1, boyut: 12)
            yazi.yas = 0.3
            parcaCiz(c, yazi, kayma: .zero)

            // Söz balonu ve menü çubuğundayken aşağı açılan balon
            p = Poz()
            p.yuz = .mutlu
            p.kolSol = 4
            p.kolSag = 1
            clawdTam(c, merkez: CGPoint(x: xo + 110, y: 215), olcek: s, poz: p)
            balonOnizle(c, uc: CGPoint(x: xo + 110, y: 215 + 16 * s), baslik: "", metin: "Merhaba! Bugün ne yazıyoruz?")
            clawdTam(c, merkez: CGPoint(x: xo + 360, y: 268), olcek: s, poz: Poz())
            balonOnizle(c, uc: CGPoint(x: xo + 360, y: 268 - 15 * s), baslik: "/plan",
                        metin: "Plan moduna girer. Örnek: /plan giriş hatasını düzelt", asagi: true)

            // Komut ve kısayol önerileri
            clawdTam(c, merkez: CGPoint(x: xo + 110, y: 30), olcek: s, poz: Poz())
            balonOnizle(c, uc: CGPoint(x: xo + 122, y: 30 + 16 * s), baslik: "/compact",
                        metin: "Konuşmayı özetleyip bağlamda yer açar. Konuşma kaldığı yerden sürer.")
            p = Poz()
            p.bakis = CGPoint(x: -0.6, y: 0.4)
            clawdTam(c, merkez: CGPoint(x: xo + 370, y: 30), olcek: s, poz: p)
            balonOnizle(c, uc: CGPoint(x: xo + 360, y: 30 + 16 * s), baslik: "Esc Esc",
                        metin: "Giriş boşken geri sarma menüsünü açar. Yazı varsa taslağı temizler.")
        }
    }
}

let argumanlar = CommandLine.arguments
if let i = argumanlar.firstIndex(of: "--simge"), i + 1 < argumanlar.count {
    simgeKaydet(argumanlar[i + 1])
    exit(0)
}
if let i = argumanlar.firstIndex(of: "--goruntu"), i + 1 < argumanlar.count {
    goruntuKaydet(argumanlar[i + 1])
    exit(0)
}

let uygulama = NSApplication.shared
let temsilci = Uygulama()
uygulama.delegate = temsilci
uygulama.setActivationPolicy(.accessory)
uygulama.run()
