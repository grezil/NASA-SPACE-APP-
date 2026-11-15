# NASA-SPACE-APP-

Game Godot 4.7 (top-down) về căn cứ / nhà kính trên Sao Hỏa: sinh tồn theo Sol,
trồng trọt, quản lý điện–oxy–nhiên liệu, mini-game và hoạt động ngoài bề mặt.

Repo này là bản hợp nhất của `grezil/NASA-SPACE-APP-` (nhánh main) và fork
`KDSpaceTech/NASA-SPACE-APP-`. Phần chơi được hiện tại là bản của fork
(`game.tscn` + `sol_system.gd`).

## Chạy

1. Cài **Godot 4.7** (bản stable, có .NET cũng được — project không dùng C#).
2. Mở `project.godot` → bấm **F5**.
3. Menu → **Play** → vào căn cứ. **Save Game** ghi `user://save.cfg`,
   lần chơi sau tự khôi phục tiến trình.

## Điều khiển

| Phím | Tác dụng |
|---|---|
| `WASD` / phím mũi tên | Di chuyển |
| `Shift` (giữ) | Chạy (tốn Food nhanh hơn) |
| `E` | Dùng thiết bị đang đứng gần (máy tính, trạm thực phẩm, bình nhiên liệu) |
| `1`–`5` | Chọn mục trong bảng của máy tính |
| `Space` | Tiếp tục / dừng vạch trong mini-game |
| `Esc` | Đóng bảng, đóng briefing |
| `Q` | Bật/tắt chế độ tiết kiệm (ít điện, ít oxy hơn) |
| `T` (giữ) | Tua nhanh thời gian x8 |
| `E` tại cửa **MODULE TRỒNG CÂY** | Vào khoang trồng cây (10 khay) |
| `G` | Vào/ra khoang trồng cây (phím tắt) |
| `E` tại cửa **AIRLOCK: RA SAO HỎA** (tường trái khoang chính) | Ra bề mặt Sao Hỏa |
| `E` tại điểm **Airlock / Về căn cứ** trên bản đồ | Quay vào căn cứ (nạp lại suit) |
| `F6` | Phím tắt ra/vào bề mặt (để kiểm thử nhanh) |

Mẹo: lúc mới vào có bảng **briefing Sol** và game tạm dừng — bấm `Esc` để chơi.

## Cấu trúc

```
Menu.tscn / node_2d.gd     menu chính (PLAY, SAVE GAME, CREDIT)
Music.gd                   autoload nhạc nền: phát từ menu và tiếp tục trong game
game.tscn                  scene chơi chính: Player, HUD (HP/FOOD), Room, MarsMap
  player.gd                di chuyển, sinh tồn, clamp trong room_bounds
  room_setup.gd            dựng nền/tường + 3 loại thiết bị, gắn SolSystem
  sol_system.gd            vòng chơi Sol, nhiệm vụ, nhà kính, mini-game, UI phải
  map.gd                   bản đồ Sao Hỏa (3 điểm tương tác EVA)
growing_room.gd          khoang trồng cây trong tàu: 10 khay 2x5, trồng/tưới/thu hoạch
growing_door.gd          cửa từ khoang chính sang module trồng cây
  world_controller.gd      chuyển giữa trong căn cứ và ngoài bề mặt
Global.gd                  autoload: HP/Food, oxy/nước/điện/fuel/credits, inventory, beds, save/load
GameData.gd                bảng dữ liệu cây trồng và vật phẩm
HUD.gd + greenhouse.tscn   scene nhà kính cũ của main (chạy độc lập được, không nối từ menu)
assets/                    ảnh cây trồng, vật phẩm, nền nhà kính
assets/mars/               Mars_Background, Geology_Lab, Solar_Array, Communications_Relay
assets/bg/greenhouse_growing.png   nền khoang trồng cây (1280x640, 10 ô đất)
```

## Ghi chú

- **Bản đồ Sao Hỏa** đã có đủ ảnh trong `assets/mars/`; `map.gd` tự dò theo tên
  (`Mars_Background.png`, `Geology_Lab.png`, `Solar_Array.png`,
  `Communications_Relay.png`) nên chỉ cần thay file là đổi hình.
- **Khoang trồng cây** (`growing_room.gd`): 10 khay khớp 10 ô đất trong ảnh nền.
  Cây lớn theo thời gian thực, nhả oxy (dùng chung `Global.tick_beds`), tưới tốn
  6 nước/bồn, thu hoạch vào túi — cùng logic với scene nhà kính cũ.
- Đường ra Sao Hỏa: đứng ở cửa **AIRLOCK** bên trái khoang chính, bấm `E`.
  Ngoài bề mặt oxy tụt ~0.8%/giây — quay về bằng điểm **Airlock / Về căn cứ**
  trên bản đồ hoặc `F6`.
- Mars map có 3 điểm hoạt động + 1 điểm airlock: **Geology Lab** (phân tích mẫu → báo cáo), **Solar Array**
  (vệ sinh pin khi bụi), **NASA Data Relay** (gửi báo cáo → +Power, +khoa học, +điểm).
- `greenhouse.tscn` (bản main cũ) vẫn chạy được bằng `godot --path . res://greenhouse.tscn`
  nhưng nội dung nhà kính hiện tại nằm trong `sol_system.gd`.
- Nhạc: "Dub Hub" — Jimmy Fontanez (no copyright 8-bit music), phát lặp qua autoload
  `Music.gd` (menu −8 dB, trong game −14 dB). Nếu không nghe thấy: kiểm tra Windows
  Volume Mixer cho `Godot`/`5joblesS` và đảm bảo chạy từ `Menu.tscn` (F5).
- Thiết kế chi tiết: [docs/gameplay-plan.md](docs/gameplay-plan.md).
