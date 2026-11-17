// Clawd (Windows): ekranda duran minik masaüstü karakteri. Claude Code'un açılış ekranındaki turuncu piksel
// karakterden (Clawd) esinlenen, resmi olmayan bir hayran çalışmasıdır.
//   - Tıklayınca konsol görünümlü bir balonda bir söz söyler ve yana yana koşup geri gelir.
//   - Claude öndeyken arada bir Claude Code komutu ya da kısayolu önerir.
//   - Boş kalınca yanındaki iş listesini yazıp işaretler, bitince uyur.
// Derleme: derle.bat (Windows'un içindeki C# derleyicisiyle). O derleyici eski olduğu için bu dosyada yalnızca
// C# 5 yazımı kullanılır. İç hesaplar "y yukarı doğru artar" düzeninde yapılır; ekrana basarken Windows'un
// "y aşağı doğru artar" düzenine çevrilir.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace Clawd
{
    // ------------------------------------------------------------------ küçük yardımcılar

    struct V
    {
        public float X, Y;
        public V(float x, float y) { X = x; Y = y; }
        public static V operator +(V a, V b) { return new V(a.X + b.X, a.Y + b.Y); }
        public static V operator -(V a, V b) { return new V(a.X - b.X, a.Y - b.Y); }
        public static V operator *(V a, float k) { return new V(a.X * k, a.Y * k); }
        public float Uzunluk { get { return (float)Math.Sqrt(X * X + Y * Y); } }
        public V Birim
        {
            get
            {
                float u = Uzunluk;
                return u < 0.0001f ? new V(0f, 0f) : new V(X / u, Y / u);
            }
        }
    }

    /// Ekranda bir dikdörtgen; y yukarı doğru artar (Y alt kenardır).
    struct Alan
    {
        public float X, Y, G, Yuk;
        public Alan(float x, float y, float g, float yuk) { X = x; Y = y; G = g; Yuk = yuk; }
        public float MinX { get { return X; } }
        public float MaxX { get { return X + G; } }
        public float MinY { get { return Y; } }
        public float MaxY { get { return Y + Yuk; } }
        public float MidX { get { return X + G / 2f; } }
        public bool Esit(Alan o) { return X == o.X && Y == o.Y && G == o.G && Yuk == o.Yuk; }
    }

    enum Yuz { Normal, Mutlu, Saskin, Uyku }
    enum Mod { Bekle, Oyun, Calis, Uyu }
    enum Baglam { Claude, Masaustu }

    /// Karakterin bir karedeki duruşu.
    class Poz
    {
        public float Faz;             // sürekli ilerleyen evre (kol sallama ve tuşlama bununla oynar)
        public float Egim;                 // radyan
        public V Bakis;                    // -1...1
        public float Kirpma;               // 0 açık, 1 kapalı
        public Yuz Yuz = Yuz.Normal;
        public float Ezme;                 // artı: basık ve geniş
        public float Salinim;                // kolların hafif salınımı
        public float Adim;                 // adım evresi (radyan)
        public float Kosu;                 // 0 duruyor, 1 koşuyor
        public bool Mesgul;                // iş listesini yazıyor (kollar sırayla tuşlara iner)
    }

    /// İş listesinin bir satırı.
    class Satir
    {
        public V Ofset;
        public float Belirme;
        public float Dolu;
    }

    /// Havada uçuşan küçük parça: liste toplanınca saçılan yıldız ya da "+5" yazısı.
    class Parca
    {
        public const int Yildiz = 0, Yazi = 1;
        public int Tur;
        public string Metin;
        public V Konum;            // ekran koordinatı (y yukarı)
        public V Hiz;
        public float Omur, Boyut, Yas, Donus;
    }

    static class M
    {
        public const float PI = 3.14159265f;
        public static float Sin(float a) { return (float)Math.Sin(a); }
        public static float Cos(float a) { return (float)Math.Cos(a); }
        public static float Exp(float a) { return (float)Math.Exp(a); }
        public static float Sinirla(float v, float a, float b) { return Math.Min(Math.Max(v, a), b); }
    }

    // ------------------------------------------------------------------ Windows çağrıları

    static class Win
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct POINT { public int X, Y; public POINT(int x, int y) { X = x; Y = y; } }
        [StructLayout(LayoutKind.Sequential)]
        public struct SIZE { public int CX, CY; public SIZE(int x, int y) { CX = x; CY = y; } }
        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential, Pack = 1)]
        public struct BLENDFUNCTION { public byte BlendOp, BlendFlags, SourceConstantAlpha, AlphaFormat; }

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UpdateLayeredWindow(IntPtr hwnd, IntPtr hdcDst, ref POINT pptDst, ref SIZE psize,
            IntPtr hdcSrc, ref POINT pptSrc, int crKey, ref BLENDFUNCTION pblend, int dwFlags);
        [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
        [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr hDC);
        [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr hdc);
        [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr hDC, IntPtr hObject);
        [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr hObject);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
        [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT r);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
        [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out RECT r, int size);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, StringBuilder metin, int azami);

        /// Pencerenin başlık yazısı (okunamazsa boş).
        public static string Baslik(IntPtr h)
        {
            StringBuilder sb = new StringBuilder(256);
            return GetWindowText(h, sb, sb.Capacity) > 0 ? sb.ToString() : "";
        }

        public static readonly IntPtr EnUstte = new IntPtr(-1);     // HWND_TOPMOST
        public const uint YerDegistirme = 0x0001 | 0x0002 | 0x0010; // boyut ve yer aynı, öne alma yok

        /// Pencerenin görünen çerçevesi (gölge payı olmadan); olmazsa sıradan çerçeve.
        public static bool Cerceve(IntPtr h, out RECT r)
        {
            try
            {
                if (DwmGetWindowAttribute(h, 9, out r, Marshal.SizeOf(typeof(RECT))) == 0 && r.Right > r.Left) return true;
            }
            catch (Exception) { }
            return GetWindowRect(h, out r);
        }
    }

    // ------------------------------------------------------------------ çizim
    // Buradaki çizimler "y yukarı" düzeninde, birim başına bir piksel (ölçek 1) varsayılarak yapılır.

    static class Cizim
    {
        static readonly Color MumCizgi = Color.FromArgb(210, 132, 24);

        static Color Rk(float alfa, int r, int g, int b)
        {
            int a = (int)Math.Round(alfa * 255f);
            if (a < 0) a = 0;
            if (a > 255) a = 255;
            return Color.FromArgb(a, r, g, b);
        }

        public static float GeriSekme(float t)
        {
            float c1 = 1.70158f, c3 = c1 + 1f;
            float u = M.Sinirla(t, 0f, 1f) - 1f;
            return 1f + c3 * u * u * u + c1 * u * u;
        }

        public static void YildizCiz(Graphics g, float r, float donus, float alfa)
        {
            PointF[] p = new PointF[8];
            for (int i = 0; i < 8; i++)
            {
                float a = donus + i * M.PI / 4f;
                float rr = i % 2 == 0 ? r : r * 0.36f;
                p[i] = new PointF(M.Cos(a) * rr, M.Sin(a) * rr);
            }
            using (SolidBrush dolgu = new SolidBrush(Rk(alfa, 255, 214, 70)))
            using (Pen cizgi = new Pen(Rk(alfa, MumCizgi.R, MumCizgi.G, MumCizgi.B), 0.8f))
            {
                cizgi.LineJoin = LineJoin.Round;
                g.FillPolygon(dolgu, p);
                g.DrawPolygon(cizgi, p);
            }
        }

        /// Çevresi çizgili yazı. Dönüşümsüz (piksel, y aşağı) çizilir; (px, py) yazının ortasıdır.
        public static void YaziCiz(Graphics g, string s, float px, float py, float boy, Color dolgu, Color kontur)
        {
            if (boy < 1f) return;
            FontFamily aile;
            try { aile = new FontFamily("Segoe UI"); }
            catch (Exception) { aile = new FontFamily(System.Drawing.Text.GenericFontFamilies.SansSerif); }
            using (aile)
            using (GraphicsPath yol = new GraphicsPath())
            using (StringFormat bicim = new StringFormat())
            {
                bicim.Alignment = StringAlignment.Center;
                bicim.LineAlignment = StringAlignment.Center;
                yol.AddString(s, aile, (int)FontStyle.Bold, boy, new PointF(px, py), bicim);
                using (Pen k = new Pen(kontur, boy * 0.24f))
                {
                    k.LineJoin = LineJoin.Round;
                    g.DrawPath(k, yol);
                }
                using (SolidBrush f = new SolidBrush(dolgu))
                {
                    g.FillPath(f, yol);
                }
            }
        }

        static void YuvarlakKutu(GraphicsPath yol, float x, float y, float w, float h, float r)
        {
            float k = r * 0.5523f;
            yol.AddLine(x + r, y, x + w - r, y);
            yol.AddBezier(x + w - r, y, x + w - r + k, y, x + w, y + r - k, x + w, y + r);
            yol.AddLine(x + w, y + r, x + w, y + h - r);
            yol.AddBezier(x + w, y + h - r, x + w, y + h - r + k, x + w - r + k, y + h, x + w - r, y + h);
            yol.AddLine(x + w - r, y + h, x + r, y + h);
            yol.AddBezier(x + r, y + h, x + r - k, y + h, x, y + h - r + k, x, y + h - r);
            yol.AddLine(x, y + h - r, x, y + r);
            yol.AddBezier(x, y + r, x, y + r - k, x + r - k, y, x + r, y);
            yol.CloseFigure();
        }

        /// Köşeleri (x, y) ve (x + w, y + h) olan dolu dikdörtgen.
        static void Kutu(Graphics g, Brush firca, float x, float y, float w, float h)
        {
            g.FillPolygon(firca, new PointF[] { new PointF(x, y), new PointF(x + w, y), new PointF(x + w, y + h), new PointF(x, y + h) });
        }

        /// Clawd: Claude Code'un açılış ekranındaki turuncu piksel karakter. Biçimi oradaki blok harflerden alındı:
        /// 12 × 4 piksellik gövde, iki dik göz, yanlarda birer kol, altta dört bacak (bir piksel 2,5 × 5 birim).
        /// Merkez (0,0), y yukarı; ayakları -12,5 hizasındadır. `p.Adim`, `p.Kosu`: yürüme; `p.Mesgul`: yazı yazıyor.
        public static void ClawdCiz(Graphics g, Poz p)
        {
            bool mutlu = p.Yuz == Yuz.Mutlu, saskin = p.Yuz == Yuz.Saskin, uyku = p.Yuz == Yuz.Uyku;
            float kosu = M.Sinirla(p.Kosu, 0f, 1f);
            using (SolidBrush turuncu = new SolidBrush(Color.FromArgb(215, 119, 87)))
            using (SolidBrush goz = new SolidBrush(Color.FromArgb(34, 26, 24)))
            using (SolidBrush golge = new SolidBrush(Color.FromArgb(34, 30, 20, 10)))
            {
                g.FillEllipse(golge, -15f, -14.3f, 30f, 3.6f);

                // Bacaklar: yürürken çiftler sırayla kalkar
                float[] bacakX = new float[] { -12.5f, -7.5f, 5f, 10f };
                for (int i = 0; i < bacakX.Length; i++)
                {
                    float kalk = kosu * Math.Max(0f, M.Sin(p.Adim + (i % 2 == 0 ? 0f : M.PI))) * 2.8f;
                    Kutu(g, turuncu, bacakX[i], -12.5f + kalk, 2.5f, 5.6f - kalk);
                }

                // Kollar: sevinince sırayla havaya kalkar, şaşırınca ikisi de kalkar, yazarken sırayla tuşlara iner
                float sol = 0f, sag = 0f;
                if (saskin) { sol = 5f; sag = 5f; }
                else if (mutlu) { sol = 2.5f + 2.5f * M.Sin(p.Faz * 0.12f); sag = 2.5f - 2.5f * M.Sin(p.Faz * 0.12f); }
                else if (p.Mesgul) { sol = -1.8f * M.Sin(p.Faz * 0.2f); sag = 1.8f * M.Sin(p.Faz * 0.2f); }
                else if (!uyku) { sol = p.Salinim * 0.6f; sag = -p.Salinim * 0.6f; }
                Kutu(g, turuncu, -20f, -2.5f + sol, 5.2f, 5f);
                Kutu(g, turuncu, 14.8f, -2.5f + sag, 5.2f, 5f);

                // Gövde
                Kutu(g, turuncu, -15f, -7.6f, 30f, 20.1f);

                // Gözler: iki dik dikdörtgen; bakışa göre kayar, kırpınca kısalır
                for (int i = 0; i < 2; i++)
                {
                    float x = (i == 0 ? -8.75f : 8.75f) + p.Bakis.X * 1.25f, y = 5f + p.Bakis.Y * 1.0f;
                    if (uyku)
                    {
                        Kutu(g, goz, x - 2.5f, 3.4f, 5f, 1.5f);
                    }
                    else if (mutlu)
                    {
                        // Gülen göz: ters U biçiminde üç parça
                        Kutu(g, goz, x - 2.5f, 5.7f, 5f, 1.9f);
                        Kutu(g, goz, x - 2.5f, 3.8f, 1.3f, 1.9f);
                        Kutu(g, goz, x + 1.2f, 3.8f, 1.3f, 1.9f);
                    }
                    else
                    {
                        float w = saskin ? 3.75f : 2.5f, h = (saskin ? 6.25f : 5f) * Math.Max(0.16f, 1f - p.Kirpma);
                        Kutu(g, goz, x - w / 2f, y - h / 2f, w, h);
                    }
                }
            }
        }

        /// Clawd: merkezi (mx, my) pikselinde, `s` birim başına piksel. Basılıp esnerken ayakları yerinde kalır.
        public static void ClawdYerlestir(Graphics g, float mx, float my, float s, Poz poz)
        {
            GraphicsState bas = g.Save();
            g.TranslateTransform(mx, my);
            g.ScaleTransform(1f, -1f);
            g.RotateTransform(poz.Egim * 180f / M.PI);
            g.TranslateTransform(0f, -12.5f * s * poz.Ezme);
            g.ScaleTransform(s * (1f + poz.Ezme), s * (1f - poz.Ezme));
            ClawdCiz(g, poz);
            g.Restore(bas);
        }

        /// İş listesi: beş satır. Ofsetler satırların merkezidir (alttan üste sıralı; liste üstten başlayarak işlenir).
        public static V[] GorevDizilimi()
        {
            return new V[] { new V(0f, -10.3f), new V(0f, -5.6f), new V(0f, -0.9f), new V(0f, 3.8f), new V(0f, 8.5f) };
        }

        static readonly float[] GorevBoylari = new float[] { 19f, 14f, 21f, 12f, 17f };

        /// Konsol penceresi görünümlü iş listesi: satırlar sırayla belirir, yazılır (çizgi uzar) ve bitince kutusu
        /// yeşil işaretlenir. Pencere yerden büyüyerek belirir; tabanı -17 hizasındadır.
        public static void GorevCiz(Graphics g, List<Satir> satirlar, float alfa)
        {
            if (satirlar.Count == 0 || satirlar[0].Belirme <= 0.001f) return;
            float k = GeriSekme(satirlar[0].Belirme);
            if (k <= 0.02f) return;

            GraphicsState d = g.Save();
            g.TranslateTransform(0f, -17f);
            g.ScaleTransform(k, k);
            g.TranslateTransform(0f, 17f);
            using (GraphicsPath pencere = new GraphicsPath())
            using (SolidBrush zemin = new SolidBrush(Rk(alfa, 38, 36, 34)))
            using (SolidBrush baslik = new SolidBrush(Rk(alfa, 58, 55, 52)))
            using (Pen kenar = new Pen(Rk(alfa, 104, 98, 92), 1.1f))
            using (SolidBrush kutuRenk = new SolidBrush(Rk(alfa, 150, 146, 140)))
            using (SolidBrush yesil = new SolidBrush(Rk(alfa, 98, 196, 120)))
            using (SolidBrush turuncu = new SolidBrush(Rk(alfa, 215, 119, 87)))
            using (SolidBrush acik = new SolidBrush(Rk(alfa, 206, 202, 194)))
            using (SolidBrush soluk = new SolidBrush(Rk(alfa, 120, 116, 110)))
            using (Pen tik = new Pen(Rk(alfa, 255, 255, 255), 0.7f))
            {
                kenar.LineJoin = LineJoin.Round;
                tik.StartCap = LineCap.Round;
                tik.EndCap = LineCap.Round;
                YuvarlakKutu(pencere, -16f, -17f, 32f, 34f, 2.6f);
                g.FillPath(zemin, pencere);
                GraphicsState ic = g.Save();
                g.SetClip(pencere, CombineMode.Intersect);
                Kutu(g, baslik, -16f, 12.2f, 32f, 5f);
                g.Restore(ic);
                g.FillEllipse(turuncu, -13.6f, 13.8f, 1.9f, 1.9f);
                g.FillEllipse(kutuRenk, -10.8f, 13.8f, 1.9f, 1.9f);
                g.FillEllipse(kutuRenk, -8.0f, 13.8f, 1.9f, 1.9f);
                for (int i = 0; i < satirlar.Count; i++)
                {
                    Satir satir = satirlar[i];
                    if (satir.Belirme <= 0.001f) continue;
                    float y = satir.Ofset.Y, dolu = M.Sinirla(satir.Dolu, 0f, 1f);
                    bool bitti = satir.Dolu >= 1f;
                    // Onay kutusu
                    Kutu(g, bitti ? yesil : kutuRenk, -13.4f, y - 1.5f, 3f, 3f);
                    if (bitti)
                    {
                        g.DrawLine(tik, -12.7f, y - 0.1f, -12.1f, y - 0.8f);
                        g.DrawLine(tik, -12.1f, y - 0.8f, -11.0f, y + 0.8f);
                    }
                    else
                    {
                        Kutu(g, zemin, -12.8f, y - 0.9f, 1.8f, 1.8f);
                    }
                    // Satırın yazısı: yazıldıkça uzayan çizgi; biten satır soluklaşır
                    float boy = GorevBoylari[i % GorevBoylari.Length] * Math.Min(1f, dolu / 0.85f) * Math.Min(1f, satir.Belirme * 2f);
                    if (boy > 0.3f) Kutu(g, bitti ? soluk : (dolu > 0f ? turuncu : acik), -8.4f, y - 0.8f, boy, 1.6f);
                    else Kutu(g, soluk, -8.4f, y - 0.8f, 1.2f, 1.6f);
                }
                g.DrawPath(kenar, pencere);
            }
            g.Restore(d);
        }

        /// İş listesi: merkezi (px, py) pikselinde.
        public static void GorevYerlestir(Graphics g, float px, float py, float s, List<Satir> satirlar, float alfa)
        {
            GraphicsState d = g.Save();
            g.TranslateTransform(px, py);
            g.ScaleTransform(s, -s);
            GorevCiz(g, satirlar, alfa);
            g.Restore(d);
        }

        /// Uzun bir cümleyi, her satırı en çok `azami` harf olacak biçimde sözcük aralarından böler.
        public static string[] Sar(string metin, int azami)
        {
            List<string> satirlar = new List<string>();
            string[] sozcukler = metin.Split(' ');
            string satir = "";
            for (int i = 0; i < sozcukler.Length; i++)
            {
                if (satir.Length > 0 && satir.Length + 1 + sozcukler[i].Length > azami)
                {
                    satirlar.Add(satir);
                    satir = sozcukler[i];
                }
                else
                {
                    satir = satir.Length == 0 ? sozcukler[i] : satir + " " + sozcukler[i];
                }
            }
            if (satir.Length > 0) satirlar.Add(satir);
            return satirlar.ToArray();
        }

        /// Konsol görünümlü konuşma balonu: koyu kutu, turuncu kenar. `baslik` doluysa en üstte eş aralıklı yazıyla
        /// (komut ya da kısayol) yazılır; altında açıklama satırları durur. Alt ucu (cx, cy) pikselini gösterir.
        /// Piksel düzeni (y aşağı). Balon [solSinir, sagSinir] aralığının dışına taşmaz. `d`: ekran ölçeği.
        public static void KonsolBalonu(Graphics g, float cx, float cy, string baslik, string[] satirlar, float d, float buyume, float alfa, float solSinir, float sagSinir)
        {
            float boy = 12f * d, baslikBoy = 13f * d;
            bool baslikVar = baslik != null && baslik.Length > 0;
            using (Font yazi = new Font("Segoe UI", boy, FontStyle.Regular, GraphicsUnit.Pixel))
            using (Font kod = new Font("Consolas", baslikBoy, FontStyle.Bold, GraphicsUnit.Pixel))
            {
                float genislik = baslikVar ? g.MeasureString(baslik, kod).Width : 0f;
                for (int i = 0; i < satirlar.Length; i++) genislik = Math.Max(genislik, g.MeasureString(satirlar[i], yazi).Width);
                float dolgu = 9f * d, kuyruk = 6f * d, r = 7f * d, satirYuk = boy * 1.34f, baslikYuk = baslikVar ? baslikBoy * 1.42f : 0f;
                float gen = genislik + dolgu * 2f, yuk = dolgu * 1.5f + baslikYuk + satirlar.Length * satirYuk;
                // Kutu ucun üstünde ortalanır; ekrandan taşacaksa yana kayar
                float merkez = M.Sinirla(cx, solSinir + gen / 2f, Math.Max(solSinir + gen / 2f, sagSinir - gen / 2f)) - cx;
                merkez = M.Sinirla(merkez, -(gen / 2f - r - kuyruk), gen / 2f - r - kuyruk);
                float sol = merkez - gen / 2f, ust = -kuyruk - yuk;

                GraphicsState durum = g.Save();
                g.TranslateTransform(cx, cy);
                g.ScaleTransform(buyume, buyume);
                g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
                using (SolidBrush turuncu = new SolidBrush(Rk(alfa, 215, 119, 87)))
                using (SolidBrush baslikRenk = new SolidBrush(Rk(alfa, 238, 148, 116)))
                using (SolidBrush zemin = new SolidBrush(Rk(alfa, 36, 34, 32)))
                using (SolidBrush acik = new SolidBrush(Rk(alfa, 240, 236, 228)))
                using (SolidBrush golge = new SolidBrush(Rk(0.16f * alfa, 20, 12, 8)))
                using (Pen kenar = new Pen(Rk(alfa, 215, 119, 87), 1.5f * d))
                using (GraphicsPath kutu = new GraphicsPath())
                using (GraphicsPath golgeKutu = new GraphicsPath())
                {
                    YuvarlakKutu(golgeKutu, sol + 1f * d, ust + 2f * d, gen, yuk, r);
                    g.FillPath(golge, golgeKutu);
                    g.FillPolygon(turuncu, new PointF[] { new PointF(-kuyruk, -kuyruk - 1f), new PointF(kuyruk, -kuyruk - 1f), new PointF(0f, 0f) });
                    YuvarlakKutu(kutu, sol, ust, gen, yuk, r);
                    g.FillPath(zemin, kutu);
                    g.DrawPath(kenar, kutu);
                    float y = ust + dolgu * 0.62f;
                    if (baslikVar)
                    {
                        g.DrawString(baslik, kod, baslikRenk, sol + dolgu * 0.75f, y);
                        y += baslikYuk;
                    }
                    for (int i = 0; i < satirlar.Length; i++)
                    {
                        g.DrawString(satirlar[i], yazi, acik, sol + dolgu * 0.75f, y);
                        y += satirYuk;
                    }
                }
                g.Restore(durum);
            }
        }

        /// Uyurken başının üstünden yükselen z harfleri.
        public static void UykuHarfleri(Graphics g, float mx, float my, float s, double zaman)
        {
            for (int i = 0; i < 3; i++)
            {
                double ham = zaman * 0.33 + i / 3.0;
                float f = (float)(ham - Math.Floor(ham));
                float boy = (7.5f + f * 6.5f) * s;
                float alfa = M.Sin(f * M.PI);
                float px = mx + (14f + f * 11f + M.Sin(f * 6f) * 2f) * s;
                float py = my - (15f + f * 20f) * s;
                YaziCiz(g, "z", px, py, boy, Rk(alfa, 102, 135, 242), Rk(alfa, 255, 255, 255));
            }
        }

        /// Tek parçacık (yıldız ya da yazı): merkezi (px, py) pikselinde.
        public static void ParcaCiz(Graphics g, Parca p, float px, float py)
        {
            float t = p.Yas / p.Omur;
            float alfa = t < 0.6f ? 1f : Math.Max(0f, 1f - (t - 0.6f) / 0.4f);
            float buyume = Math.Min(1f, t / 0.15f);
            if (p.Tur == Parca.Yazi)
            {
                YaziCiz(g, p.Metin, px, py, p.Boyut * 1.15f, Rk(alfa, 237, 140, 5), Rk(alfa, 255, 255, 255));
                return;
            }
            GraphicsState d = g.Save();
            g.TranslateTransform(px, py);
            g.ScaleTransform(1f, -1f);
            YildizCiz(g, p.Boyut * buyume, p.Donus + t * 2f, alfa);
            g.Restore(d);
        }
    }

    // ------------------------------------------------------------------ ayarlar

    /// Ayarlar %APPDATA%\Clawd\ayarlar.txt dosyasında "ad=değer" satırları olarak durur.
    /// Komut satırından verilen "-ad değer" çiftleri yalnızca o çalıştırma için geçerlidir.
    class Ayarlar
    {
        readonly Dictionary<string, string> kayitli = new Dictionary<string, string>();
        readonly Dictionary<string, string> gecici = new Dictionary<string, string>();
        readonly string yol;

        public Ayarlar(string[] argumanlar, string dosyaAdi)
        {
            string klasor = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Clawd");
            yol = Path.Combine(klasor, dosyaAdi);
            try
            {
                if (File.Exists(yol))
                {
                    string[] satirlar = File.ReadAllLines(yol, Encoding.UTF8);
                    for (int i = 0; i < satirlar.Length; i++)
                    {
                        int e = satirlar[i].IndexOf('=');
                        if (e > 0) kayitli[satirlar[i].Substring(0, e).Trim()] = satirlar[i].Substring(e + 1).Trim();
                    }
                }
            }
            catch (Exception) { }
            for (int i = 0; i + 1 < argumanlar.Length; i += 2)
            {
                if (argumanlar[i].StartsWith("-", StringComparison.Ordinal)) gecici[argumanlar[i].Substring(1)] = argumanlar[i + 1];
            }
        }

        public bool Var(string ad) { return gecici.ContainsKey(ad) || kayitli.ContainsKey(ad); }

        public float Sayi(string ad, float varsayilan)
        {
            string s;
            float f;
            if (!gecici.TryGetValue(ad, out s) && !kayitli.TryGetValue(ad, out s)) return varsayilan;
            return float.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out f) ? f : varsayilan;
        }

        public string Metin(string ad)
        {
            string s;
            if (gecici.TryGetValue(ad, out s) || kayitli.TryGetValue(ad, out s)) return s;
            return null;
        }

        public void Yaz(string ad, float deger)
        {
            kayitli[ad] = deger.ToString("R", CultureInfo.InvariantCulture);
            Kaydet();
        }

        public void Sil(string ad)
        {
            if (kayitli.Remove(ad)) Kaydet();
        }

        void Kaydet()
        {
            try
            {
                Directory.CreateDirectory(Path.GetDirectoryName(yol));
                StringBuilder sb = new StringBuilder();
                foreach (KeyValuePair<string, string> kv in kayitli) sb.AppendLine(kv.Key + "=" + kv.Value);
                File.WriteAllText(yol, sb.ToString(), Encoding.UTF8);
            }
            catch (Exception) { }
        }
    }

    // ------------------------------------------------------------------ Claude'daki mesaj kutusunu bulma

    /// Claude penceresindeki yazı alanının yerini Windows'un UI Automation arayüzüyle bulur.
    /// Yalnızca öğe türü ve çerçeve okur; yazılanları okumaz, hiçbir şeye basmaz.
    /// Sorgular yavaş olabildiği için ayrı bir iş parçacığında yapılır.
    class KutuIzleyici
    {
        readonly object kilit = new object();
        readonly Stopwatch saat = Stopwatch.StartNew();
        readonly float D;
        Thread iplik;

        // istek (arayüz iş parçacığı yazar)
        int istekPid;
        RectangleF istekPencere;      // ekran pikseli, y aşağı
        bool istekHizli;

        // sonuç (arka plan yazar)
        bool sonucVar;
        RectangleF sonucKutu, sonucPencere;
        long sonucZamani = -100000;
        string durum = "-";

        // yalnızca arka planda kullanılanlar
        System.Windows.Automation.AutomationElement onbellek;
        int onbellekPid;
        long sonArama = -100000, sonOdakBakisi = -100000;
        int basarisiz;

        public KutuIzleyici(float d) { D = d; }

        public void Istek(int pid, RectangleF pencere, bool hizli)
        {
            lock (kilit)
            {
                istekPid = pid;
                istekPencere = pencere;
                istekHizli = hizli;
            }
            if (iplik == null)
            {
                iplik = new Thread(Dongu);
                iplik.IsBackground = true;
                iplik.Name = "kutu";
                iplik.Start();
            }
        }

        public void Durdur()
        {
            lock (kilit) { istekPid = 0; }
        }

        /// Son ölçüm: kutu ve o sırada bilinen pencere (ikisi de ekran pikseli, y aşağı), ölçümün yaşı (ms).
        public bool Sonuc(out RectangleF kutu, out RectangleF pencere, out long yas, out string d)
        {
            lock (kilit)
            {
                kutu = sonucKutu;
                pencere = sonucPencere;
                yas = saat.ElapsedMilliseconds - sonucZamani;
                d = durum;
                return sonucVar;
            }
        }

        void Dongu()
        {
            long sonSorgu = -100000;
            while (true)
            {
                int pid;
                RectangleF w;
                bool hizli;
                lock (kilit) { pid = istekPid; w = istekPencere; hizli = istekHizli; }
                long simdi = saat.ElapsedMilliseconds;
                if (pid != 0 && simdi - sonSorgu >= (hizli ? 100 : 500))
                {
                    sonSorgu = simdi;
                    RectangleF kutu = RectangleF.Empty;
                    string d;
                    bool bulundu = false;
                    try { bulundu = Ara(pid, w, out kutu, out d); }
                    catch (Exception e) { d = "hata: " + e.GetType().Name; onbellek = null; }
                    lock (kilit)
                    {
                        durum = d;
                        if (d != "bekliyor")
                        {
                            sonucVar = bulundu;
                            sonucKutu = kutu;
                            sonucPencere = w;
                            sonucZamani = simdi;
                        }
                    }
                }
                Thread.Sleep(50);
            }
        }

        bool Ara(int pid, RectangleF w, out RectangleF kutu, out string d)
        {
            long simdi = saat.ElapsedMilliseconds;
            kutu = RectangleF.Empty;
            if (pid != onbellekPid)
            {
                onbellek = null;
                onbellekPid = pid;
                basarisiz = 0;
                sonArama = -100000;
            }

            // Bilinen yazı alanı duruyorsa yalnızca yeri sorulur
            if (onbellek != null)
            {
                RectangleF f;
                if (Cerceve(onbellek, out f) && Uygun(f, w))
                {
                    // Arada bir klavye odağına bakılır: başka bir mesaj kutusuna geçildiyse Clawd da geçer
                    if (simdi - sonOdakBakisi > 2000)
                    {
                        sonOdakBakisi = simdi;
                        System.Windows.Automation.AutomationElement o = Odak(pid);
                        RectangleF of;
                        if (o != null && !System.Windows.Automation.Automation.Compare(o, onbellek) && Aday(o, w, true, out of))
                        {
                            onbellek = o;
                            kutu = of;
                            d = "odak degisti";
                            return true;
                        }
                    }
                    kutu = f;
                    d = "onbellek";
                    return true;
                }
                onbellek = null;
            }

            if (simdi - sonArama < (basarisiz >= 3 ? 5000 : 1500)) { d = "bekliyor"; return false; }
            sonArama = simdi;

            // 1) Klavye odağındaki öğe çoğu zaman mesaj kutusudur
            System.Windows.Automation.AutomationElement odak = Odak(pid);
            RectangleF r;
            if (odak != null && Aday(odak, w, true, out r))
            {
                onbellek = odak;
                basarisiz = 0;
                kutu = r;
                d = "odak";
                return true;
            }

            // 2) Pencerenin alt ve orta kısmındaki noktalarda ne olduğuna bakılır
            float[] xs = new float[] { 0.5f, 0.6f, 0.4f, 0.7f, 0.3f };
            List<float> ys = new List<float>();
            for (float a = 30f; a <= 210f; a += 20f) ys.Add(w.Bottom - a * D);
            ys.Add(w.Top + w.Height * 0.6f);
            ys.Add(w.Top + w.Height * 0.55f);
            ys.Add(w.Top + w.Height * 0.5f);
            ys.Add(w.Top + w.Height * 0.45f);
            for (int yi = 0; yi < ys.Count; yi++)
            {
                for (int xi = 0; xi < xs.Length; xi++)
                {
                    System.Windows.Automation.AutomationElement e = null;
                    try { e = System.Windows.Automation.AutomationElement.FromPoint(new System.Windows.Point(w.Left + w.Width * xs[xi], ys[yi])); }
                    catch (Exception) { e = null; }
                    for (int derinlik = 0; e != null && derinlik <= 8; derinlik++)
                    {
                        int epid;
                        try { epid = e.Current.ProcessId; }
                        catch (Exception) { break; }
                        if (epid != pid) break;       // Clawd'ın kendi penceresi ya da başka bir uygulama
                        if (Aday(e, w, false, out r))
                        {
                            onbellek = e;
                            basarisiz = 0;
                            kutu = r;
                            d = "nokta";
                            return true;
                        }
                        try { e = System.Windows.Automation.TreeWalker.ControlViewWalker.GetParent(e); }
                        catch (Exception) { e = null; }
                    }
                }
            }
            basarisiz++;
            d = "kutu yok";
            return false;
        }

        System.Windows.Automation.AutomationElement Odak(int pid)
        {
            try
            {
                System.Windows.Automation.AutomationElement o = System.Windows.Automation.AutomationElement.FocusedElement;
                if (o == null || o.Current.ProcessId != pid) return null;
                return o;
            }
            catch (Exception) { return null; }
        }

        /// Öğe geniş bir yazı alanı mı? `belgeOlur`: sayfa türündeki küçük alanlar da kabul edilir.
        bool Aday(System.Windows.Automation.AutomationElement e, RectangleF w, bool belgeOlur, out RectangleF r)
        {
            r = RectangleF.Empty;
            try
            {
                System.Windows.Automation.ControlType tur = e.Current.ControlType;
                bool yaziAlani = tur == System.Windows.Automation.ControlType.Edit
                    || (belgeOlur && tur == System.Windows.Automation.ControlType.Document);
                if (!yaziAlani) return false;
            }
            catch (Exception) { return false; }
            return Cerceve(e, out r) && Uygun(r, w);
        }

        bool Cerceve(System.Windows.Automation.AutomationElement e, out RectangleF r)
        {
            r = RectangleF.Empty;
            try
            {
                System.Windows.Rect b = e.Current.BoundingRectangle;
                if (b.IsEmpty || double.IsInfinity(b.Width) || double.IsNaN(b.Width)) return false;
                r = new RectangleF((float)b.X, (float)b.Y, (float)b.Width, (float)b.Height);
                return true;
            }
            catch (Exception) { return false; }
        }

        bool Uygun(RectangleF f, RectangleF w)
        {
            RectangleF genis = RectangleF.Inflate(w, 4f, 4f);
            return f.Width >= 240f * D && f.Height >= 14f * D && f.Height < w.Height * 0.7f && genis.Contains(f);
        }
    }

    // ------------------------------------------------------------------ pencereler

    /// Kenarlıksız, her zaman üstte, odağı almayan ve her pikselin saydamlığı ayrı olan pencere.
    class KatmanliPencere : Form
    {
        readonly bool tiklamaGecirir;

        public KatmanliPencere(bool tiklamaGecirir)
        {
            this.tiklamaGecirir = tiklamaGecirir;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            Location = new Point(-2000, -2000);
            Size = new Size(10, 10);
            Text = "Clawd";
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams cp = base.CreateParams;
                // katmanlı | araç penceresi (görev çubuğunda görünmez) | en üstte | odağı almaz
                cp.ExStyle |= 0x00080000 | 0x00000080 | 0x00000008 | 0x08000000;
                if (tiklamaGecirir) cp.ExStyle |= 0x00000020;      // tıklamayı alttaki pencereye bırakır
                return cp;
            }
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == 0x0021)       // WM_MOUSEACTIVATE: tıklanınca öne geçme
            {
                m.Result = (IntPtr)3;
                return;
            }
            base.WndProc(ref m);
        }

        /// Resmi pencerenin içeriği yapar ve pencereyi (x, y) noktasına taşır. Saydam pikseller tıklamayı geçirir.
        public void Goster(Bitmap resim, int x, int y)
        {
            if (!IsHandleCreated || IsDisposed) return;
            IntPtr ekran = Win.GetDC(IntPtr.Zero);
            IntPtr bellek = Win.CreateCompatibleDC(ekran);
            IntPtr hb = IntPtr.Zero, eski = IntPtr.Zero;
            try
            {
                hb = resim.GetHbitmap(Color.FromArgb(0));
                eski = Win.SelectObject(bellek, hb);
                Win.SIZE boyut = new Win.SIZE(resim.Width, resim.Height);
                Win.POINT kaynak = new Win.POINT(0, 0);
                Win.POINT hedef = new Win.POINT(x, y);
                Win.BLENDFUNCTION karisim = new Win.BLENDFUNCTION();
                karisim.BlendOp = 0;
                karisim.BlendFlags = 0;
                karisim.SourceConstantAlpha = 255;
                karisim.AlphaFormat = 1;
                Win.UpdateLayeredWindow(Handle, ekran, ref hedef, ref boyut, bellek, ref kaynak, 0, ref karisim, 2);
            }
            finally
            {
                Win.ReleaseDC(IntPtr.Zero, ekran);
                if (hb != IntPtr.Zero)
                {
                    Win.SelectObject(bellek, eski);
                    Win.DeleteObject(hb);
                }
                Win.DeleteDC(bellek);
            }
        }
    }

    /// Clawd'ın penceresi ve bütün davranışı. İkinci bir saydam pencere ("sahne") iş listesini, yıldızları ve
    /// konuşma balonunu taşır; tıklamayı geçirdiği için Clawd her zaman tıklanabilir.
    class ClawdPencere : KatmanliPencere
    {
        const string CalistirAnahtari = @"Software\Microsoft\Windows\CurrentVersion\Run";
        const string CalistirAdi = "Clawd";

        readonly Ayarlar ayar;
        readonly KatmanliPencere sahne = new KatmanliPencere(true);
        readonly System.Windows.Forms.Timer zamanlayici = new System.Windows.Forms.Timer();
        readonly Stopwatch saat = Stopwatch.StartNew();
        readonly Random rastgele = new Random();
        readonly Dictionary<uint, string> surecAdlari = new Dictionary<uint, string>();
        readonly uint benimPid = (uint)Process.GetCurrentProcess().Id;
        KutuIzleyici izleyici;

        // Ayarlar
        float D = 1f;                   // ekran ölçeği (yüzde 100 = 1)
        float olcek = 0.85f;            // Clawd'ın boyu
        double bosSure = 180, dolumSuresi = 9;
        bool kutuIzle = true;
        float S { get { return olcek * D; } }

        // Durum
        Mod mod = Mod.Bekle;
        Baglam baglam = Baglam.Masaustu;
        bool claudeVar;
        Alan claudeCerceve;
        int claudePid;
        float ekranYuksekligi = 1080f;
        V konum, hiz, ev, sahneEv;
        readonly List<V> hedefler = new List<V>();
        double zaman, sonTik, sonEtkilesim, sonEvYoklama = -10, sonCerceveDegisim = -10, sonUstte = -10, sonGunluk = -10;

        // Mesaj kutusu
        bool kutuVar;
        Alan kutuGoreli;                // yazı alanı, Claude penceresinin sol alt köşesine göre
        float kutuPencereG, kutuPencereY;
        long kutuYas = 100000;
        string kutuDurum = "-";
        double sonKutuDegisim = -10;

        // Fare
        bool basili, surukleniyor, menuAcik;
        V basNokta, surukFark;

        // İş listesi
        readonly List<Satir> liste = new List<Satir>();
        int aktifSatir;
        float listeAlfa = 1f;
        bool listeSoluyor, calisiyor;

        // Canlandırma
        readonly List<Parca> parcalar = new List<Parca>();
        Poz poz = new Poz();
        V cizimKayma, bakis;
        float faz, egim, mutluluk, takla, taklaYon = 1f, inis, adimFaz;
        double sonrakiKirpma = 2;
        bool uyuyor, sahneKirli = true;
        Bitmap karakterTampon, sahneTampon;

        // Konuşma balonu ve öneriler
        bool balonAcik, ipucuAcik = true, kodAcik, claudeSureciVar;     // kodAcik: Claude Code önde
        float balonYas, balonOmur = 4.5f;
        string balonBaslik = "";
        string[] balonSatirlar = new string[0];
        int sozSira, ipucuSira, tikSayac;
        double sonrakiIpucu = -1, sonIpucu = -100, sonSurecBakisi = -100, ipucuAraligi = 120;
        static readonly string[] Sozler = new string[]
        {
            "Merhaba! Bugün ne yazıyoruz?",
            "* Düşünüyorum...",
            "Testler geçti mi? Geçmiş gibi yapmayalım.",
            "* Demleniyor...",
            "Bir commit atsak mı?",
            "Hata değil o, beklenmedik özellik.",
            "CLAUDE.md dosyasına yazdıysan unutmam.",
            "* Kod pişiyor...",
            "Önce plan, sonra kod.",
            "Bende çalışıyor!",
            "Kaydettin mi? Emin misin?",
            "Yengeç değilim. Sanırım.",
            "git push --force mu? Bir daha düşün.",
            "Kahve molası verelim mi?",
            "Bana tıklamak hata ayıklamaz ama iyi gelir.",
            "Bağlam dolduysa /compact yazman yeter.",
        };
        // Öneriler Claude Code belgelerinden alındı (code.claude.com/docs: commands, interactive-mode; Kasım 2026)
        static readonly string[][] Ipuclari = new string[][]
        {
            new string[] { "/help", "Yardımı ve kullanabileceğin komutları gösterir." },
            new string[] { "/clear", "Boş bağlamla yeni bir konuşma başlatır. Eskisine /resume ile dönersin." },
            new string[] { "Esc", "Claude'u durdurur. O ana kadar yaptığı iş yerinde kalır." },
            new string[] { "/compact", "Konuşmayı özetleyip bağlamda yer açar. Konuşma kaldığı yerden sürer." },
            new string[] { "Shift+Tab", "İzin modları arasında gezer, plan modu da bunlardan biri. Bazı Windows kurulumlarında Alt+M." },
            new string[] { "/init", "Projeye bir CLAUDE.md kılavuzu hazırlar." },
            new string[] { "@dosya", "Dosya yolu önerir. Seçtiğin dosya mesajına eklenir." },
            new string[] { "/memory", "CLAUDE.md dosyalarını düzenler, otomatik hafızayı açıp kapatır." },
            new string[] { "! komut", "Kabuk modu: komutu doğrudan çalıştırır, çıktısını oturuma ekler." },
            new string[] { "/model", "Modeli değiştirir. Seçimin yeni oturumlarda da geçerli olur." },
            new string[] { "Esc Esc", "Giriş boşken geri sarma menüsünü açar. Yazı varsa taslağı temizler." },
            new string[] { "/resume", "Eski bir konuşmayı seçip kaldığın yerden sürdürür." },
            new string[] { "/rewind", "Konuşmayı ya da kodu önceki bir noktaya geri sarar." },
            new string[] { "Ctrl+C", "Çalışan işi keser. İş yokken ilk basış girişi temizler, ikincisi çıkar." },
            new string[] { "/context", "Bağlamın ne kadarının dolduğunu renkli bir tabloyla gösterir." },
            new string[] { "/plan", "Plan moduna girer. Örnek: /plan giriş hatasını düzelt" },
            new string[] { "/diff", "Çalışma klasöründeki değişiklikleri gösterir. Claude'un yaptıkları da içindedir." },
            new string[] { "Ctrl+J", "Yeni satır ekler. Her terminalde ayarsız çalışır." },
            new string[] { "/code-review", "Yapılan değişiklikleri hata açısından inceler." },
            new string[] { "/permissions", "Araç izinlerini yönetir: izin ver, sor ya da reddet kuralları." },
            new string[] { "/btw", "Konuşmaya eklemeden yan bir soru sormanı sağlar." },
            new string[] { "Ctrl+R", "Önceki komutlarının içinde geriye doğru arar." },
            new string[] { "/usage", "Oturumun maliyetini ve plan kullanım sınırlarını gösterir." },
            new string[] { "/config", "Ayarlar ekranını açar." },
            new string[] { "Ctrl+O", "Ayrıntılı dökümü açıp kapatır: hangi araç ne zaman kullanılmış." },
            new string[] { "/security-review", "Dalındaki değişiklikleri güvenlik açıkları için inceler." },
            new string[] { "/copy", "Claude'un son yanıtını panoya kopyalar." },
            new string[] { "Ctrl+B", "Çalışan komutu arka plana alır." },
            new string[] { "/mcp", "MCP sunucu bağlantılarını yönetir." },
            new string[] { "/branch", "Konuşmayı bu noktadan dallandırır. Asıl konuşma olduğu gibi kalır." },
            new string[] { "Ctrl+T", "Claude'un yapılacaklar listesini gösterir ya da gizler." },
            new string[] { "/doctor", "Kurulumu, ayarları ve CLAUDE.md sorunlarını denetler, çözüm önerir." },
            new string[] { "/export", "Konuşmayı düz metin olarak dışa aktarır." },
            new string[] { "Alt+V", "Windows'ta panodaki görüntüyü mesaja yapıştırır." },
            new string[] { "/add-dir", "Oturuma dosya erişimi için bir klasör daha ekler." },
            new string[] { "/tasks", "Arka planda çalışan işleri gösterir ve yönetir." },
            new string[] { "/", "Satır başına yazınca komut ve beceri listesini açar." },
            new string[] { "/rename", "Oturuma ad verir. Ad yazmazsan konuşmadan kendisi türetir." },
            new string[] { "/skills", "Kullanabileceğin becerileri (skill) listeler." },
            new string[] { "Ctrl+G", "Yazdığın istemi varsayılan metin düzenleyicinde açar." },
            new string[] { "/hooks", "Kanca (hook) ayarlarını gösterir." },
            new string[] { "/status", "Sürümü, modeli, hesabı ve bağlantı durumunu gösterir." },
            new string[] { "/theme", "Renk temasını değiştirir." },
            new string[] { "/fast", "Hızlı modu açar ya da kapatır." },
            new string[] { "?", "Giriş boşken kısayol yardımını açar." },
        };

        public ClawdPencere(string[] argumanlar) : base(false)
        {
            ayar = new Ayarlar(argumanlar, "ayarlar.txt");
        }

        double Simdi { get { return saat.Elapsed.TotalSeconds; } }
        float Rasgele(float a, float b) { return a + (float)rastgele.NextDouble() * (b - a); }
        int PencereKenar { get { return (int)Math.Round(Math.Max(96f, 120f * olcek) * D); } }
        int SahneG { get { return (int)Math.Round(470f * D); } }       // konuşma balonu sığsın diye geniş
        int SahneY { get { return (int)Math.Round(280f * D); } }

        // ---- başlangıç

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            try
            {
                using (Graphics g = Graphics.FromHwnd(IntPtr.Zero)) D = Math.Max(1f, g.DpiX / 96f);
            }
            catch (Exception) { D = 1f; }
            olcek = M.Sinirla(ayar.Sayi("olcek", 0.85f), 0.5f, 2f);
            bosSure = Math.Max(3f, ayar.Sayi("bosSure", 180f));
            dolumSuresi = Math.Max(0.3f, ayar.Sayi("dolumSuresi", 9f));
            kutuIzle = ayar.Sayi("kutuIzle", 1f) > 0.5f;
            ipucuAcik = ayar.Sayi("ipucu", 1f) > 0.5f;
            ipucuAraligi = Math.Max(10f, ayar.Sayi("ipucuAralik", 120f));
            ipucuSira = rastgele.Next(Ipuclari.Length);        // her açılışta başka bir öneriden başlar
            sozSira = rastgele.Next(Sozler.Length);
            Text = "Clawd";
            sahne.Text = "Clawd";

            sahne.Show();
            EvGuncelle();
            sahneEv = ev;
            konum = ev + new V(150f * D, 60f * D);
            sonTik = Simdi;
            sonEtkilesim = sonTik;

            zamanlayici.Interval = 15;
            zamanlayici.Tick += delegate
            {
                try { Tik(); }
                catch (Exception hata) { HataYaz(hata); }
            };
            zamanlayici.Start();
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            zamanlayici.Stop();
            try { sahne.Close(); } catch (Exception) { }
            base.OnFormClosed(e);
        }

        // ---- ev (Clawd'ın durduğu yer)

        string SurecAdi(uint pid)
        {
            string ad;
            if (surecAdlari.TryGetValue(pid, out ad)) return ad;
            try { ad = Process.GetProcessById((int)pid).ProcessName.ToLowerInvariant(); }
            catch (Exception) { ad = ""; }
            if (surecAdlari.Count > 64) surecAdlari.Clear();
            surecAdlari[pid] = ad;
            return ad;
        }

        /// Öndeki pencereye bakar: Claude uygulamasıysa Clawd onun mesaj kutusuna, değilse görev çubuğunun üstüne gider.
        void EvGuncelle()
        {
            ekranYuksekligi = Screen.PrimaryScreen.Bounds.Height;
            Baglam yeni = baglam;
            bool bulundu = false;
            Alan cerceve = new Alan();

            IntPtr on = Win.GetForegroundWindow();
            uint pid = 0;
            if (on != IntPtr.Zero) Win.GetWindowThreadProcessId(on, out pid);

            if (on != IntPtr.Zero && pid == benimPid)
            {
                // Kendi menümüz açıkken bağlam değişmez
                bulundu = claudeVar;
                cerceve = claudeCerceve;
            }
            else
            {
                yeni = Baglam.Masaustu;
                Win.RECT r;
                if (on != IntPtr.Zero && SurecAdi(pid) == "claude" && !Win.IsIconic(on) && Win.Cerceve(on, out r)
                    && r.Right - r.Left > 420f * D && r.Bottom - r.Top > 320f * D)
                {
                    yeni = Baglam.Claude;
                    bulundu = true;
                    cerceve = new Alan(r.Left, ekranYuksekligi - r.Bottom, r.Right - r.Left, r.Bottom - r.Top);
                    claudePid = (int)pid;
                }
            }

            if (yeni != baglam)
            {
                baglam = yeni;
                if (mod == Mod.Oyun)
                {
                    hedefler.Clear();
                    mod = Mod.Bekle;
                }
            }
            if (bulundu != claudeVar || (bulundu && !cerceve.Esit(claudeCerceve))) sonCerceveDegisim = Simdi;
            claudeVar = bulundu;
            claudeCerceve = cerceve;
            KodAcikMiBak(on, pid, bulundu);
            ev = EvNoktasi();
        }

        /// Claude Code önde mi: Claude uygulamasının penceresi ya da içinde Claude çalışan bir terminal penceresi
        /// (başlığında "claude" geçen ya da bilgisayarda bir Claude süreci çalışırken öne gelen terminal).
        void KodAcikMiBak(IntPtr on, uint pid, bool claudePenceresi)
        {
            if (on == IntPtr.Zero)
            {
                kodAcik = false;
                return;
            }
            if (pid == benimPid) return;                 // kendi menümüz açıkken değişmez
            if (claudePenceresi)
            {
                kodAcik = true;
                return;
            }
            string ad = SurecAdi(pid);
            bool terminal = ad == "windowsterminal" || ad == "cmd" || ad == "powershell" || ad == "pwsh" || ad == "conhost"
                || ad == "openconsole" || ad == "wezterm-gui" || ad == "alacritty" || ad == "mintty" || ad == "code" || ad == "cursor";
            if (!terminal)
            {
                kodAcik = false;
                return;
            }
            if (Win.Baslik(on).ToLowerInvariant().Contains("claude"))
            {
                kodAcik = true;
                return;
            }
            if (Simdi - sonSurecBakisi > 5)
            {
                // Süreç listesine seyrek bakılır
                sonSurecBakisi = Simdi;
                claudeSureciVar = false;
                try
                {
                    Process[] surecler = Process.GetProcessesByName("claude");
                    claudeSureciVar = surecler.Length > 0;
                    for (int i = 0; i < surecler.Length; i++) surecler[i].Dispose();
                }
                catch (Exception) { }
            }
            kodAcik = claudeSureciVar;
        }

        /// Mesaj kutusu bulunamadığında kullanılan tahmin: kenar çubuğu 260, yazı alanı 644 geniş (Claude penceresinde ölçülen değerler).
        float VarsayilanClaudeMx(Alan w)
        {
            return 130f * D + Math.Min(322f * D, (w.G - 260f * D) / 2f - 24f * D) - 46f * D;
        }

        bool GecerliKutu(Alan w, out Alan kutu)
        {
            kutu = new Alan();
            if (!kutuIzle || !kutuVar) return false;
            if (kutuYas > 3000 && (kutuPencereG != w.G || kutuPencereY != w.Yuk)) return false;
            kutu = new Alan(kutuGoreli.X + w.X, kutuGoreli.Y + w.Y, kutuGoreli.G, kutuGoreli.Yuk);
            return true;
        }

        V EvNoktasi()
        {
            if (baglam == Baglam.Claude && claudeVar)
            {
                Alan w = claudeCerceve;
                Alan k;
                if (GecerliKutu(w, out k))
                {
                    // Yazı alanının sağ üst köşesine göre: Clawd kutunun üst kenarına basar (yazı alanının yaklaşık 14 üstü)
                    return new V(k.MaxX + ayar.Sayi("kutuDx", -46f) * D, k.MaxY + ayar.Sayi("kutuDy", 14f + 12.5f * olcek) * D);
                }
                // Kutu bulunamadıysa pencerenin ölçüsünden tahmin edilir
                float mx = ayar.Var("claudeMx") ? ayar.Sayi("claudeMx", 0f) * D : VarsayilanClaudeMx(w);
                float dy = ayar.Sayi("claudeDy", 124f) * D;
                return new V(M.Sinirla(w.MidX + mx, w.MinX + 30f * D, w.MaxX - 20f * D),
                             M.Sinirla(w.MinY + dy, w.MinY + 20f * D, w.MaxY - 20f * D));
            }

            // Masaüstü: görev çubuğunun üstünde, saatin solunda durur; yer çalışma alanının sağ alt köşesine göre saklanır
            Rectangle ca = Screen.PrimaryScreen.WorkingArea;
            float sag = ca.Right, alt = ekranYuksekligi - ca.Bottom;
            V varsayilan = new V(sag - 150f * D, alt + 13f * S);        // ayakları görev çubuğunun üst kenarında
            if (ayar.Var("masaDx") && ayar.Var("masaDy"))
            {
                V p = new V(sag + ayar.Sayi("masaDx", 0f) * D, alt + ayar.Sayi("masaDy", 0f) * D);
                Point ekranNoktasi = new Point((int)p.X, (int)(ekranYuksekligi - p.Y));
                Screen[] ekranlar = Screen.AllScreens;
                for (int i = 0; i < ekranlar.Length; i++)
                {
                    if (ekranlar[i].Bounds.Contains(ekranNoktasi)) return p;
                }
            }
            return varsayilan;
        }

        /// Sürüklenip bırakılan yeri, bulunduğu bağlama göre saklar.
        void YeriKaydet()
        {
            if (baglam == Baglam.Claude && claudeVar)
            {
                Alan w = claudeCerceve;
                Alan k;
                if (GecerliKutu(w, out k))
                {
                    ayar.Yaz("kutuDx", (konum.X - k.MaxX) / D);
                    ayar.Yaz("kutuDy", (konum.Y - k.MaxY) / D);
                }
                else
                {
                    ayar.Yaz("claudeMx", (konum.X - w.MidX) / D);
                    ayar.Yaz("claudeDy", (konum.Y - w.MinY) / D);
                }
            }
            else
            {
                Rectangle ca = Screen.PrimaryScreen.WorkingArea;
                ayar.Yaz("masaDx", (konum.X - ca.Right) / D);
                ayar.Yaz("masaDy", (konum.Y - (ekranYuksekligi - ca.Bottom)) / D);
            }
            ev = EvNoktasi();
        }

        /// Koşu noktalarını Clawd'ın bulunduğu ekranın içinde tutar.
        V EkranaSigdir(V p)
        {
            Screen e = Screen.FromPoint(new Point((int)ev.X, (int)(ekranYuksekligi - ev.Y)));
            Rectangle b = e.Bounds, ca = e.WorkingArea;
            return new V(M.Sinirla(p.X, b.Left + 34f * D, b.Right - 34f * D),
                         M.Sinirla(p.Y, ekranYuksekligi - ca.Bottom + 16f * S, ekranYuksekligi - b.Top - 40f * D));
        }

        V Fare()
        {
            Point p = Cursor.Position;
            return new V(p.X, ekranYuksekligi - p.Y);
        }

        // ---- fare

        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button != MouseButtons.Left) return;
            basili = true;
            surukleniyor = false;
            basNokta = Fare();
            surukFark = konum - basNokta;
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (!basili) return;
            V f = Fare();
            if (!surukleniyor && (f - basNokta).Uzunluk > 4f * D)
            {
                surukleniyor = true;
                hedefler.Clear();
                if (liste.Count > 0 && !listeSoluyor) ListeyiTopla();
                mod = Mod.Bekle;
            }
            if (surukleniyor)
            {
                konum = f + surukFark;
                hiz = new V(0f, 0f);
            }
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (e.Button == MouseButtons.Right)
            {
                MenuGoster();
                return;
            }
            if (e.Button != MouseButtons.Left || !basili) return;
            basili = false;
            sonEtkilesim = Simdi;
            if (surukleniyor)
            {
                surukleniyor = false;
                YeriKaydet();
                inis = 1f;
            }
            else
            {
                Tiklandi();
            }
        }

        // ---- sözler ve öneriler

        /// Konsol görünümlü balonu açar: `baslik` komut ya da kısayoldur (boş olabilir), `metin` satırlara bölünür.
        void BalonGoster(string baslik, string metin, float omur)
        {
            balonBaslik = baslik;
            balonSatirlar = Cizim.Sar(metin, 36);
            balonYas = 0f;
            balonOmur = omur;
            balonAcik = true;
            sahneKirli = true;
        }

        /// Sıradaki Claude Code önerisini gösterir.
        void IpucuGoster()
        {
            string[] ipucu = Ipuclari[ipucuSira % Ipuclari.Length];
            ipucuSira++;
            BalonGoster(ipucu[0], ipucu[1], 9f);
            sonIpucu = Simdi;
            mutluluk = Math.Max(mutluluk, 0.7f);
        }

        /// Tıklanınca sevinir, bir söz söyler ve yana yana koşup geri gelir. Claude Code öndeyken her ikinci
        /// tıklamada söz yerine bir komut önerisi verir. İş listesi açıksa toplanır.
        void Tiklandi()
        {
            if (liste.Count > 0 && !listeSoluyor) ListeyiTopla();
            mutluluk = 1.3f;
            inis = 1f;
            tikSayac++;
            if (kodAcik && tikSayac % 2 == 0)
            {
                IpucuGoster();
            }
            else
            {
                BalonGoster("", Sozler[sozSira % Sozler.Length], 4.5f);
                sozSira++;
            }
            if (mod == Mod.Oyun)
            {
                takla = 1f;
                taklaYon = hiz.X >= 0f ? -1f : 1f;
            }
            mod = Mod.Oyun;
            float yon = rastgele.Next(2) == 0 ? 1f : -1f;
            hedefler.Clear();
            hedefler.Add(EkranaSigdir(ev + new V(yon * Rasgele(40f, 70f) * D, 0f)));
            hedefler.Add(EkranaSigdir(ev + new V(-yon * Rasgele(25f, 45f) * D, 0f)));
            hedefler.Add(ev);
        }

        /// Claude Code öndeyken arada bir komut önerisi verir. Claude Code öne geldiğinde uyuyorsa ya da iş
        /// listesiyle uğraşıyorsa bırakıp uyanır.
        void OneriDongusu(double simdi)
        {
            if (!kodAcik)
            {
                sonrakiIpucu = -1;
                return;
            }
            if (!ipucuAcik) return;
            if (mod == Mod.Calis || mod == Mod.Uyu)
            {
                if (liste.Count > 0 && !listeSoluyor) ListeyiTopla();
                mod = Mod.Bekle;
                sonEtkilesim = simdi;
            }
            // Öne gelince ilk öneri birkaç saniye sonra; pencere sık değiştirilse de öneriler art arda yağmaz
            if (sonrakiIpucu < 0) sonrakiIpucu = Math.Max(simdi + 6, sonIpucu + 25);
            if (simdi < sonrakiIpucu || balonAcik || surukleniyor || menuAcik || basili || mod != Mod.Bekle) return;
            IpucuGoster();
            sonrakiIpucu = simdi + ipucuAraligi;
        }

        // ---- iş listesi

        void ListeyeBasla()
        {
            V[] dizilim = Cizim.GorevDizilimi();
            liste.Clear();
            // Dizilim alttan üste sıralıdır; liste üstten başlayarak işlenir
            for (int i = dizilim.Length - 1; i >= 0; i--)
            {
                Satir s = new Satir();
                s.Ofset = dizilim[i];
                liste.Add(s);
            }
            aktifSatir = 0;
            listeAlfa = 1f;
            listeSoluyor = false;
            hedefler.Clear();
            mod = Mod.Calis;
        }

        /// İş listesinin merkezi: Clawd'ın solunda, tabanı ayak hizasında.
        V ListeMerkez(V taban) { return taban + new V(-39f * S, 4.5f * S); }

        /// Sıradaki satırı belirtir, yazar ve işaretler. Clawd bunu durduğu yerden yapar.
        void Calis(float dt)
        {
            if (aktifSatir >= liste.Count)
            {
                mod = Mod.Uyu;
                return;
            }
            if ((konum - ev).Uzunluk >= 9f * D || (sahneEv - ev).Uzunluk >= 1f) return;
            calisiyor = true;
            Satir s = liste[aktifSatir];
            if (s.Belirme < 1f)
            {
                s.Belirme = Math.Min(1f, s.Belirme + dt / 0.45f);
            }
            else
            {
                s.Dolu += dt / (float)dolumSuresi;
                if (s.Dolu >= 1f)
                {
                    s.Dolu = 1f;
                    aktifSatir++;
                    if (aktifSatir >= liste.Count)
                    {
                        mod = Mod.Uyu;
                        mutluluk = 1.0f;
                        BalonGoster("", "Liste bitti. Biraz kestireyim.", 3.5f);
                    }
                }
            }
        }

        /// Listeyi kapatır: satırlardan yıldız saçılır, biten satır sayısı sayaca eklenir.
        void ListeyiTopla()
        {
            int biten = 0;
            V pm = ListeMerkez(sahneEv);
            for (int i = 0; i < liste.Count; i++)
            {
                if (liste[i].Dolu > 0.5f) biten++;
                if (liste[i].Belirme <= 0.5f) continue;
                V m = pm + liste[i].Ofset * S;
                for (int j = 0; j < 2; j++)
                {
                    float a = Rasgele(0f, 2f * M.PI), v = Rasgele(26f, 64f) * D;
                    Parca y = new Parca();
                    y.Tur = Parca.Yildiz;
                    y.Konum = m;
                    y.Hiz = new V(M.Cos(a) * v, M.Sin(a) * v + 14f * D);
                    y.Omur = Rasgele(0.55f, 0.9f);
                    y.Boyut = Rasgele(2.6f, 4.6f) * S;
                    y.Donus = Rasgele(0f, 3f);
                    parcalar.Add(y);
                }
            }
            if (biten > 0)
            {
                ayar.Yaz("biten", ayar.Sayi("biten", 0f) + biten);
                Parca yazi = new Parca();
                yazi.Tur = Parca.Yazi;
                yazi.Metin = "+" + biten.ToString(CultureInfo.InvariantCulture);
                yazi.Konum = pm + new V(0f, 26f * S);
                yazi.Hiz = new V(0f, 30f * D);
                yazi.Omur = 1.5f;
                yazi.Boyut = 14f * S;
                parcalar.Add(yazi);
            }
            listeSoluyor = true;
        }

        // ---- menü

        void MenuGoster()
        {
            sonEtkilesim = Simdi;
            ContextMenuStrip m = new ContextMenuStrip();
            ToolStripMenuItem bilgi = new ToolStripMenuItem("Biten iş: " + ((int)ayar.Sayi("biten", 0f)).ToString(CultureInfo.InvariantCulture));
            bilgi.Enabled = false;
            m.Items.Add(bilgi);
            m.Items.Add(new ToolStripSeparator());

            m.Items.Add("Şimdi bir öneri ver", null, delegate
            {
                sonEtkilesim = Simdi;
                IpucuGoster();
            });
            ToolStripMenuItem oneri = new ToolStripMenuItem("Claude Code açıkken öneri ver");
            oneri.Checked = ipucuAcik;
            oneri.Click += delegate
            {
                ipucuAcik = !ipucuAcik;
                ayar.Yaz("ipucu", ipucuAcik ? 1f : 0f);
                sonrakiIpucu = -1;
            };
            m.Items.Add(oneri);
            ToolStripMenuItem siklik = new ToolStripMenuItem("Öneri sıklığı");
            string[] siklikAdlari = new string[] { "30 saniye", "2 dakika", "5 dakika", "15 dakika" };
            double[] sikliklar = new double[] { 30, 120, 300, 900 };
            for (int i = 0; i < sikliklar.Length; i++)
            {
                double aralik = sikliklar[i];
                ToolStripMenuItem secenek = new ToolStripMenuItem(siklikAdlari[i]);
                secenek.Checked = Math.Abs(ipucuAraligi - aralik) < 1;
                secenek.Click += delegate
                {
                    ipucuAraligi = aralik;
                    ayar.Yaz("ipucuAralik", (float)aralik);
                    sonrakiIpucu = -1;
                };
                siklik.DropDownItems.Add(secenek);
            }
            m.Items.Add(siklik);
            m.Items.Add(new ToolStripSeparator());

            m.Items.Add("Şimdi iş listesini yap", null, delegate { SimdiListeYap(); });
            ToolStripMenuItem sure = new ToolStripMenuItem("İş listesine başlama süresi");
            string[] sureAdlari = new string[] { "1 dakika", "3 dakika", "10 dakika", "30 dakika" };
            double[] sureler = new double[] { 60, 180, 600, 1800 };
            for (int i = 0; i < sureler.Length; i++)
            {
                double sn = sureler[i];
                ToolStripMenuItem kalem = new ToolStripMenuItem(sureAdlari[i]);
                kalem.Checked = Math.Abs(bosSure - sn) < 1;
                kalem.Click += delegate
                {
                    bosSure = sn;
                    ayar.Yaz("bosSure", (float)sn);
                    sonEtkilesim = Simdi;
                };
                sure.DropDownItems.Add(kalem);
            }
            m.Items.Add(sure);

            ToolStripMenuItem boyut = new ToolStripMenuItem("Boyut");
            string[] boyutAdlari = new string[] { "Küçük", "Orta", "Büyük" };
            float[] boyutlar = new float[] { 0.7f, 0.85f, 1.1f };
            for (int i = 0; i < boyutlar.Length; i++)
            {
                float o = boyutlar[i];
                ToolStripMenuItem kalem = new ToolStripMenuItem(boyutAdlari[i]);
                kalem.Checked = Math.Abs(olcek - o) < 0.01f;
                kalem.Click += delegate
                {
                    olcek = o;
                    ayar.Yaz("olcek", o);
                    ev = EvNoktasi();
                    sahneKirli = true;
                };
                boyut.DropDownItems.Add(kalem);
            }
            m.Items.Add(boyut);

            m.Items.Add("Buradaki yerini sıfırla", null, delegate
            {
                if (baglam == Baglam.Claude)
                {
                    ayar.Sil("claudeMx");
                    ayar.Sil("claudeDy");
                    ayar.Sil("kutuDx");
                    ayar.Sil("kutuDy");
                }
                else
                {
                    ayar.Sil("masaDx");
                    ayar.Sil("masaDy");
                }
                ev = EvNoktasi();
            });
            m.Items.Add(new ToolStripSeparator());

            ToolStripMenuItem izle = new ToolStripMenuItem("Claude'da mesaj kutusunu izle");
            izle.Checked = kutuIzle;
            izle.Click += delegate
            {
                kutuIzle = !kutuIzle;
                ayar.Yaz("kutuIzle", kutuIzle ? 1f : 0f);
                if (!kutuIzle)
                {
                    kutuVar = false;
                    if (izleyici != null) izleyici.Durdur();
                }
                ev = EvNoktasi();
            };
            m.Items.Add(izle);

            ToolStripMenuItem acilis = new ToolStripMenuItem("Bilgisayar açılınca başlat");
            acilis.Checked = AcilistaBaslar();
            acilis.Click += delegate { AcilisDegistir(); };
            m.Items.Add(acilis);
            m.Items.Add(new ToolStripSeparator());
            m.Items.Add("Clawd'ı kapat", null, delegate { Close(); });

            // Menü, başka yere tıklanınca kapanabilsin diye Clawd öne alınır; kapanınca odak önceki uygulamaya geri verilir
            IntPtr onceki = Win.GetForegroundWindow();
            m.Closed += delegate
            {
                menuAcik = false;
                if (onceki != IntPtr.Zero && onceki != Handle && !IsDisposed) Win.SetForegroundWindow(onceki);
            };
            menuAcik = true;
            Win.SetForegroundWindow(Handle);
            m.Show(Cursor.Position);
        }

        void SimdiListeYap()
        {
            if (liste.Count > 0)
            {
                ListeyiTopla();
                liste.Clear();
                listeSoluyor = false;
                listeAlfa = 1f;
            }
            ListeyeBasla();
        }

        bool AcilistaBaslar()
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(CalistirAnahtari, false))
                {
                    return k != null && k.GetValue(CalistirAdi) != null;
                }
            }
            catch (Exception) { return false; }
        }

        void AcilisDegistir()
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(CalistirAnahtari, true))
                {
                    if (k == null) return;
                    if (k.GetValue(CalistirAdi) != null) k.DeleteValue(CalistirAdi, false);
                    else k.SetValue(CalistirAdi, "\"" + Application.ExecutablePath + "\"");
                }
            }
            catch (Exception) { }
        }

        // ---- her karede

        void Tik()
        {
            double simdi = Simdi;
            float dt = (float)Math.Min(0.1, Math.Max(0.001, simdi - sonTik));
            sonTik = simdi;
            zaman += dt;
            V fare = Fare();

            // Claude penceresi kıpırdıyorsa sık, duruyorsa seyrek yoklanır
            double aralik = baglam == Baglam.Claude ? (simdi - sonCerceveDegisim < 2 ? 0.08 : 0.3) : 0.4;
            if (simdi - sonEvYoklama > aralik)
            {
                sonEvYoklama = simdi;
                EvGuncelle();
            }
            KutuYokla(simdi);
            OneriDongusu(simdi);

            calisiyor = false;
            if (mod == Mod.Bekle)
            {
                // Uzun süre dokunulmadıysa iş listesine başlar; Claude Code öndeyken uyanık kalır
                if (!basili && !menuAcik && simdi - sonEtkilesim > bosSure && !(kodAcik && ipucuAcik)) ListeyeBasla();
            }
            else if (mod == Mod.Calis)
            {
                Calis(dt);
            }

            Hareket(dt);

            // Sahne (iş listesi) Clawd'ın evini izler; uzak bir yere geçerken liste sönüp orada yeniden belirir
            float fark = (sahneEv - ev).Uzunluk;
            if (fark > 0.5f)
            {
                if (liste.Count == 0 || fark < 80f * D)
                {
                    sahneEv = ev;
                }
                else
                {
                    listeAlfa = Math.Max(0f, listeAlfa - dt / 0.15f);
                    if (listeAlfa <= 0f) sahneEv = ev;
                }
                sahneKirli = true;
            }
            else if (listeSoluyor)
            {
                listeAlfa = Math.Max(0f, listeAlfa - dt / 0.45f);
                if (listeAlfa <= 0f)
                {
                    liste.Clear();
                    listeSoluyor = false;
                    listeAlfa = 1f;
                }
                sahneKirli = true;
            }
            else if (listeAlfa < 1f && (konum - ev).Uzunluk < 110f * D)
            {
                listeAlfa = Math.Min(1f, listeAlfa + dt / 0.3f);
                sahneKirli = true;
            }

            // Parçacıklar
            if (parcalar.Count > 0)
            {
                for (int i = parcalar.Count - 1; i >= 0; i--)
                {
                    Parca p = parcalar[i];
                    p.Yas += dt;
                    p.Konum = p.Konum + p.Hiz * dt;
                    p.Hiz = p.Hiz * (1f - 1.4f * dt);
                    if (p.Yas >= p.Omur) parcalar.RemoveAt(i);
                }
                sahneKirli = true;
            }

            // Konuşma balonu
            if (balonAcik)
            {
                balonYas += dt;
                if (balonYas >= balonOmur) balonAcik = false;
                sahneKirli = true;
            }

            PozHazirla(dt, fare);
            KarakterCiz();
            if (sahneKirli || calisiyor) SahneCiz();

            // Başka pencereler öne geçmiş olabilir; arada bir yeniden en üste alınır.
            // Son çağrılan en üstte kalır: balon Clawd'ın önünde dursun diye sahne üsttedir.
            if (simdi - sonUstte > 2)
            {
                sonUstte = simdi;
                Win.SetWindowPos(Handle, Win.EnUstte, 0, 0, 0, 0, Win.YerDegistirme);
                Win.SetWindowPos(sahne.Handle, Win.EnUstte, 0, 0, 0, 0, Win.YerDegistirme);
            }

            // Hareket varken sık, dururken seyrek, uyurken daha da seyrek çizilir
            bool hareketli = surukleniyor || mod == Mod.Oyun || hiz.Uzunluk > 6f * D || parcalar.Count > 0 || takla > 0f;
            int ms = hareketli ? 15 : (uyuyor ? 100 : 33);
            if (zamanlayici.Interval != ms) zamanlayici.Interval = ms;

            Gunluk(simdi);
        }

        void KutuYokla(double simdi)
        {
            if (!kutuIzle || baglam != Baglam.Claude || !claudeVar || claudePid == 0)
            {
                if (izleyici != null) izleyici.Durdur();
                return;
            }
            Alan w = claudeCerceve;
            RectangleF ekranPencere = new RectangleF(w.X, ekranYuksekligi - w.MaxY, w.G, w.Yuk);
            try
            {
                if (izleyici == null) izleyici = new KutuIzleyici(D);
                izleyici.Istek(claudePid, ekranPencere, simdi - sonKutuDegisim < 2 || simdi - sonCerceveDegisim < 2);
                KutuSonucuAl();
            }
            catch (Exception e)
            {
                // UI Automation bu bilgisayarda kullanılamıyorsa tahmine dönülür
                kutuVar = false;
                kutuDurum = "kullanilamiyor: " + e.GetType().Name;
            }
        }

        void KutuSonucuAl()
        {
            RectangleF kutu, pencere;
            long yas;
            string d;
            bool bulundu = izleyici.Sonuc(out kutu, out pencere, out yas, out d);
            kutuDurum = d;
            kutuYas = yas;
            if (!bulundu)
            {
                if (kutuVar && d == "kutu yok") { kutuVar = false; ev = EvNoktasi(); }
                return;
            }
            // Ölçümü, alındığı andaki pencerenin sol alt köşesine göre sakla (y yukarı)
            Alan yeni = new Alan(kutu.Left - pencere.Left, pencere.Bottom - kutu.Bottom, kutu.Width, kutu.Height);
            if (!kutuVar || !yeni.Esit(kutuGoreli))
            {
                sonKutuDegisim = Simdi;
                kutuVar = true;
                kutuGoreli = yeni;
                kutuPencereG = pencere.Width;
                kutuPencereY = pencere.Height;
                ev = EvNoktasi();
            }
        }

        /// Clawd'ı hedefine doğru yürütür: sıradaki koşu noktasına, yoksa evine.
        void Hareket(float dt)
        {
            if (surukleniyor || menuAcik) return;      // menü açıkken yerinde durur
            V hedef = ev;
            bool son = true;
            float azami = 900f * D;
            if (hedefler.Count > 0)
            {
                hedef = hedefler[0];
                son = hedefler.Count == 1;
                azami = 430f * D;
            }
            V d = hedef - konum;
            float uz = d.Uzunluk;
            float surat = son ? Math.Min(azami, uz * 5.5f) : azami;
            V istenen = d.Birim * surat;
            float k = 1f - M.Exp(-dt * (son ? 7f : 4.5f));
            hiz = hiz + (istenen - hiz) * k;
            if (uz < 0.3f && hiz.Uzunluk < 2f)
            {
                konum = hedef;
                hiz = new V(0f, 0f);
            }
            else
            {
                konum = konum + hiz * dt;
            }
            if (hedefler.Count > 0 && uz < (son ? 5f : 32f) * D)
            {
                hedefler.RemoveAt(0);
                if (hedefler.Count == 0 && mod == Mod.Oyun)
                {
                    mod = Mod.Bekle;
                    inis = 1f;
                }
            }
        }

        void PozHazirla(float dt, V fare)
        {
            float surat = hiz.Uzunluk / D;          // yüzde 100 ölçeğe göre
            uyuyor = mod == Mod.Uyu && (konum - ev).Uzunluk < 5f * D && surat < 6f && !surukleniyor;

            faz += dt * 2f * M.PI * (surukleniyor ? 15f : (surat > 60f ? 13f : 9f));
            if (faz > 1000f) faz -= 1000f;
            // Adımlar gidilen yolla ilerler; tutulup taşınırken bacakları havada çırpınır
            float kosu = surukleniyor ? 1f : Math.Min(1f, surat / 45f);
            adimFaz += dt * (surukleniyor ? 26f : Math.Min(surat, 460f) * 0.085f);
            if (adimFaz > 200f * M.PI) adimFaz -= 200f * M.PI;

            float hedefEgim = -M.Sinirla(hiz.X / D / 520f, -1f, 1f) * 0.36f;
            egim += (hedefEgim - egim) * (1f - M.Exp(-dt * 10f));
            float toplamEgim = egim;
            if (takla > 0f)
            {
                takla = Math.Max(0f, takla - dt / 0.55f);
                float t = 1f - takla;
                toplamEgim += taklaYon * 2f * M.PI * (t * t * (3f - 2f * t));
            }
            if (calisiyor) toplamEgim += M.Sin((float)zaman * 16f) * 0.035f;       // yazarken hafifçe titrer

            mutluluk = Math.Max(0f, mutluluk - dt);
            inis = Math.Max(0f, inis - dt / 0.35f);

            // Bakış: koşarken gittiği yöne, yazarken listeye, dururken fareye
            V hedefBakis = new V(0f, 0f);
            if (surat > 50f)
            {
                hedefBakis = hiz.Birim;
            }
            else if (calisiyor && aktifSatir < liste.Count)
            {
                hedefBakis = (ListeMerkez(ev) + liste[aktifSatir].Ofset * S - konum).Birim;
            }
            else if (!uyuyor)
            {
                V d = fare - konum;
                hedefBakis = d.Birim * Math.Min(1f, d.Uzunluk / (90f * D));
            }
            bakis = bakis + (hedefBakis - bakis) * (1f - M.Exp(-dt * 12f));

            float kirpma = 0f;
            if (zaman > sonrakiKirpma)
            {
                double t = (zaman - sonrakiKirpma) / 0.16;
                if (t >= 1) sonrakiKirpma = zaman + Rasgele(2.2f, 5.5f);
                else kirpma = M.Sin((float)t * M.PI);
            }

            Poz p = new Poz();
            p.Faz = faz;
            p.Egim = toplamEgim;
            p.Bakis = bakis;
            p.Kirpma = kirpma;
            p.Salinim = M.Sin((float)zaman * 2.1f) * 0.8f + M.Sinirla(-hiz.X / D / 300f, -1.2f, 1.2f);
            p.Adim = adimFaz;
            p.Kosu = kosu;
            p.Mesgul = calisiyor;
            if (surukleniyor)
            {
                p.Yuz = Yuz.Saskin;
            }
            else if (mutluluk > 0f)
            {
                p.Yuz = Yuz.Mutlu;
            }
            else if (uyuyor)
            {
                p.Yuz = Yuz.Uyku;
                p.Salinim = 0f;
            }
            if (uyuyor) p.Ezme = M.Sin((float)zaman * 1.7f) * 0.03f;
            else if (inis > 0f) p.Ezme = M.Sin(inis * M.PI) * 0.10f;
            else if (mutluluk > 0.9f && mutluluk <= 1.3f) p.Ezme = -M.Sin((1.3f - mutluluk) / 0.4f * M.PI) * 0.08f;
            else p.Ezme = M.Sin((float)zaman * 2.2f) * 0.018f;        // dururken soluk alıp verir
            poz = p;

            // Yürürken adım adım hafifçe yükselir
            V kayma = new V(0f, 0f);
            if (!surukleniyor) kayma.Y += Math.Abs(M.Sin(adimFaz)) * 1.4f * S * kosu;
            cizimKayma = kayma;
        }

        // ---- ekrana basma

        static void Kalite(Graphics g)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.CompositingQuality = CompositingQuality.HighQuality;
        }

        void KarakterCiz()
        {
            int k = PencereKenar;
            if (karakterTampon == null || karakterTampon.Width != k)
            {
                if (karakterTampon != null) karakterTampon.Dispose();
                karakterTampon = new Bitmap(k, k, PixelFormat.Format32bppArgb);
            }
            float mx = k / 2f + cizimKayma.X, my = k / 2f - cizimKayma.Y;
            using (Graphics g = Graphics.FromImage(karakterTampon))
            {
                g.Clear(Color.Transparent);
                Kalite(g);
                Cizim.ClawdYerlestir(g, mx, my, S, poz);
                if (uyuyor && mutluluk <= 0f) Cizim.UykuHarfleri(g, mx, my, S, zaman);      // liste bitince önce sevinir, sonra uyur
            }
            int sol = (int)Math.Round(konum.X - k / 2f);
            int ust = (int)Math.Round(ekranYuksekligi - konum.Y - k / 2f);
            Goster(karakterTampon, sol, ust);
        }

        void SahneCiz()
        {
            int gen = SahneG, yuk = SahneY;
            if (sahneTampon == null || sahneTampon.Width != gen || sahneTampon.Height != yuk)
            {
                if (sahneTampon != null) sahneTampon.Dispose();
                sahneTampon = new Bitmap(gen, yuk, PixelFormat.Format32bppArgb);
            }
            // Sahnenin sol üst köşesi (ekran pikseli) ve aynı noktanın "y yukarı" karşılığı
            int sol = (int)Math.Round(sahneEv.X - gen / 2f);
            int ust = (int)Math.Round(ekranYuksekligi - sahneEv.Y - yuk / 2f);
            float ustY = ekranYuksekligi - ust;

            using (Graphics g = Graphics.FromImage(sahneTampon))
            {
                g.Clear(Color.Transparent);
                Kalite(g);
                if (liste.Count > 0 && listeAlfa > 0.01f)
                {
                    V pm = ListeMerkez(sahneEv);
                    Cizim.GorevYerlestir(g, pm.X - sol, ustY - pm.Y, S, liste, listeAlfa);
                }
                for (int i = 0; i < parcalar.Count; i++)
                {
                    Cizim.ParcaCiz(g, parcalar[i], parcalar[i].Konum.X - sol, ustY - parcalar[i].Konum.Y);
                }
                if (balonAcik)
                {
                    // Konuşma balonu: başının üstünde durur, yürürken peşinden gelir
                    float buyume = Cizim.GeriSekme(Math.Min(1f, balonYas / 0.2f));
                    float alfa = balonYas > balonOmur - 0.5f ? Math.Max(0f, (balonOmur - balonYas) / 0.5f) : 1f;
                    V tepe = konum + cizimKayma + new V(0f, 17f * S);
                    // Balon ekranın dışına taşmasın: sahnenin ve ekranın ortak aralığı
                    Rectangle ekran = Screen.FromPoint(new Point((int)tepe.X, (int)(ekranYuksekligi - tepe.Y))).Bounds;
                    float solSinir = Math.Max(4f, ekran.Left + 4f - sol), sagSinir = Math.Min(gen - 4f, ekran.Right - 4f - sol);
                    Cizim.KonsolBalonu(g, tepe.X - sol, ustY - tepe.Y, balonBaslik, balonSatirlar, D, buyume, alfa, solSinir, sagSinir);
                }
            }
            sahne.Goster(sahneTampon, sol, ust);
            // Çizilecek bir şey kalmadıysa bir sonraki değişikliğe kadar yeniden çizilmez
            sahneKirli = parcalar.Count > 0 || listeSoluyor || balonAcik;
        }

        /// Beklenmeyen hata olursa Clawd çalışmaya devam eder; ilk birkaç hata Clawd.exe'nin yanındaki
        /// clawd-hata.txt dosyasına yazılır.
        int hataSayac;

        public void HataYaz(Exception hata)
        {
            if (hataSayac++ >= 5) return;
            try
            {
                File.AppendAllText(Path.Combine(Application.StartupPath, "clawd-hata.txt"),
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture) + Environment.NewLine + hata + Environment.NewLine + Environment.NewLine,
                    Encoding.UTF8);
            }
            catch (Exception) { }
        }

        // ---- deneme günlüğü: Clawd.exe -gunluk 1  (Clawd.exe'nin yanına clawd-gunluk.txt yazar)

        int gunlukSayac;

        void Gunluk(double simdi)
        {
            if (simdi - sonGunluk < 1 || gunlukSayac > 4000 || ayar.Sayi("gunluk", 0f) < 0.5f) return;
            sonGunluk = simdi;
            gunlukSayac++;
            try
            {
                string kutu = kutuVar
                    ? ((int)kutuGoreli.X) + "," + ((int)kutuGoreli.Y) + "," + ((int)kutuGoreli.G) + "," + ((int)kutuGoreli.Yuk)
                    : "yok";
                string pencere = claudeVar
                    ? ((int)claudeCerceve.X) + "," + ((int)claudeCerceve.Y) + "," + ((int)claudeCerceve.G) + "," + ((int)claudeCerceve.Yuk)
                    : "yok";
                string satir = "mod=" + mod + " baglam=" + baglam + " claudeOnde=" + kodAcik + " konum=(" + (int)konum.X + "," + (int)konum.Y + ")"
                    + " ev=(" + (int)ev.X + "," + (int)ev.Y + ") satir=" + aktifSatir + " olcek=" + D.ToString("0.00", CultureInfo.InvariantCulture)
                    + " uyuyor=" + uyuyor + " kutu=" + kutuDurum + " kutuGoreli=" + kutu + " pencere=" + pencere;
                File.AppendAllText(Path.Combine(Application.StartupPath, "clawd-gunluk.txt"), satir + Environment.NewLine, Encoding.UTF8);
            }
            catch (Exception) { }
        }
    }

    // ------------------------------------------------------------------ giriş

    static class Program
    {
        [STAThread]
        static void Main(string[] argumanlar)
        {
            bool ilk;
            using (Mutex tek = new Mutex(true, "ClawdMasaustuKarakteri", out ilk))
            {
                if (!ilk) return;                      // zaten çalışıyor
                try { Win.SetProcessDPIAware(); } catch (Exception) { }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                ClawdPencere clawd = new ClawdPencere(argumanlar);
                Application.ThreadException += delegate(object kaynak, ThreadExceptionEventArgs olay) { clawd.HataYaz(olay.Exception); };
                Application.Run(clawd);
                GC.KeepAlive(tek);
            }
        }
    }
}
