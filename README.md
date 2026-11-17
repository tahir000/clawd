# Clawd (Windows)

Ekranda duran minik bir masaüstü karakteri. Claude Code'un açılış ekranındaki turuncu piksel karakterden (Clawd) esinlenen, **resmi olmayan** bir hayran çalışmasıdır.

![Clawd'ın yüz ifadeleri, iş listesi, sözleri ve komut önerileri](onizleme.png)

## Ne yapar

- **Tıklayınca** sevinir, konsol görünümlü bir balonda bir söz söyler ve yana yana koşup geri gelir.
- **Claude öndeyken** arada bir Claude Code komutu ya da kısayolu önerir. Örneğin `/compact`: "Konuşmayı özetleyip bağlamda yer açar."
- **3 dakika dokunmazsan** yanında bir iş listesi açar, satırları yazıp işaretler ve bitince uyur. Claude öndeyken uyumaz.
- **Sürükleyince** bıraktığın yeri hatırlar.
- **Sağ tık menüsünden** hemen bir öneri isteyebilir, önerileri kapatabilir, sıklığını ve boyutunu seçebilir, bilgisayar açılınca başlamasını sağlayabilirsin.

Görev çubuğunun üstünde, saatin solunda durur. Claude uygulaması öndeyse mesaj kutusunun üstüne çıkar.

## Durum

Program bir Mac'te çapraz derlendi ve çizimleri orada denetlendi. **Gerçek bir Windows bilgisayarda henüz denenmedi.** Pencere davranışı, önerilerin zamanlaması ve balonun yeri Windows'ta farklı çıkabilir. Bir sorun görürsen `tanilama.bat` ile günlük alıp bir kayıt açabilirsin.

## Kurulum

1. Depoyu indir (Code, Download ZIP) ve klasörü kalıcı bir yere koy.
2. `Clawd.exe` dosyasına çift tıkla.

Windows "bilinmeyen yayıncı" uyarısı verirse "Ek bilgi" yazısına, sonra "Yine de çalıştır" düğmesine bas. Hazır `Clawd.exe` dosyasına güvenmek istemezsen `derle.bat` dosyasına çift tıkla: programı senin bilgisayarında `Clawd.cs` kaynağından yeniden derler. Windows 10 ve 11'in içindeki C# derleyicisini kullanır, ayrıca bir şey kurmak gerekmez.

Kaldırmak için Clawd'a sağ tıklayıp "Clawd'ı kapat" de ve klasörü sil. Ayarlar `%APPDATA%\Clawd` klasöründe durur.

## Öneriler nereden geliyor

45 öneri var: 30 komut, 15 kısayol ve giriş kolaylığı. Hepsi Claude Code'un resmi belgelerinden alındı ([commands](https://code.claude.com/docs/en/commands), [interactive mode](https://code.claude.com/docs/en/interactive-mode); Kasım 2026). Komutlar sürümle değişebilir. Bir komut sende yoksa `/help` güncel listeyi gösterir.

## "Claude önde" nasıl anlaşılıyor

Bu bir tahmindir. Clawd şu iki durumda öneri verir:

- Öndeki pencere Claude uygulamasıysa.
- Öndeki pencere bir terminalse (Windows Terminal, cmd, PowerShell, VS Code gibi) ve başlığında "claude" geçiyorsa ya da bilgisayarda bir `claude` süreci çalışıyorsa.

Claude arka planda açıkken başka bir iş için terminal kullanırsan da öneri çıkabilir.

Mesaj kutusunun yerini bulmak için Windows'un UI Automation arayüzü kullanılır. Yalnızca öğe türü ve çerçeve okunur; yazdıkların okunmaz, hiçbir şeye basılmaz. Program internete bağlanmaz.

## Dosyalar

| Dosya | Ne |
| --- | --- |
| `Clawd.cs` | Programın bütün kaynağı (C# 5, .NET Framework 4.8, WinForms) |
| `Clawd.exe` | Derlenmiş program |
| `Clawd.ico` | Simge |
| `derle.bat` | Windows'ta yeniden derler ve başlatır |
| `tanilama.bat` | Günlük tutarak başlatır (`clawd-gunluk.txt`) |
| `derle-mac.sh` | macOS ya da Linux'ta çapraz derleme |
| `LICENSE` | MIT lisansı |

## Lisans ve yasal not

Bu depodaki kod [MIT lisansı](LICENSE) ile sunulur.

Lisans yalnız kodu kapsar. Clawd, Claude Code'un maskotudur; Claude, Claude Code ve Clawd Anthropic'e aittir ve bu lisansın kapsamında değildir. Bu depo Anthropic ile bağlantılı değildir ve Anthropic tarafından onaylanmamıştır. Karakter Claude Code'un açılış ekranındaki blok harflerden yola çıkılarak kodla yeniden çizildi.

Kod Claude Code ile birlikte yazıldı.
