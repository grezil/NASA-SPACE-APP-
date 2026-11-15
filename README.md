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

Mẹo: lúc mới vào có bảng **briefing Sol** và game tạm dừng — bấm `Esc` để chơi.

## Cấu trúc

```
Menu.tscn / node_2d.gd     menu chính (PLAY, SAVE GAME, CREDIT)
Music.gd                   autoload nhạc nền: phát từ menu và tiếp tục trong game
game.tscn                  scene chơi chính: Player, HUD (HP/FOOD), Room, MarsMap
  player.gd                di chuyển, sinh tồn, clamp trong room_bounds
  room_setup.gd            dựng nền/tường + 3 loại thiết bị, gắn SolSystem
  sol_system.gd            vòng chơi Sol, nhiệm vụ, nhà kính, mini-game, UI phải
  map.gd                   bản đồ Sao Hỏa (điểm tương tác EVA)
  world_controller.gd      chuyển giữa trong căn cứ và ngoài bề mặt
Global.gd                  autoload: HP/Food, oxy/nước/điện/fuel/credits, inventory, beds, save/load
GameData.gd                bảng dữ liệu cây trồng và vật phẩm
HUD.gd + greenhouse.tscn   scene nhà kính cũ của main (chạy độc lập được, không nối từ menu)
assets/                    ảnh cây trồng, vật phẩm, nền nhà kính
```

## Ghi chú

- **Ảnh bản đồ Sao Hỏa chưa có trong repo**: `map.gd` dò `res://assets/mars/*.png`
  và tự vẽ placeholder nếu thiếu. Thả ảnh vào đó là map có hình ngay.
- `greenhouse.tscn` (bản main cũ) vẫn chạy được bằng `godot --path . res://greenhouse.tscn`
  nhưng nội dung nhà kính hiện tại nằm trong `sol_system.gd`.
- Nhạc: "Dub Hub" — Jimmy Fontanez (no copyright 8-bit music), phát lặp qua autoload
  `Music.gd` (menu −8 dB, trong game −14 dB). Nếu không nghe thấy: kiểm tra Windows
  Volume Mixer cho `Godot`/`4joblesS` và đảm bảo chạy từ `Menu.tscn` (F5).
- Thiết kế chi tiết: [docs/gameplay-plan.md](docs/gameplay-plan.md).
