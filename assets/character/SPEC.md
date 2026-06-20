# Karakter Frame-by-Frame Çizim Spec'i

Bu kuralları takip et ki kod kareleri olduğu gibi oynatsın (his katmanı —
eğim/sündürme/oynatma hızı — koddan otomatik gelecek, sen onları çizme).

## Tuval (her kare için AYNI)
- **Boyut:** 64 × 80 px, **şeffaf arkaplan** (PNG).
- **Yön:** karakter **SAĞA** baksın (kod sola dönünce otomatik çeviriyor).
- **Boy:** çöp adam ~50 px yüksekliğinde.
- **Ayak çizgisi (pivot):** ayakların altı **y = 72** pikselinde, yatayda
  **x = 32** (ortalı). ⚠️ Bu nokta TÜM karelerde aynı kalmalı — yoksa
  karakter zıplar gibi titrer. Zıplama karesinde bile "ayak hizası" sabit
  düşün, karakteri yukarı kaydırma; kod havalandırmayı kendi yapıyor.
- **Çizgi:** kurşun/mürekkep, ~3 px, koyu (#242424). Defter estetiği.

## Çizilecek animasyonlar (öncelik sırası)
| Klip   | Kare sayısı | Dosya adı            | Not |
|--------|-------------|----------------------|-----|
| idle   | 2–4         | `idle/idle_1.png`…   | hafif nefes/sallanma |
| run    | 6–8         | `run/run_1.png`…     | EN önemli — sprint döngüsü |
| walk   | 6–8         | `walk/walk_1.png`…   | yavaş yürüme döngüsü |

### Jump arkı (5 ayrı klip — kod sırayla tetikliyor)
| Klasör           | Loop   | Kare | İçerik |
|------------------|--------|------|--------|
| `jump_launch`    | KAPALI | 2–3  | çömelme→itiş, diz bükmesi burada |
| `jump_rise`      | açık   | 1–2  | yükseliş / süzülme |
| `jump_fall_trans`| KAPALI | 1–2  | zirvede çıkış→düşüş dönüşü |
| `jump_fall`      | açık   | 1–2  | düşüş |
| `land`           | KAPALI | 1–2  | iniş çömelmesi |

Akış: kalkış→launch(1 kez)→rise→zirvede fall_trans(1 kez)→fall→yere değince
land(1 kez)→idle/run. Loop flag'lerini koda/`.tres`'e ben koyuyorum.

Sonra (silah/efekt aşamasında): `shoot`, `land`, `hurt`, `draw_pose`.

## Akış
1. Önce sadece **idle (2) + run (6)** çiz, bana ver — pipeline'ı bağlayıp
   canlı test edelim, his oturuyor mu görelim.
2. Sonra walk/jump/fall ekleriz.
3. Kareleri `assets/character/<klip>/<klip>_N.png` olarak koy; gerisini
   (SpriteFrames `.tres`) ben otomatik kurarım.

## Kolaylık: izlenecek referans pozlar
İstersen, beğendiğin o "his"in pozlarını (koşu/yürüme döngüsü, idle, zıplama)
mevcut rig'den **PNG referans olarak çıkarabilirim** — sen üstünden geçerek
(trace) çizersin, böylece elle çizim o iyi hissi aynen taşır. "referansları
çıkar" de yeter.
