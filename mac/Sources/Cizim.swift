import Cocoa

// MARK: - Küçük yardımcılar

extension CGPoint {
    static func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
    static func - (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x - b.x, y: a.y - b.y) }
    static func * (a: CGPoint, k: CGFloat) -> CGPoint { CGPoint(x: a.x * k, y: a.y * k) }
    var uzunluk: CGFloat { (x * x + y * y).squareRoot() }
    var birim: CGPoint {
        let u = uzunluk
        return u < 0.0001 ? .zero : CGPoint(x: x / u, y: y / u)
    }
}

func sinirla(_ v: CGFloat, _ a: CGFloat, _ b: CGFloat) -> CGFloat { min(max(v, a), b) }
func rastgele(_ a: CGFloat, _ b: CGFloat) -> CGFloat { CGFloat.random(in: a...b) }

func renk(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func nsRenk(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

/// Hafif taşarak yerine oturan büyüme eğrisi.
func geriSekme(_ t: CGFloat) -> CGFloat {
    let c1: CGFloat = 1.70158
    let c3 = c1 + 1
    let u = sinirla(t, 0, 1) - 1
    return 1 + c3 * u * u * u + c1 * u * u
}

/// Bir çizimi bir kez yapıp katmana koymak için küçük resim üretir. Ölçüler birim, `piksel` birim başına piksel.
func goruntuUret(genislik: CGFloat, yukseklik: CGFloat, piksel: CGFloat, _ ciz: (CGContext) -> Void) -> CGImage? {
    let w = Int((genislik * piksel).rounded(.up))
    let h = Int((yukseklik * piksel).rounded(.up))
    guard w > 0, h > 0, let uzay = CGColorSpace(name: CGColorSpace.sRGB),
          let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: uzay,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    c.scaleBy(x: piksel, y: piksel)
    ciz(c)
    return c.makeImage()
}

/// Yazı çizimi AppKit ile yapılır; bunun için bağlamın geçerli çizim bağlamı olması gerekir.
func yaziBaglaminda(_ c: CGContext, _ ciz: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: false)
    ciz()
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Clawd

enum Yuz { case normal, mutlu, saskin, uyku }

/// Karakterin bir karedeki duruşu.
struct Poz {
    var egim: CGFloat = 0             // radyan
    var bakis: CGPoint = .zero        // -1...1
    var kirpma: CGFloat = 0           // 0 açık, 1 kapalı
    var yuz: Yuz = .normal
    var ezme: CGFloat = 0             // artı: basık ve geniş
    var kolSol: CGFloat = 0           // kolun yukarı kayması (birim)
    var kolSag: CGFloat = 0
    var bacak: [CGFloat] = [0, 0, 0, 0]   // bacakların yerden kalkması (birim), soldan sağa
}

enum Palet {
    static let turuncu = renk(215, 119, 87)
    static let goz = renk(34, 26, 24)
    static let yildiz = renk(255, 214, 70)
    static let yildizCizgi = renk(210, 132, 24)
}

/// Clawd: Claude Code'un açılış ekranındaki turuncu piksel karakter. Biçimi oradaki blok harflerden alındı:
/// 12 × 4 piksellik gövde, iki dik göz, yanlarda birer kol, altta dört bacak (bir piksel 2,5 × 5 birim).
/// Merkez (0,0), ölçek 1; ayakları -12,5 hizasındadır.
func clawdCiz(_ c: CGContext, poz p: Poz) {
    c.setFillColor(renk(30, 20, 10, 0.13))
    c.fillEllipse(in: CGRect(x: -15, y: -14.3, width: 30, height: 3.6))

    c.setFillColor(Palet.turuncu)
    // Bacaklar
    for (i, x) in [CGFloat(-12.5), -7.5, 5, 10].enumerated() {
        let kalk = i < p.bacak.count ? p.bacak[i] : 0
        c.fill(CGRect(x: x, y: -12.5 + kalk, width: 2.5, height: 5.6 - kalk))
    }
    // Kollar ve gövde
    c.fill(CGRect(x: -20, y: -2.5 + p.kolSol, width: 5.2, height: 5))
    c.fill(CGRect(x: 14.8, y: -2.5 + p.kolSag, width: 5.2, height: 5))
    c.fill(CGRect(x: -15, y: -7.6, width: 30, height: 20.1))

    // Gözler: iki dik dikdörtgen; bakışa göre kayar, kırpınca kısalır
    c.setFillColor(Palet.goz)
    for yon in [CGFloat(-1), 1] {
        let x = yon * 8.75 + p.bakis.x * 1.25
        let y = 5 + p.bakis.y * 1.0
        switch p.yuz {
        case .uyku:
            c.fill(CGRect(x: x - 2.5, y: 3.4, width: 5, height: 1.5))
        case .mutlu:
            // Gülen göz: ters U biçiminde üç parça
            c.fill(CGRect(x: x - 2.5, y: 5.7, width: 5, height: 1.9))
            c.fill(CGRect(x: x - 2.5, y: 3.8, width: 1.3, height: 1.9))
            c.fill(CGRect(x: x + 1.2, y: 3.8, width: 1.3, height: 1.9))
        case .normal, .saskin:
            let w: CGFloat = p.yuz == .saskin ? 3.75 : 2.5
            let h: CGFloat = (p.yuz == .saskin ? 6.25 : 5) * max(0.16, 1 - p.kirpma)
            c.fill(CGRect(x: x - w / 2, y: y - h / 2, width: w, height: h))
        }
    }
}

/// Bütün karakter tek seferde (simge ve önizleme için). Basılıp esnerken ayakları yerinde kalır.
func clawdTam(_ c: CGContext, merkez: CGPoint, olcek s: CGFloat, poz p: Poz) {
    c.saveGState()
    c.translateBy(x: merkez.x, y: merkez.y)
    c.rotate(by: p.egim)
    c.translateBy(x: 0, y: -12.5 * s * p.ezme)
    c.scaleBy(x: s * (1 + p.ezme), y: s * (1 - p.ezme))
    clawdCiz(c, poz: p)
    c.restoreGState()
}

// MARK: - Yazı (z harfleri, +N)

func yaziCiz(_ s: String, merkez: CGPoint, boy: CGFloat, dolgu: NSColor, kontur: NSColor) {
    var font = NSFont.systemFont(ofSize: boy, weight: .heavy)
    if let d = font.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: boy) { font = f }
    let dis: [NSAttributedString.Key: Any] = [.font: font, .strokeColor: kontur, .strokeWidth: 24.0, .foregroundColor: kontur]
    let ic: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: dolgu]
    let ns = s as NSString
    let b = ns.size(withAttributes: ic)
    let o = CGPoint(x: merkez.x - b.width / 2, y: merkez.y - b.height / 2)
    ns.draw(at: o, withAttributes: dis)
    ns.draw(at: o, withAttributes: ic)
}

/// Uyurken başının üstünden yükselen z harfleri.
func uykuHarfleri(merkez: CGPoint, olcek s: CGFloat, zaman: Double) {
    for i in 0..<3 {
        let f = CGFloat((zaman * 0.33 + Double(i) / 3).truncatingRemainder(dividingBy: 1))
        let boy = (6.5 + f * 5.5) * s
        let alfa = sin(f * .pi)
        let p = CGPoint(x: merkez.x + (14 + f * 11 + sin(f * 6) * 2) * s, y: merkez.y + (15 + f * 20) * s)
        yaziCiz("z", merkez: p, boy: boy, dolgu: nsRenk(102, 135, 242, alfa), kontur: nsRenk(255, 255, 255, alfa))
    }
}

// MARK: - İş listesi

/// İş listesinin bir satırı.
struct Satir {
    var ofset: CGPoint
    var belirme: CGFloat = 0
    var dolu: CGFloat = 0
}

/// Beş satırın merkezleri, üstten alta.
func gorevDizilimi() -> [CGPoint] {
    [8.5, 3.8, -0.9, -5.6, -10.3].map { CGPoint(x: 0, y: $0) }
}

let gorevBoylari: [CGFloat] = [19, 14, 21, 12, 17]

/// Konsol penceresi görünümlü iş listesi: satırlar sırayla belirir, yazılır (çizgi uzar) ve bitince kutusu
/// yeşil işaretlenir. Pencere yerden büyüyerek belirir. Merkez `merkez`, tabanı merkezin 17 birim altındadır.
func gorevCiz(_ c: CGContext, merkez: CGPoint, olcek s: CGFloat, satirlar: [Satir], alfa: CGFloat) {
    guard let ilk = satirlar.first, ilk.belirme > 0.001 else { return }
    let k = geriSekme(ilk.belirme)
    guard k > 0.02 else { return }
    c.saveGState()
    c.setAlpha(alfa)
    c.translateBy(x: merkez.x, y: merkez.y)
    c.scaleBy(x: s, y: s)
    c.translateBy(x: 0, y: -17)
    c.scaleBy(x: k, y: k)
    c.translateBy(x: 0, y: 17)

    let cerceve = CGRect(x: -16, y: -17, width: 32, height: 34)
    let pencere = CGPath(roundedRect: cerceve, cornerWidth: 2.6, cornerHeight: 2.6, transform: nil)
    c.addPath(pencere)
    c.setFillColor(renk(38, 36, 34))
    c.fillPath()
    c.saveGState()
    c.addPath(pencere)
    c.clip()
    c.setFillColor(renk(58, 55, 52))
    c.fill(CGRect(x: -16, y: 12.2, width: 32, height: 5))
    c.restoreGState()
    c.setFillColor(Palet.turuncu)
    c.fillEllipse(in: CGRect(x: -13.6, y: 13.8, width: 1.9, height: 1.9))
    c.setFillColor(renk(150, 146, 140))
    c.fillEllipse(in: CGRect(x: -10.8, y: 13.8, width: 1.9, height: 1.9))
    c.fillEllipse(in: CGRect(x: -8.0, y: 13.8, width: 1.9, height: 1.9))

    for (i, satir) in satirlar.enumerated() where satir.belirme > 0.001 {
        let y = satir.ofset.y
        let dolu = sinirla(satir.dolu, 0, 1)
        let bitti = satir.dolu >= 1
        // Onay kutusu
        c.setFillColor(bitti ? renk(98, 196, 120) : renk(150, 146, 140))
        c.fill(CGRect(x: -13.4, y: y - 1.5, width: 3, height: 3))
        if bitti {
            c.setStrokeColor(renk(255, 255, 255))
            c.setLineWidth(0.7)
            c.setLineCap(.round)
            c.move(to: CGPoint(x: -12.7, y: y - 0.1))
            c.addLine(to: CGPoint(x: -12.1, y: y - 0.8))
            c.addLine(to: CGPoint(x: -11.0, y: y + 0.8))
            c.strokePath()
        } else {
            c.setFillColor(renk(38, 36, 34))
            c.fill(CGRect(x: -12.8, y: y - 0.9, width: 1.8, height: 1.8))
        }
        // Satırın yazısı: yazıldıkça uzayan çizgi; biten satır soluklaşır
        let boy = gorevBoylari[i % gorevBoylari.count] * min(1, dolu / 0.85) * min(1, satir.belirme * 2)
        if boy > 0.3 {
            c.setFillColor(bitti ? renk(120, 116, 110) : (dolu > 0 ? Palet.turuncu : renk(206, 202, 194)))
            c.fill(CGRect(x: -8.4, y: y - 0.8, width: boy, height: 1.6))
        } else {
            c.setFillColor(renk(120, 116, 110))
            c.fill(CGRect(x: -8.4, y: y - 0.8, width: 1.2, height: 1.6))
        }
    }
    c.addPath(pencere)
    c.setStrokeColor(renk(104, 98, 92))
    c.setLineWidth(1.1)
    c.strokePath()
    c.restoreGState()
}

// MARK: - Parçacıklar

enum ParcaTur {
    case yildiz
    case yazi(String)
}

/// Havada uçuşan küçük parça: liste toplanınca saçılan yıldız ya da "+5" yazısı.
struct Parca {
    var tur: ParcaTur
    var konum: CGPoint          // ekran koordinatı
    var hiz: CGPoint
    var omur: CGFloat
    var boyut: CGFloat
    var yas: CGFloat = 0
    var donus: CGFloat = 0
}

func yildizYolu(merkez m: CGPoint, r: CGFloat, donus: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<8 {
        let a = donus + CGFloat(i) * .pi / 4
        let rr = i % 2 == 0 ? r : r * 0.36
        let q = CGPoint(x: m.x + cos(a) * rr, y: m.y + sin(a) * rr)
        if i == 0 { p.move(to: q) } else { p.addLine(to: q) }
    }
    p.closeSubpath()
    return p
}

/// `kayma`: çizilen pencerenin ekran üzerindeki sol alt köşesi.
func parcaCiz(_ c: CGContext, _ p: Parca, kayma: CGPoint) {
    let t = p.yas / p.omur
    let alfa = t < 0.6 ? 1 : max(0, 1 - (t - 0.6) / 0.4)
    let buyume = min(1, t / 0.15)
    let m = p.konum - kayma
    c.saveGState()
    c.setAlpha(alfa)
    c.setLineJoin(.round)
    switch p.tur {
    case .yildiz:
        c.addPath(yildizYolu(merkez: m, r: p.boyut * buyume, donus: p.donus + t * 2))
        c.setFillColor(Palet.yildiz)
        c.setStrokeColor(Palet.yildizCizgi)
        c.setLineWidth(0.8)
        c.drawPath(using: .fillStroke)
    case .yazi(let s):
        yaziCiz(s, merkez: m, boy: p.boyut, dolgu: nsRenk(237, 140, 5, alfa), kontur: nsRenk(255, 255, 255, alfa))
    }
    c.restoreGState()
}

// MARK: - Konuşma balonu

/// Uzun bir cümleyi, her satırı en çok `azami` harf olacak biçimde sözcük aralarından böler.
func sar(_ metin: String, _ azami: Int) -> [String] {
    var satirlar: [String] = []
    var satir = ""
    for sozcuk in metin.split(separator: " ") {
        if !satir.isEmpty && satir.count + 1 + sozcuk.count > azami {
            satirlar.append(satir)
            satir = String(sozcuk)
        } else {
            satir = satir.isEmpty ? String(sozcuk) : satir + " " + sozcuk
        }
    }
    if !satir.isEmpty { satirlar.append(satir) }
    return satirlar
}

/// Konsol görünümlü konuşma balonu: koyu kutu, turuncu kenar. `baslik` doluysa en üstte eş aralıklı yazıyla
/// (komut ya da kısayol) yazılır; altında açıklama satırları durur.
enum Balon {
    static let dolgu: CGFloat = 9
    static let kuyruk: CGFloat = 6
    static let kose: CGFloat = 7
    static let satirYuk: CGFloat = 16
    static let baslikYuk: CGFloat = 18.5
    static let pay: CGFloat = 4          // gölge ve kenar çizgisi için resmin çevresinde bırakılan boşluk
    static var yaziFont: NSFont { NSFont.systemFont(ofSize: 12, weight: .regular) }
    static var baslikFont: NSFont { NSFont.monospacedSystemFont(ofSize: 13, weight: .bold) }

    /// Kutunun ölçüsü (kuyruk hariç).
    static func olcu(baslik: String, satirlar: [String]) -> CGSize {
        var gen: CGFloat = baslik.isEmpty ? 0 : (baslik as NSString).size(withAttributes: [.font: baslikFont]).width
        for s in satirlar { gen = max(gen, (s as NSString).size(withAttributes: [.font: yaziFont]).width) }
        let yuk = dolgu * 1.5 + (baslik.isEmpty ? 0 : baslikYuk) + CGFloat(satirlar.count) * satirYuk
        return CGSize(width: (gen + dolgu * 2).rounded(.up), height: yuk.rounded(.up))
    }

    /// Kutuyu `kutu` dikdörtgenine çizer. Kuyruğun ucu yatayda `ucX` noktasındadır; `asagi` ise balon
    /// karakterin altında durur ve kuyruk yukarı bakar, değilse kuyruk aşağı bakar.
    static func ciz(_ c: CGContext, kutu: CGRect, ucX: CGFloat, asagi: Bool, baslik: String, satirlar: [String]) {
        let yol = CGPath(roundedRect: kutu, cornerWidth: kose, cornerHeight: kose, transform: nil)
        c.saveGState()
        c.addPath(CGPath(roundedRect: kutu.offsetBy(dx: 1, dy: -2), cornerWidth: kose, cornerHeight: kose, transform: nil))
        c.setFillColor(renk(20, 12, 8, 0.16))
        c.fillPath()
        // Kuyruk
        let taban = asagi ? kutu.maxY - 1 : kutu.minY + 1
        let uc = asagi ? kutu.maxY + kuyruk : kutu.minY - kuyruk
        c.move(to: CGPoint(x: ucX - kuyruk, y: taban))
        c.addLine(to: CGPoint(x: ucX + kuyruk, y: taban))
        c.addLine(to: CGPoint(x: ucX, y: uc))
        c.closePath()
        c.setFillColor(Palet.turuncu)
        c.fillPath()
        c.addPath(yol)
        c.setFillColor(renk(36, 34, 32))
        c.fillPath()
        c.addPath(yol)
        c.setStrokeColor(Palet.turuncu)
        c.setLineWidth(1.5)
        c.strokePath()
        c.restoreGState()

        yaziBaglaminda(c) {
            let x = kutu.minX + dolgu * 0.9
            var ust = kutu.maxY - dolgu * 0.7
            if !baslik.isEmpty {
                let f = baslikFont
                (baslik as NSString).draw(at: CGPoint(x: x, y: ust - (f.ascender - f.descender)),
                                          withAttributes: [.font: f, .foregroundColor: nsRenk(238, 148, 116)])
                ust -= baslikYuk
            }
            let f = yaziFont
            for s in satirlar {
                (s as NSString).draw(at: CGPoint(x: x, y: ust - (f.ascender - f.descender)),
                                     withAttributes: [.font: f, .foregroundColor: nsRenk(240, 236, 228)])
                ust -= satirYuk
            }
        }
    }
}
