from pathlib import Path
import sys


def main() -> int:
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).with_name('room_setup.gd')
    if not target.exists():
        print(f'ERROR: Không tìm thấy {target}. Hãy đặt script này cạnh room_setup.gd hoặc truyền đường dẫn file.')
        return 2

    original = target.read_text(encoding='utf-8-sig')
    lines = original.splitlines(keepends=True)
    device_key = '_add_device(fuel_container, "Bình nhiên liệu"'
    device_indices = [i for i, line in enumerate(lines) if device_key in line]
    if not device_indices:
        print('ERROR: Không tìm thấy lệnh tạo Bình nhiên liệu; không sửa file.')
        return 3

    # Keep the first declaration and remove any duplicate declarations of the same device.
    for index in reversed(device_indices[1:]):
        del lines[index]

    # Keep only the first guarded Player spawn call. This is a line-level exact edit;
    # the function definition itself is not touched.
    spawn_guard_indices = [i for i, line in enumerate(lines) if line.strip() == 'if move_player_to_spawn:']
    removed_spawn_blocks = 0
    for index in reversed(spawn_guard_indices[1:]):
        if index + 1 < len(lines) and '_move_player_to_spawn()' in lines[index + 1]:
            del lines[index:index + 2]
            removed_spawn_blocks += 1

    updated = ''.join(lines)
    if updated == original:
        print('OK: room_setup.gd đã có một bình nhiên liệu và một lệnh spawn; không cần thay đổi.')
        return 0

    # Guard against accidental removal of the SolSystem bridge.
    if updated.count('var sol_system := SolSystem.new()') != 1:
        print('ERROR: Số lần tạo SolSystem không bằng 1; không ghi file.')
        return 4
    if updated.count('sol_system.bind(_devices)') != 1:
        print('ERROR: Không tìm thấy đúng một lệnh sol_system.bind(_devices); không ghi file.')
        return 5

    target.write_text(updated, encoding='utf-8', newline='')
    print(f'OK: Đã sửa {target}')
    print(f'- Bình nhiên liệu ban đầu: {len(device_indices)} -> 1')
    print(f'- Khối spawn trùng đã xóa: {removed_spawn_blocks}')
    print('- Giữ nguyên SolSystem.new() và sol_system.bind(_devices).')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
