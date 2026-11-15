extends Node
class_name SolSystem
## sol_system.gd v5.4: vòng chơi Happy Valley với sinh tồn, nhà kính, NASA, EVA và lưu tiến trình.
## Giữ tương thích với room_setup.gd và các thiết bị Device hiện có.
## Tự dựng giao diện bằng code (góc trên bên phải), không cần sửa scene.
## room_setup.gd vẫn gọi bind(devices) như cũ (không cần đổi gì ở room_setup.gd).
##
## Phím: E = dùng thiết bị | 1-5 = chọn trong bảng | Esc = đóng bảng | Q = tiết kiệm
##       Space = tiếp tục / dừng vạch trong mini-game | giữ T = tua nhanh x8
##
## Thiết bị:
##  - Máy tính        : quản lý căn cứ, nhiệm vụ Rover/EVA, phòng thí nghiệm và dữ liệu NASA.
##  - Trạm thực phẩm  : nhà kính thủy canh, gieo cây, chờ lớn và thu hoạch.
##  - Bình nhiên liệu : cấp điện, nạp MAV hoặc tinh chế tài nguyên Rover thành nhiên liệu MAV.

@export_group("Thời gian")
@export var sol_seconds := 210.0   # 1 Sol = bao nhiêu giây thực (từ 08:00 đến 22:00)
@export var total_sols := 5
@export var start_hour := 8.0
@export var end_hour := 22.0

@export_group("Cân bằng (chỉnh số ở đây)")
@export var start_power := 55.0
@export var start_oxygen := 100.0
@export var solar_peak := 0.5      # Power/giây lúc nắng đỉnh (12:00)
@export var base_load := 0.28      # Power/giây tiêu thụ ở chế độ thường
@export var eco_load := 0.15       # ... ở chế độ tiết kiệm
@export var lamp_load := 0.12      # Power/giây đèn nhà kính (khi bật)
@export var o2_use := 0.3          # Oxygen/giây phi hành gia dùng
@export var o2_gen := 0.4          # Oxygen/giây máy sinh oxy tạo ra (chế độ thường)
@export var o2_gen_eco := 0.18     # ... (chế độ tiết kiệm)
@export var dust_factor := 0.3     # nắng còn bao nhiêu khi pin bị phủ bụi
@export var dust_hour := 14.0
@export var fuel_power := 25.0     # 1 lần dùng nhiên liệu cho điện bao nhiêu Power
@export var fuel_per_sol := 3      # số lần dùng nhiên liệu mỗi Sol
@export var mav_per_charge := 12.0 # 1 lần dùng nhiên liệu cho tên lửa MAV bao nhiêu %
@export var clean_cost := 4.0
@export var data_cost := 6.0       # Power tốn khi gửi dữ liệu về NASA
@export var rations_per_sol := 2   # khẩu phần khẩn cấp mỗi Sol (+10 FOOD)
@export var o2_damage_per_sec := 3.0

@export_group("EVA – Oxygen ngoài bề mặt Sao Hỏa")
@export var mars_o2_drain_per_sec := 0.80       # O2 tụt nhanh khi đang ở ngoài bề mặt
@export var mars_o2_research_cost := 8.0        # O2 tiêu hao khi bắt đầu phân tích mẫu đá
@export var mars_o2_solar_clean_cost := 5.0     # O2 tiêu hao khi bắt đầu vệ sinh pin
@export var mars_o2_transmission_cost := 2.0    # O2 tiêu hao khi gửi báo cáo NASA
@export var indoor_o2_refill_per_sec := 0.45   # nạp lại bình suit khi ở trong căn cứ
@export var mars_o2_warning_level := 35.0
@export var mars_o2_critical_level := 15.0
@export var mars_o2_damage_per_sec := 5.0
@export var handle_player_death := true         # hiện bảng thất bại khi HP về 0
@export var auto_save_interval := 30.0           # tự lưu theo giây thực
@export var auto_load_save_on_start := true

const SAVE_PATH := "user://happy_valley_save.cfg"
const SAVE_VERSION := 1

# ---------- Dữ liệu nội dung (thêm / sửa ở đây là xong, không cần đụng code logic) ----------

const SOLS := [
	{
		"title": "Landfall", "dust": false, "sun": 1.0, "goal_power": 30.0, "goal_o2": 50.0, "events": 1,
		"brief": "Hạ cánh thành công. Làm quen căn cứ: gieo cây ở nhà kính, kiểm tra máy tính và giữ pin không cạn khi màn đêm buông xuống.",
		"lesson": "Ngân sách điện: điện sinh ra phải bù được điện tiêu thụ, nhất là ban đêm khi pin mặt trời không phát điện.",
	},
	{
		"title": "Dust", "dust": true, "sun": 1.0, "goal_power": 30.0, "goal_o2": 50.0, "events": 1,
		"brief": "Bụi Mars sắp phủ lên pin mặt trời. Hãy chuẩn bị phương án trước khi điện sụt giảm.",
		"lesson": "Bụi làm giảm điện mặt trời. Bảo trì định kỳ quan trọng không kém thiết kế ban đầu.",
	},
	{
		"title": "Breathe", "dust": true, "sun": 1.0, "goal_power": 35.0, "goal_o2": 60.0, "events": 2,
		"brief": "Máy sinh oxy, nhà kính và mọi hệ thống sống còn dùng chung một nguồn điện. Cân bằng giữa tiết kiệm điện và giữ oxy.",
		"lesson": "Single point of failure: khi mất điện, máy oxy ngừng theo, và một lỗi nhỏ kéo cả căn cứ sụp đổ.",
	},
	{
		"title": "Global Storm", "dust": true, "sun": 0.4, "goal_power": 25.0, "goal_o2": 55.0, "events": 2,
		"brief": "Bão bụi toàn cầu che kín bầu trời. Nắng chỉ còn rất ít cả ngày. Nhiên liệu là phao cứu sinh của bạn.",
		"lesson": "Năm 2018 một bão bụi toàn cầu che ánh sáng khiến rover Opportunity (chạy bằng pin mặt trời) ngừng liên lạc.",
	},
	{
		"title": "Launch Window", "dust": true, "sun": 1.0, "goal_power": 35.0, "goal_o2": 60.0, "events": 3,
		"brief": "Cửa sổ phóng về Trái Đất đang mở. Tên lửa MAV cần đủ 100% nhiên liệu. Sol cuối cùng, mọi rủi ro dồn lại.",
		"lesson": "Cửa sổ phóng Trái Đất–Mars chỉ mở khoảng 26 tháng một lần, nên kế hoạch dự phòng quan trọng hơn may mắn.",
	},
]

# Cây trồng theo file Plants List (3 nhóm). grow = số giây (đèn bật) để lớn.
const CROPS := {
	"leaf": {"label": "Rau lá & thảo mộc", "names": ["Cải mizuna", "Xà lách romaine đỏ", "Húng quế", "Thì là"],
		"grow": 45.0, "food": 12.0, "hp": 4.0},
	"fresh": {"label": "Rau quả tươi", "names": ["Cà chua bi", "Ớt", "Dâu tây"],
		"grow": 90.0, "food": 25.0, "hp": 3.0},
	"staple": {"label": "Cây lương thực", "names": ["Khoai tây", "Lúa mì lùn", "Đậu nành"],
		"grow": 150.0, "food": 45.0, "hp": 0.0},
}

# Sự kiện ngẫu nhiên. Mỗi lựa chọn có thể có: power, oxygen, hp, food, mav, science, fuel, eco, lamps,
# dust (false = lau sạch), hours (tua thời gian), blight (true = cây mất 1/2 tiến độ), result (chữ kết quả),
# risk (xác suất thất bại 0-1) + fail {...}, minigame (số lượt) + need (số lần trúng tối thiểu).
const EVENTS := [
	{
		"id": "nasa_order", "min_sol": 1, "title": "LỆNH TỪ MISSION CONTROL",
		"hint": "Mission Control đang chuẩn bị gửi chỉ thị mới.",
		"text": "Trung tâm điều khiển yêu cầu gửi gói dữ liệu khoa học trong cửa sổ liên lạc hiện tại. Việc truyền tốn điện.",
		"lesson": "Tín hiệu Trái Đất–Mars trễ từ vài phút đến hơn 20 phút mỗi chiều, nên phi hành đoàn phải tự quyết định nhiều việc.",
		"options": [
			{"label": "Gửi dữ liệu (-8 Power, +3 điểm khoa học)", "power": -8.0, "science": 3,
				"result": "Dữ liệu đã truyền thành công. Mission Control gửi lời cảm ơn."},
			{"label": "Bỏ qua, tiết kiệm điện", "result": "Bạn từ chối. Mission Control sẽ chờ cửa sổ liên lạc sau."},
		],
	},
	{
		"id": "supply", "min_sol": 1, "title": "THÙNG TIẾP TẾ",
		"hint": "Robot tuần tra phát hiện vật thể lạ gần căn cứ.",
		"text": "Robot tuần tra tìm thấy một thùng tiếp tế cũ. Bạn chỉ kịp mở một ngăn trước khi gió nổi lên.",
		"options": [
			{"label": "Lấy bình nhiên liệu (+1 lần dùng nhiên liệu)", "fuel": 1, "result": "Bạn mang về một bình nhiên liệu nhỏ."},
			{"label": "Lấy thực phẩm (+20 FOOD, +5 HP)", "food": 20.0, "hp": 5.0, "result": "Khẩu phần đóng gói vẫn còn tốt."},
		],
	},
	{
		"id": "dust_devil", "min_sol": 2, "after_dust": true, "title": "LỐC BỤI",
		"hint": "Gió trên cao đang mạnh lên.",
		"text": "Một lốc bụi quét qua bãi pin mặt trời!",
		"lesson": "Trên Mars, gió và lốc bụi đôi khi tự cuốn sạch bụi khỏi pin mặt trời, giúp rover Spirit và Opportunity sống lâu hơn dự kiến.",
		"options": [
			{"label": "Quan sát từ cửa sổ", "dust": false, "science": 1,
				"result": "Lốc bụi cuốn sạch lớp bụi trên pin mặt trời. May mắn hiếm có!"},
		],
	},
	{
		"id": "flare", "min_sol": 2, "title": "BÃO HẠT MẶT TRỜI",
		"hint": "Trạm quan sát Mặt Trời ghi nhận hoạt động tăng mạnh.",
		"text": "Cảnh báo bức xạ! Hạt năng lượng cao từ Mặt Trời sắp quét qua căn cứ. Bạn xử lý thế nào?",
		"lesson": "Mars không có từ trường toàn cầu như Trái Đất nên bức xạ là rủi ro lớn với phi hành gia.",
		"options": [
			{"label": "Tắt thiết bị không thiết yếu (-8 Power, bật tiết kiệm, tắt đèn)", "power": -8.0, "eco": true, "lamps": false,
				"science": 1, "result": "Căn cứ an toàn. Bạn ghi lại số liệu bức xạ."},
			{"label": "Giữ nguyên, hy vọng may mắn (50%: mạch hỏng -30 Power, -15 HP)", "risk": 0.5, "science": 2,
				"fail": {"power": -30.0, "hp": -15.0, "result": "Bức xạ làm cháy mạch điện và gây tổn hại sức khỏe!"},
				"result": "May mắn! Bức xạ đi qua mà không gây hại."},
			{"label": "Trú trong hầm che chắn 2 giờ (mất 2 giờ)", "hours": 2.0,
				"result": "Bạn chờ trong hầm. An toàn nhưng mất 2 giờ làm việc."},
		],
	},
	{
		"id": "meteor", "min_sol": 2, "title": "VI THIÊN THẠCH",
		"hint": "Radar phát hiện mảnh vụn bay thấp.",
		"text": "Một vi thiên thạch xuyên thủng mái module! Oxygen đang thoát ra ngoài.",
		"lesson": "Khí quyển Mars chưa đến 1% khí quyển Trái Đất nên vi thiên thạch ít bị đốt cháy trước khi chạm đất.",
		"options": [
			{"label": "Ra vá mái khẩn cấp (mini-game, -3 Power)", "minigame": 3, "need": 2, "power": -3.0, "science": 1,
				"fail": {"oxygen": -15.0, "result": "Vá hỏng! Oxygen thoát ra ngoài (-15)."},
				"result": "Vết thủng đã được vá kín."},
			{"label": "Bỏ qua (mất ngay 25 Oxygen)", "oxygen": -25.0, "result": "Khí thoát ra qua vết nứt. Bạn mất 25 Oxygen."},
		],
	},
	{
		"id": "blight", "min_sol": 2, "title": "NẤM MỐC NHÀ KÍNH",
		"hint": "Cảm biến độ ẩm nhà kính cho số đo bất thường.",
		"text": "Nấm mốc xuất hiện trên các khay trồng cây!",
		"lesson": "Trồng cây trong không gian cần kiểm soát vi sinh nghiêm ngặt. NASA đã trồng xà lách và ớt trên Trạm Vũ trụ Quốc tế.",
		"options": [
			{"label": "Khử trùng bằng tia UV (-6 Power)", "power": -6.0, "result": "Nấm mốc bị tiêu diệt, cây an toàn."},
			{"label": "Bỏ mặc (cây đang lớn mất 1/2 tiến độ)", "blight": true, "result": "Nấm mốc lan rộng, cây phát triển chậm lại."},
		],
	},
	{
		"id": "overheat", "min_sol": 3, "title": "MÁY OXY QUÁ NHIỆT",
		"hint": "Nhiệt độ máy sinh oxy đang tăng dần.",
		"text": "Máy sinh oxy quá nhiệt và cảnh báo sắp tự ngắt.",
		"lesson": "Thiết bị MOXIE trên Perseverance đã tạo oxy từ khí CO2 Mars, nhưng cần rất nhiều điện và tản nhiệt tốt.",
		"options": [
			{"label": "Dùng 1 lần nhiên liệu làm mát (cần ≥ 1 nhiên liệu)", "fuel": -1, "science": 1,
				"fail": {"oxygen": -20.0, "result": "Không đủ nhiên liệu làm mát, máy tự ngắt (-20 Oxygen)."},
				"result": "Máy nguội dần và chạy ổn định trở lại."},
			{"label": "Bật chế độ tiết kiệm", "eco": true, "result": "Máy nguội dần, nhưng sinh oxy chậm hơn."},
			{"label": "Mặc kệ (60%: máy cháy, -40 Oxygen)", "risk": 0.6,
				"fail": {"oxygen": -40.0, "result": "Máy sinh oxy cháy một phần! (-40 Oxygen)"},
				"result": "Máy vẫn trụ được. Bạn thở phào."},
		],
	},
]

const UPGRADES := [
	{"id": "solar", "label": "Pin hiệu suất cao", "desc": "Điện mặt trời +20%"},
	{"id": "coating", "label": "Lớp phủ chống bụi", "desc": "Khi bị phủ bụi vẫn giữ thêm 25% nắng"},
	{"id": "o2gen", "label": "Máy lọc oxy cải tiến", "desc": "Máy sinh oxy mạnh hơn 25%"},
	{"id": "led", "label": "Đèn LED tiết kiệm", "desc": "Đèn nhà kính tốn điện chỉ bằng một nửa"},
	{"id": "tank", "label": "Bình nhiên liệu dự phòng", "desc": "+1 lần dùng nhiên liệu mỗi Sol"},
	{"id": "robot", "label": "Robot lau bụi tự động", "desc": "Tự lau bụi pin sau 40 giây (vẫn tốn ít điện)"},
	{"id": "load", "label": "Tối ưu tải điện", "desc": "Điện tiêu thụ nền giảm 15%"},
	{"id": "recycle", "label": "Hệ thống tái chế khí", "desc": "Phi hành gia dùng ít oxy hơn 15%"},
]

const MG_W := 560.0   # độ dài thanh mini-game (pixel)

# ---------- Trạng thái ----------

var sol := 1
var hour := 8.0
var power := 55.0
var oxygen := 100.0
var mav_fuel := 0.0
var eco := false
var dust := false
var lamps_on := false
var fuel := 3
var rations := 2
var ate := false
var data_sent := false
var auto_clean := false
var science := 0
var sol_science := 0
var total_score := 0
var trays: Array = []
var upgrades_taken: Array = []

var _t := 0.0
var _player = null
var _dust_fired := false
var _auto_clean_t := 0.0
var _blackout_warned := false
var _low_o2_warned := false
var _critical_o2_warned := false
var _low_power_warned := false
var _world_controller: Node
var _on_mars_surface := false
var _last_surface_state := false
var _harvested_cats: Array = []
var _pending_events: Array = []
var _panel_open := false
var _panel_kind := ""
var _choice_options: Array = []
var _choice_cancelable := false
var _dev_computer = null
var _dev_food = null
var _dev_fuel = null

# ---------- Hoạt động Happy Valley (lấy cảm hứng từ For All Mankind S4) ----------
# Đây là tài nguyên gameplay, không phải mô phỏng khối lượng vật lý chính xác.
var water_ice_kg := 0
var regolith_kg := 0
var rock_samples := 0
var rover_runs := 0
var comms_online := false
# Demo Mars surface loop: research -> NASA reward, plus solar-panel cleaning.
var mars_research_report_ready := false
var mars_reports_created := 0
var mars_reports_sent := 0
var mars_solar_cleaned_this_sol := false
var mars_last_report: Dictionary = {}
var mars_report_history: Array = []
var mars_last_research_result := "Chưa thực hiện"

# mini-game
var _mg_active := false
var _mg_title := ""
var _mg_rounds := 3
var _mg_need := 2
var _mg_round := 0
var _mg_hits := 0
var _mg_pos := 0.0
var _mg_dir := 1.0
var _mg_speed := 1.0
var _mg_zone := 0.5
var _mg_half := 0.14
var _mg_log := ""
var _mg_success := false
var _mg_done: Callable

# giao diện
var _layer: CanvasLayer
var _clock: Label
var _power_bar: ProgressBar
var _o2_bar: ProgressBar
var _mav_bar: ProgressBar
var _data_bar: ProgressBar
var _info_label: Label
var _player_hp_bar: ProgressBar
var _player_food_bar: ProgressBar
var _player_hp_label: Label
var _player_food_label: Label
var _toast_label: Label
var _toast_tween: Tween
var _panel: Panel
var _panel_scroll: ScrollContainer
var _panel_label: Label
var _info_panel: Panel
var _info_scroll: ScrollContainer
var _mg_track_width := MG_W
var _mg_root: Control
var _mg_zone_rect: ColorRect
var _mg_marker: ColorRect
var _autosave_accumulator := 0.0
var _save_loaded := false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if is_inside_tree():
			_save_game_state(false)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # vẫn chạy khi game tạm dừng (để bấm Space đóng bảng)
	power = start_power
	oxygen = start_oxygen
	fuel = fuel_per_sol
	rations = rations_per_sol
	hour = start_hour
	# Khay 1 có sẵn 1 củ khoai tây chín (để Sol đầu có thức ăn), khay 2 trống
	trays = [{"cat": "staple", "name": "Khoai tây", "progress": 1.0}, null]
	_register_eco_input()
	_build_ui()
	_schedule_events()
	_update_ui()
	# Đợi vài khung hình cho Player/HUD khởi tạo xong rồi mới hiện briefing
	await get_tree().process_frame
	await get_tree().process_frame
	_bind_player_hud()
	if auto_load_save_on_start:
		_save_loaded = _load_game_state(false)
	_update_ui()
	if _save_loaded:
		_show_panel("ĐÃ KHÔI PHỤC TIẾN TRÌNH ĐÃ LƯU\n\n" + _briefing_text() + "\n\n[Esc] Đóng", "brief")
	else:
		_show_panel(_briefing_text(), "brief")


## room_setup.gd gọi hàm này, truyền vào danh sách thiết bị.
func bind(devices: Array) -> void:
	for d in devices:
		match str(d.device_name):
			"Máy tính":
				_dev_computer = d
				d.used.connect(_on_computer_used)
			"Trạm thực phẩm":
				_dev_food = d
				d.items = []              # nhà kính do SolSystem điều khiển, không phát đồ ăn trực tiếp nữa
				d.food_amount = 0.0
				d.heal_amount = 0.0
				d.used.connect(_on_food_used)
			"Bình nhiên liệu":
				_dev_fuel = d
				d.used.connect(_on_fuel_used)
		d.cooldown = 0.5
		d.message = " "
	_refresh_device_names()


func _process(delta: float) -> void:
	if _mg_active:
		# Mini-game vẫn tiêu hao O2 khi đang làm việc ngoài bề mặt; phần còn lại của thế giới đang tạm dừng.
		if _is_on_mars_surface():
			_tick_surface_oxygen(delta)
		if _panel_kind == "final":
			return
		_update_minigame(delta)
		_update_ui()
		return
	if _panel_open:
		# Bảng thông tin dừng thời gian căn cứ, nhưng không đóng băng Oxygen suit khi
		# phi hành gia đang ở ngoài bề mặt. Mini-game đã có nhánh tiêu hao riêng phía trên.
		if _panel_kind != "final" and _is_on_mars_surface():
			_tick_surface_oxygen(delta)
			_check_warnings()
			_update_ui()
			_autosave_accumulator += delta
			if _autosave_accumulator >= maxf(auto_save_interval, 5.0):
				_autosave_accumulator = 0.0
				_save_game_state(false)
		return
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
		if _player != null and handle_player_death and _player.has_signal("died"):
			_player.died.connect(_on_player_died)

	var dt := delta * (8.0 if Input.is_physical_key_pressed(KEY_T) else 1.0)
	_t += dt
	hour = start_hour + (_t / sol_seconds) * (end_hour - start_hour)

	var s := _sol_def()
	if bool(s["dust"]) and not _dust_fired and hour >= dust_hour:
		_dust_fired = true
		dust = true
		_auto_clean_t = 40.0
		_toast("BỤI PHỦ PIN MẶT TRỜI! Dùng Máy tính để lau bụi.", Color(1.0, 0.6, 0.25))
		_refresh_device_names()

	# Điện: nắng chỉ có ban ngày (đỉnh lúc 12:00), bụi và bão bụi làm giảm
	var sun := maxf(0.0, sin(PI * (hour - 6.0) / 12.0)) * float(s.get("sun", 1.0))
	var gen := solar_peak * sun * (dust_factor if dust else 1.0)
	var load_now := eco_load if eco else base_load
	if lamps_on:
		load_now += lamp_load
	power = clampf(power + (gen - load_now) * dt, 0.0, 100.0)

	# Nhà kính: cây chỉ lớn khi đèn bật và còn điện
	if lamps_on and power > 0.0:
		_grow_trays(dt)

	# Robot lau bụi tự động (nếu đã nâng cấp)
	if dust and auto_clean:
		_auto_clean_t -= dt
		if _auto_clean_t <= 0.0:
			dust = false
			power = maxf(power - clean_cost, 0.0)
			_toast("Robot tự động đã lau bụi pin (-%d Power)" % int(clean_cost), Color(0.4, 1.0, 0.5))
			_refresh_device_names()

	# Oxy trong căn cứ được máy sinh oxy bổ sung; ngoài bề mặt suit tiêu hao nhanh và không được nạp.
	_on_mars_surface = _is_on_mars_surface()
	if _on_mars_surface != _last_surface_state:
		_last_surface_state = _on_mars_surface
		_low_o2_warned = false
		_critical_o2_warned = false
		if _on_mars_surface:
			_toast("ĐANG Ở NGOÀI SAO HỎA: suit mất %.2f%% Oxygen/giây. Nhấn F6 để về căn cứ." % mars_o2_drain_per_sec, Color(1.0, 0.72, 0.35))
		else:
			_toast("Đã vào căn cứ kín áp suất. Bình Oxygen suit đang được nạp lại.", Color(0.45, 0.85, 1.0))
	if _on_mars_surface:
		_tick_surface_oxygen(dt)
	else:
		var o2_gen_now := 0.0
		var indoor_refill_now := 0.0
		if power > 0.0:
			o2_gen_now = o2_gen_eco if eco else o2_gen
			indoor_refill_now = indoor_o2_refill_per_sec
		# Không có điện thì máy sinh oxy và trạm nạp suit đều dừng; O2 nền tiếp tục bị tiêu thụ.
		oxygen = clampf(oxygen + (o2_gen_now - o2_use + indoor_refill_now) * dt, 0.0, 100.0)
		if oxygen <= 0.0 and _player != null and _player.has_method("take_damage"):
			_player.take_damage(o2_damage_per_sec * dt, false)

	_check_warnings()
	_update_ui()
	_autosave_accumulator += delta
	if _autosave_accumulator >= maxf(auto_save_interval, 5.0):
		_autosave_accumulator = 0.0
		_save_game_state(false)

	# Sự kiện ngẫu nhiên theo giờ
	if not _pending_events.is_empty() and hour >= float(_pending_events[0]["hour"]):
		var pe: Dictionary = _pending_events.pop_front()
		_trigger_event(str(pe["id"]))
		return

	if hour >= end_hour:
		_end_sol()


func _bind_player_hud() -> void:
	var scene := get_tree().current_scene
	if scene == null:
		return

	# Reuse existing HUD nodes from Game.tscn; no scene or hud.gd replacement needed.
	_player_hp_bar = scene.find_child("HPBar", true, false) as ProgressBar
	_player_food_bar = scene.find_child("FoodBar", true, false) as ProgressBar
	_player_hp_label = scene.find_child("HPLabel", true, false) as Label
	_player_food_label = scene.find_child("FoodLabel", true, false) as Label
	_sync_player_hud()
	_layout_ui()


func _on_player_hp_changed(value: float, maximum: float) -> void:
	if _player_hp_bar != null:
		_player_hp_bar.max_value = maxf(maximum, 1.0)
		_player_hp_bar.value = clampf(value, 0.0, _player_hp_bar.max_value)
		_player_hp_bar.modulate = Color(1.0, 0.55, 0.55) if value < maximum * 0.25 else Color.WHITE
	if _player_hp_label != null:
		_player_hp_label.text = "HP %d/%d" % [int(value), int(maximum)]


func _on_player_food_changed(value: float, maximum: float) -> void:
	if _player_food_bar != null:
		_player_food_bar.max_value = maxf(maximum, 1.0)
		_player_food_bar.value = clampf(value, 0.0, _player_food_bar.max_value)
		_player_food_bar.modulate = Color(1.0, 0.65, 0.35) if value < maximum * 0.25 else Color.WHITE
	if _player_food_label != null:
		_player_food_label.text = "FOOD %d/%d" % [int(value), int(maximum)]


func _sync_player_hud() -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player == null:
		return

	# Connect exactly once. Per-frame sync below also covers any HUD created late.
	var hp_callback := Callable(self, "_on_player_hp_changed")
	var food_callback := Callable(self, "_on_player_food_changed")
	if _player.has_signal("hp_changed") and not _player.is_connected("hp_changed", hp_callback):
		_player.connect("hp_changed", hp_callback)
	if _player.has_signal("food_changed") and not _player.is_connected("food_changed", food_callback):
		_player.connect("food_changed", food_callback)
	var died_callback := Callable(self, "_on_player_died")
	if handle_player_death and _player.has_signal("died") and not _player.is_connected("died", died_callback):
		_player.connect("died", died_callback)

	if _player.get("hp") != null and _player.get("max_hp") != null:
		_on_player_hp_changed(float(_player.get("hp")), float(_player.get("max_hp")))
	if _player.get("food") != null and _player.get("max_food") != null:
		_on_player_food_changed(float(_player.get("food")), float(_player.get("max_food")))


func _is_on_mars_surface() -> bool:
	if _world_controller == null or not is_instance_valid(_world_controller):
		var scene := get_tree().current_scene
		if scene != null:
			_world_controller = scene.find_child("WorldController", true, false)
	if _world_controller != null and is_instance_valid(_world_controller) and _world_controller.has_method("is_on_surface"):
		return bool(_world_controller.call("is_on_surface"))
	var scene_root := get_tree().current_scene
	if scene_root != null:
		var mars_map := scene_root.find_child("MarsMap", true, false) as Node2D
		return mars_map != null and mars_map.visible
	return false


func _tick_surface_oxygen(delta: float) -> void:
	if delta <= 0.0:
		return
	oxygen = maxf(oxygen - mars_o2_drain_per_sec * delta, 0.0)
	if oxygen <= 0.0 and _player != null and is_instance_valid(_player) and _player.has_method("take_damage"):
		_player.take_damage(mars_o2_damage_per_sec * delta, false)


func _can_spend_surface_oxygen(amount: float, activity_name: String) -> bool:
	if oxygen < amount:
		_toast("Không đủ Oxygen cho %s (cần %.0f%%, hiện còn %.0f%%). Hãy trở lại căn cứ để nạp suit." % [activity_name, amount, oxygen], Color(1.0, 0.4, 0.4))
		return false
	oxygen = maxf(oxygen - amount, 0.0)
	_update_ui()
	return true


func _sol_def() -> Dictionary:
	return SOLS[clampi(sol - 1, 0, SOLS.size() - 1)]


func _check_warnings() -> void:
	if power <= 0.0 and not _blackout_warned:
		_blackout_warned = true
		_toast("MẤT ĐIỆN! Máy sinh oxy và đèn nhà kính đã ngừng hoạt động.", Color(1.0, 0.3, 0.3))
	elif power > 5.0:
		_blackout_warned = false
	if power < 20.0 and power > 0.0 and not _low_power_warned:
		_low_power_warned = true
		_toast("Pin yếu! Dùng Bình nhiên liệu, tắt đèn nhà kính hoặc bật tiết kiệm (Q).", Color(1.0, 0.85, 0.3))
	elif power >= 30.0:
		_low_power_warned = false

	var surface := _is_on_mars_surface()
	var warning_level := mars_o2_warning_level if surface else 30.0
	if oxygen < warning_level and not _low_o2_warned:
		_low_o2_warned = true
		if surface:
			_toast("OXYGEN EVA THẤP! Hãy hoàn thành việc đang làm và nhấn F6 để trở vào căn cứ.", Color(1.0, 0.65, 0.25))
		else:
			_toast("Oxygen thấp! Kiểm tra máy sinh oxy và nguồn điện.", Color(0.5, 0.8, 1.0))
	elif oxygen >= warning_level + 8.0:
		_low_o2_warned = false

	if surface and oxygen <= mars_o2_critical_level and not _critical_o2_warned:
		_critical_o2_warned = true
		_toast("CẢNH BÁO ĐỎ: BÌNH OXY SẮP CẠN! F6 để trở lại căn cứ ngay!", Color(1.0, 0.25, 0.2))
	elif not surface or oxygen > mars_o2_critical_level + 8.0:
		_critical_o2_warned = false


# ---------- Máy tính (trung tâm điều khiển) ----------

func _on_computer_used(_d, _p) -> void:
	# Menu gốc chỉ có 3 lựa chọn để dễ thao tác bằng phím 1-4.
	var opts: Array = [
		{"label": "Quản lý căn cứ: điện, nhà kính, dữ liệu NASA", "cb": _show_base_ops},
		{"label": "Hoạt động ngoài bề mặt Sao Hỏa", "cb": _show_field_ops},
		{"label": "Phòng thí nghiệm: hồ sơ nghiên cứu", "cb": _show_lab_ops},
		{"label": "Lưu tiến trình hiện tại", "cb": _save_from_computer},
		{"label": "Tải tiến trình đã lưu", "cb": _load_from_computer},
	]
	_show_choices("TRUNG TÂM ĐIỀU HÀNH HAPPY VALLEY", "Chọn công việc cần thực hiện (phím 1–5):", opts, true)


func _show_base_ops() -> void:
	var opts: Array = []
	if dust:
		opts.append({"label": "Vệ sinh pin mặt trời (mini-game, nhận Power thưởng)", "cb": _start_clean})
	else:
		opts.append({"label": "Pin mặt trời: đang sạch", "cb": _toast_clean_ok})
	opts.append({"label": "Đèn nhà kính: %s (bấm để %s)" % [
		"BẬT" if lamps_on else "TẮT", "tắt" if lamps_on else "bật"], "cb": _toggle_lamps})
	opts.append({"label": "Xem báo cáo, dự báo & mục tiêu", "cb": _show_report})
	if data_sent:
		opts.append({"label": "Gửi dữ liệu NASA (đã gửi trong Sol này)", "cb": _toast_already_sent})
	else:
		var cost := data_cost if comms_online else data_cost + 3.0
		var gain := 2 if comms_online else 1
		var comms_note := "liên lạc ổn định" if comms_online else "liên lạc dự phòng, tốn thêm điện"
		opts.append({"label": "Gửi dữ liệu NASA (-%d Power, +%d khoa học; %s)" % [int(cost), gain, comms_note], "cb": _send_data})
	_show_choices("QUẢN LÝ CĂN CỨ", "Điều khiển hệ thống sinh tồn của Happy Valley:", opts, true)


func _show_field_ops() -> void:
	var report_status := _mars_report_status_text()
	var solar_status := "ĐÃ VỆ SINH TRONG SOL NÀY" if mars_solar_cleaned_this_sol else ("BỊ PHỦ BỤI – CẦN VỆ SINH" if dust else "ĐANG SẠCH – CHƯA CẦN VỆ SINH")
	var body := "KHU VỰC NGOÀI SAO HỎA – 3 HOẠT ĐỘNG DEMO\n\n"
	body += "1. GEOLOGY LAB: phân tích mẫu đá và tạo báo cáo khoa học.\n"
	body += "2. SOLAR ARRAY: vệ sinh bụi trên pin để phục hồi hiệu suất điện.\n"
	body += "3. NASA DATA RELAY: gửi báo cáo đã hoàn thành để nhận thưởng.\n\n"
	body += "TRẠNG THÁI HIỆN TẠI\n"
	body += "Báo cáo: %s\nPin mặt trời: %s\nBáo cáo đã tạo: %d | NASA đã nhận: %d\n" % [report_status, solar_status, mars_reports_created, mars_reports_sent]
	body += "Oxygen EVA: -%.2f%%/giây khi ở ngoài; trở vào căn cứ bằng F6 để nạp suit.\n" % mars_o2_drain_per_sec
	body += "Chi phí hoạt động: nghiên cứu %.0f O2, vệ sinh %.0f O2, gửi NASA %.0f O2.\n\n" % [mars_o2_research_cost, mars_o2_solar_clean_cost, mars_o2_transmission_cost]
	body += "Nhấn F6 để ra bề mặt, đến gần từng trạm và nhấn E.\n\n[Esc] Đóng bảng và quay lại game."
	_show_panel(body, "info")

func _show_eva_checklist() -> void:
	var t := "CHECKLIST EVA / AIRLOCK\n\n"
	t += "• Oxygen hiện tại: %d%%\n" % int(oxygen)
	t += "• Power hiện tại: %d%%\n" % int(power)
	t += "• Không nên đi EVA nếu Oxygen dưới 20%% hoặc Power dưới 10%%.\n"
	t += "• Rover dùng pin căn cứ; mini-game mô phỏng thao tác khảo sát và lấy mẫu.\n\n"
	t += "[Space] tiếp tục"
	_show_panel(t, "info")


func _show_lab_ops() -> void:
	var body := "GEOLOGY LAB / HỒ SƠ NGHIÊN CỨU\n\n"
	body += "Nghiên cứu mẫu đá được thực hiện tại trạm Geology Lab ngoài bề mặt Sao Hỏa.\n"
	body += "Chi phí: 3 Power + %.0f Oxygen khi bắt đầu; Oxygen tiếp tục giảm trong mini-game và khi đọc hồ sơ ngoài bề mặt.\n\n" % mars_o2_research_cost
	body += "TRẠNG THÁI: %s\n" % _mars_report_status_text()
	body += "Lần phân tích gần nhất: %s\n" % mars_last_research_result
	body += "Tổng báo cáo đã tạo: %d | NASA đã nhận: %d\n\n" % [mars_reports_created, mars_reports_sent]
	if mars_report_history.is_empty():
		body += "CHƯA CÓ HỒ SƠ NGHIÊN CỨU. Hãy ra bề mặt và hoàn thành mini-game tại Geology Lab.\n"
	else:
		body += "LỊCH SỬ BÁO CÁO (mới nhất ở trên)\n"
		var first_index := maxi(0, mars_report_history.size() - 8)
		for i in range(mars_report_history.size() - 1, first_index - 1, -1):
			var report: Dictionary = mars_report_history[i]
			var report_id := int(report.get("id", i + 1))
			var report_sol := int(report.get("created_sol", 0))
			var created_hour := float(report.get("created_hour", 0.0))
			var status := str(report.get("status", "CHƯA GỬI"))
			body += "\nHV-%03d | Sol %d – %02d:%02d\n" % [report_id, report_sol, int(created_hour), int((created_hour - floor(created_hour)) * 60.0)]
			body += "Kết quả: %s\nTrạng thái: %s\n" % [str(report.get("analysis", "Hoàn tất")), status]
			if status == "NASA ĐÃ NHẬN":
				body += "NASA xác nhận Sol %d | +%d Power, +%d Science, +%d điểm nhiệm vụ\n" % [
					int(report.get("sent_sol", 0)), int(report.get("power_reward", 0)),
					int(report.get("science_reward", 0)), int(report.get("mission_reward", 0))]
			else:
				body += "Đang chờ gửi: đến NASA Data Relay và nhấn E.\n"
		if first_index > 0:
			body += "\nCòn %d báo cáo cũ hơn trong lịch sử đã lưu.\n" % first_index
	body += "\n[Esc] Đóng bảng và quay lại game."
	_show_panel(body, "info")

func _mars_report_status_text() -> String:
	if mars_research_report_ready:
		return "BÁO CÁO ĐÃ HOÀN THÀNH – CHỜ GỬI NASA"
	if not mars_last_report.is_empty() and str(mars_last_report.get("status", "")) == "NASA ĐÃ NHẬN":
		return "BÁO CÁO GẦN NHẤT ĐÃ ĐƯỢC NASA NHẬN"
	if mars_reports_created > 0:
		return "ĐÃ TẠO BÁO CÁO"
	return "CHƯA CÓ BÁO CÁO"

func _toast_comms_online() -> void:
	_toast("Vệ tinh liên lạc đã hoạt động. Dữ liệu NASA được truyền ổn định hơn.", Color(0.4, 1.0, 0.6))


func _toast_no_samples() -> void:
	_toast("Chưa có mẫu địa chất. Hãy chọn Rover trong Nhiệm vụ ngoài căn cứ.", Color(1.0, 0.85, 0.3))


# ---------- Ba hoạt động demo ngoài bề mặt Sao Hỏa ----------

func _start_mars_research() -> void:
	if mars_research_report_ready:
		_toast("Bạn đã có báo cáo nghiên cứu. Hãy đến NASA Data Relay để gửi và nhận thưởng.", Color(1.0, 0.85, 0.3))
		return
	if power < 3.0:
		_toast("Không đủ Power cho Geology Lab (cần 3 Power).", Color(1.0, 0.4, 0.4))
		return
	if not _can_spend_surface_oxygen(mars_o2_research_cost, "Geology Lab"):
		return
	power = maxf(power - 3.0, 0.0)
	_update_ui()
	_start_minigame("GEOLOGY LAB: PHÂN TÍCH MẪU ĐÁ MARS", 3, 2, _on_mars_research_done)


func _on_mars_research_done(ok: bool) -> void:
	if ok:
		mars_research_report_ready = true
		mars_reports_created += 1
		mars_last_research_result = "THÀNH CÔNG"
		_add_science(2)
		mars_last_report = {
			"id": mars_reports_created,
			"created_sol": sol,
			"created_hour": hour,
			"analysis": "THÀNH CÔNG – mẫu đá đã được phân tích",
			"status": "CHỜ GỬI NASA",
			"sent_sol": 0,
			"science_earned": 2,
		}
		mars_report_history.append(mars_last_report.duplicate(true))
		_toast("Nghiên cứu hoàn tất! Báo cáo HV-%03d đã lưu trong Hồ sơ nghiên cứu." % mars_reports_created, Color(0.5, 1.0, 0.6))
	else:
		mars_last_research_result = "CHƯA ĐẠT – cần phân tích lại"
		_toast("Phân tích chưa đạt yêu cầu. Hãy thử lại tại Geology Lab.", Color(1.0, 0.55, 0.4))
	_update_ui()
	_save_game_state(false)
	# Mở hồ sơ ngay sau màn hình kết quả để người chơi thấy báo cáo vừa tạo.
	_show_lab_ops()


func _clean_mars_solar_panels() -> void:
	if mars_solar_cleaned_this_sol:
		_toast("Pin mặt trời đã được vệ sinh trong Sol này.", Color(0.5, 0.9, 1.0))
		return
	if not dust:
		_toast("Pin mặt trời hiện chưa bị phủ bụi. Hãy chờ sự kiện bụi rồi quay lại vệ sinh.", Color(0.65, 0.85, 1.0))
		return
	if not _can_spend_surface_oxygen(mars_o2_solar_clean_cost, "vệ sinh Solar Array"):
		return
	_start_minigame("SOLAR ARRAY: VỆ SINH BỤI TRÊN TẤM PIN", 3, 2, _on_mars_solar_clean_done)


func _on_mars_solar_clean_done(ok: bool) -> void:
	if ok:
		var was_dusty := dust
		dust = false
		mars_solar_cleaned_this_sol = true
		var power_reward := 12.0 if was_dusty else 7.0
		power = minf(power + power_reward, 100.0)
		_add_science(1)
		_toast("Đã vệ sinh pin mặt trời: +%d Power và +1 khoa học. Hiệu suất phát điện đã được khôi phục." % int(power_reward), Color(0.5, 1.0, 0.6))
	else:
		_toast("Vệ sinh chưa hoàn tất. Hãy thử lại tại Solar Array.", Color(1.0, 0.55, 0.4))
	_refresh_device_names()
	_update_ui()
	_save_game_state(false)


func _send_mars_research_to_nasa() -> void:
	if not mars_research_report_ready:
		_show_lab_ops()
		_toast("Chưa có báo cáo đang chờ gửi. Hãy hoàn thành nghiên cứu tại Geology Lab trước.", Color(1.0, 0.75, 0.3))
		return
	var transmission_cost := data_cost
	if power < transmission_cost:
		_toast("Không đủ Power để truyền dữ liệu NASA (cần %d Power)." % int(transmission_cost), Color(1.0, 0.4, 0.4))
		return
	if not _can_spend_surface_oxygen(mars_o2_transmission_cost, "truyền dữ liệu NASA"):
		return
	power = maxf(power - transmission_cost, 0.0)
	var power_before_reward := power
	var actual_power_reward := minf(15.0, 100.0 - power)
	power = minf(power + 15.0, 100.0)
	mars_research_report_ready = false
	mars_reports_sent += 1
	_add_science(5)
	total_score += 8
	if not mars_last_report.is_empty():
		mars_last_report["status"] = "NASA ĐÃ NHẬN"
		mars_last_report["sent_sol"] = sol
		mars_last_report["sent_hour"] = hour
		mars_last_report["transmission_cost"] = transmission_cost
		mars_last_report["power_reward"] = actual_power_reward
		mars_last_report["science_reward"] = 5
		mars_last_report["mission_reward"] = 8
		if not mars_report_history.is_empty():
			mars_report_history[mars_report_history.size() - 1] = mars_last_report.duplicate(true)
	_toast("NASA đã nhận báo cáo! +%d Power thực nhận, +5 khoa học, +8 điểm nhiệm vụ (phí truyền %d Power)." % [int(actual_power_reward), int(transmission_cost)], Color(0.5, 1.0, 0.6))
	_update_ui()
	_save_game_state(false)
	_show_nasa_submission_receipt(power_before_reward, actual_power_reward)


func _show_nasa_submission_receipt(power_before_reward: float, actual_power_reward: float) -> void:
	var report_id := int(mars_last_report.get("id", mars_reports_sent))
	var body := "NASA DATA RELAY – BIÊN NHẬN TRUYỀN DỮ LIỆU\n\n"
	body += "Trạng thái: TRUYỀN THÀNH CÔNG\n"
	body += "Mã báo cáo: HV-%03d\n" % report_id
	body += "NASA xác nhận: Sol %d – %02d:%02d\n\n" % [sol, int(hour), int((hour - floor(hour)) * 60.0)]
	body += "THANH TOÁN / PHẦN THƯỞNG\n"
	body += "Phí truyền: -%d Power\n" % int(data_cost)
	body += "Oxygen suit sử dụng: -%.0f%%\n" % mars_o2_transmission_cost
	body += "Thưởng điện thực nhận: +%d Power\n" % int(actual_power_reward)
	body += "Thưởng khoa học: +5 điểm\n"
	body += "Điểm nhiệm vụ: +8\n\n"
	body += "Power trước thưởng: %d | Power hiện tại: %d\n" % [int(power_before_reward), int(power)]
	body += "Tổng báo cáo NASA đã nhận: %d\n\n[Esc] Đóng biên nhận" % mars_reports_sent
	_show_panel(body, "info")


func _start_rover_survey() -> void:
	if power < 4.0 or oxygen < 6.0:
		_toast("Không đủ dự trữ cho chuyến Rover (cần 4 Power và 6 Oxygen).", Color(1.0, 0.4, 0.4))
		return
	power = maxf(power - 4.0, 0.0)
	oxygen = maxf(oxygen - 6.0, 0.0)
	_update_ui()
	_start_minigame("ROVER: KHẢO SÁT BỀ MẶT MARS", 4, 3, _on_rover_survey_done)


func _on_rover_survey_done(ok: bool) -> void:
	rover_runs += 1
	if ok:
		water_ice_kg += 8
		regolith_kg += 4
		rock_samples += 1
		_add_science(2)
		_toast("Khảo sát thành công: +8 băng nước, +4 regolith, +1 mẫu đá, +2 khoa học.", Color(0.5, 1.0, 0.6))
	else:
		# Rover vẫn tiêu hao điện và thời gian khi chuyến khảo sát không đạt yêu cầu.
		oxygen = maxf(oxygen - 3.0, 0.0)
		_toast("Khảo sát thất bại. Rover quay về an toàn nhưng không thu được mẫu.", Color(1.0, 0.55, 0.4))
	_update_ui()


func _start_comms_repair() -> void:
	if comms_online:
		_toast_comms_online()
		return
	if power < 5.0 or oxygen < 8.0:
		_toast("Không đủ dự trữ cho EVA sửa vệ tinh (cần 5 Power và 8 Oxygen).", Color(1.0, 0.4, 0.4))
		return
	power = maxf(power - 5.0, 0.0)
	oxygen = maxf(oxygen - 8.0, 0.0)
	_update_ui()
	_start_minigame("EVA: SỬA VỆ TINH LIÊN LẠC", 3, 2, _on_comms_repair_done)


func _on_comms_repair_done(ok: bool) -> void:
	if ok:
		comms_online = true
		_add_science(4)
		_toast("EVA thành công! Vệ tinh đã kết nối lại với Mission Control. +4 khoa học.", Color(0.5, 1.0, 0.6))
	else:
		oxygen = maxf(oxygen - 5.0, 0.0)
		_toast("Chưa sửa được vệ tinh. Phi hành gia trở về airlock, mất thêm 5 Oxygen.", Color(1.0, 0.55, 0.4))
	_update_ui()


func _analyze_rock_sample() -> void:
	if rock_samples <= 0:
		_toast_no_samples()
		return
	rock_samples -= 1
	_add_science(3)
	_toast("Phân tích mẫu Mars hoàn tất: +3 điểm khoa học.", Color(0.5, 0.85, 1.0))
	_update_ui()


func _toast_clean_ok() -> void:
	_toast("Pin mặt trời đang sạch, không cần lau.", Color(0.4, 1.0, 0.5))


func _toast_already_sent() -> void:
	_toast("Bạn đã gửi dữ liệu trong Sol này rồi.", Color(1.0, 0.85, 0.3))


func _show_report() -> void:
	_show_panel(_briefing_text(), "info")


func _toggle_lamps() -> void:
	lamps_on = not lamps_on
	_toast("Đèn nhà kính: BẬT (tốn điện, cây sẽ lớn)" if lamps_on else "Đèn nhà kính: TẮT (cây ngừng lớn)", Color(0.7, 1.0, 0.7))
	_update_ui()
	_save_game_state(false)


func _send_data() -> void:
	# Khi vệ tinh chưa sửa, căn cứ vẫn có thể gửi gói khẩn cấp qua kênh dự phòng.
	var cost := data_cost if comms_online else data_cost + 3.0
	var gain := 2 if comms_online else 1
	if power < cost:
		_toast("Không đủ điện để truyền dữ liệu!", Color(1.0, 0.4, 0.4))
		return
	power -= cost
	data_sent = true
	_add_science(gain)
	var msg := "Đã gửi dữ liệu NASA: +%d khoa học" % gain
	if not comms_online:
		msg += " (kênh dự phòng, tốn thêm điện)"
	_toast(msg, Color(0.6, 0.85, 1.0))
	_update_ui()
	_save_game_state(false)


func _start_clean() -> void:
	_clean_mars_solar_panels()


func _on_clean_done(ok: bool) -> void:
	if ok:
		dust = false
		mars_solar_cleaned_this_sol = true
		power = maxf(power - clean_cost, 0.0)
		_toast("Robot đã lau sạch bụi pin mặt trời (-%d Power)" % int(clean_cost), Color(0.4, 1.0, 0.5))
	else:
		power = maxf(power - 2.0, 0.0)
		_toast("Robot bị kẹt! Pin vẫn còn bụi (-2 Power). Thử lại.", Color(1.0, 0.5, 0.4))
	_refresh_device_names()
	_save_game_state(false)


# ---------- Nhà kính (Trạm thực phẩm) ----------

func _on_food_used(_d, _p) -> void:
	var opts: Array = []
	for i in trays.size():
		var tr = trays[i]
		if tr == null:
			opts.append({"label": "Khay %d: TRỐNG - gieo trồng" % (i + 1), "cb": _choose_crop.bind(i)})
		elif float(tr["progress"]) >= 1.0:
			opts.append({"label": "Khay %d: %s - SẴN SÀNG, thu hoạch!" % [i + 1, str(tr["name"])], "cb": _harvest.bind(i)})
		else:
			opts.append({"label": "Khay %d: %s đang lớn (%d%%)" % [i + 1, str(tr["name"]), int(float(tr["progress"]) * 100.0)],
				"cb": _tray_info.bind(i)})
	opts.append({"label": "Khẩu phần khẩn cấp +10 FOOD (còn %d)" % rations, "cb": _eat_ration})
	var body := "Đèn nhà kính: %s. Cây chỉ lớn khi đèn bật (đèn tốn điện)." % ("BẬT" if lamps_on else "TẮT")
	_show_choices("NHÀ KÍNH", body, opts, true)


func _tray_info(i: int) -> void:
	var tr = trays[i]
	if tr == null:
		return
	_toast("%s đang lớn (%d%%). %s" % [str(tr["name"]), int(float(tr["progress"]) * 100.0),
		"" if lamps_on else "Đèn đang TẮT - hãy bật ở Máy tính!"], Color(0.8, 1.0, 0.6))


func _choose_crop(i: int) -> void:
	var opts: Array = []
	for cat in ["leaf", "fresh", "staple"]:
		var c: Dictionary = CROPS[cat]
		opts.append({"label": "%s: lớn sau %d giây, +%d FOOD, +%d HP" % [str(c["label"]), int(c["grow"]), int(c["food"]), int(c["hp"])],
			"cb": _plant.bind(i, cat)})
	_show_choices("CHỌN CÂY TRỒNG", "Cây chỉ lớn khi ĐÈN NHÀ KÍNH bật (cần điện). Cây lớn chậm thì no lâu hơn.", opts, true)


func _plant(i: int, cat: String) -> void:
	var c: Dictionary = CROPS[cat]
	var names: Array = c["names"]
	trays[i] = {"cat": cat, "name": str(names.pick_random()), "progress": 0.0}
	var msg := "Đã gieo %s ở khay %d." % [str(trays[i]["name"]), i + 1]
	if not lamps_on:
		msg += " Nhớ BẬT đèn nhà kính ở Máy tính!"
	_toast(msg, Color(0.6, 1.0, 0.6))
	_refresh_device_names()
	_save_game_state(false)


func _harvest(i: int) -> void:
	var tr: Dictionary = trays[i]
	var cat := str(tr["cat"])
	var c: Dictionary = CROPS[cat]
	if _player != null:
		if _player.has_method("eat"):
			_player.eat(float(c["food"]))
		if float(c["hp"]) > 0.0 and _player.has_method("heal"):
			_player.heal(float(c["hp"]))
	ate = true
	if not (cat in _harvested_cats):
		_harvested_cats.append(cat)
		_add_science(1)
	_toast("Thu hoạch %s: +%d FOOD" % [str(tr["name"]), int(c["food"])], Color(0.5, 1.0, 0.5))
	trays[i] = null
	_refresh_device_names()
	_save_game_state(false)


func _eat_ration() -> void:
	if rations <= 0:
		_toast("Hết khẩu phần khẩn cấp trong Sol này!", Color(1.0, 0.4, 0.4))
		return
	rations -= 1
	if _player != null and _player.has_method("eat"):
		_player.eat(10.0)
	_toast("Ăn khẩu phần khẩn cấp: +10 FOOD (không tính vào mục tiêu ăn uống)", Color(1.0, 0.9, 0.5))
	_save_game_state(false)


func _grow_trays(dt: float) -> void:
	for tr in trays:
		if tr == null or float(tr["progress"]) >= 1.0:
			continue
		var c: Dictionary = CROPS[str(tr["cat"])]
		tr["progress"] = minf(float(tr["progress"]) + dt / float(c["grow"]), 1.0)
		if float(tr["progress"]) >= 1.0:
			_toast("%s ở nhà kính đã chín! Ra Nhà kính để thu hoạch." % str(tr["name"]), Color(0.6, 1.0, 0.6))
			_refresh_device_names()


func _tray_summary() -> String:
	var parts := PackedStringArray()
	for i in trays.size():
		var tr = trays[i]
		if tr == null:
			parts.append("K%d trống" % (i + 1))
		elif float(tr["progress"]) >= 1.0:
			parts.append("K%d CHÍN" % (i + 1))
		else:
			parts.append("K%d %d%%" % [i + 1, int(float(tr["progress"]) * 100.0)])
	return " | ".join(parts)


# ---------- Bình nhiên liệu: cấp điện hay phóng tên lửa? ----------

func _on_fuel_used(_d, _p) -> void:
	var opts: Array = []
	if fuel > 0:
		opts.append({"label": "Cấp điện cho căn cứ (+%d Power) - dùng 1 bình" % int(fuel_power), "cb": _fuel_to_power})
		opts.append({"label": "Dồn vào tên lửa MAV (+%d%%) - dùng 1 bình" % int(mav_per_charge), "cb": _fuel_to_mav})
	if water_ice_kg >= 8 and regolith_kg >= 4:
		opts.append({"label": "Xưởng tinh chế: +%d%% MAV (8 băng nước + 4 regolith + 8 Power)" % int(mav_per_charge), "cb": _refine_mav_propellant})
	if opts.is_empty():
		_toast("Chưa có bình nhiên liệu hoặc tài nguyên để tinh chế. Dùng Rover để tìm băng nước và regolith.", Color(1.0, 0.6, 0.35))
		return
	var body := "Bình nhiên liệu còn %d lần. MAV hiện %d%%." % [fuel, int(mav_fuel)]
	body += "\nTinh chế tài nguyên là cách bổ sung MAV ngoài số bình dự trữ."
	_show_choices("XƯỞNG NHIÊN LIỆU HAPPY VALLEY", body, opts, true)


func _refine_mav_propellant() -> void:
	if water_ice_kg < 8 or regolith_kg < 4 or power < 8.0:
		_toast("Thiếu nguyên liệu hoặc điện: cần 8 băng nước, 4 regolith và 8 Power.", Color(1.0, 0.4, 0.4))
		return
	water_ice_kg -= 8
	regolith_kg -= 4
	power = maxf(power - 8.0, 0.0)
	mav_fuel = minf(mav_fuel + mav_per_charge, 100.0)
	_add_science(1)
	_toast("Tinh chế thành công: MAV +%d%%, +1 khoa học." % int(mav_per_charge), Color(0.75, 0.55, 1.0))
	_update_ui()
	_save_game_state(false)


func _fuel_to_power() -> void:
	if fuel <= 0:
		_toast("Không còn bình nhiên liệu.", Color(1.0, 0.4, 0.4))
		return
	fuel -= 1
	power = minf(power + fuel_power, 100.0)
	_toast("Nạp nhiên liệu: +%d Power" % int(fuel_power), Color(1.0, 0.9, 0.3))
	_refresh_device_names()
	_save_game_state(false)


func _fuel_to_mav() -> void:
	if fuel <= 0:
		_toast("Không còn bình nhiên liệu.", Color(1.0, 0.4, 0.4))
		return
	fuel -= 1
	mav_fuel = minf(mav_fuel + mav_per_charge, 100.0)
	_toast("Tên lửa MAV: %d%% nhiên liệu" % int(mav_fuel), Color(0.8, 0.55, 1.0))
	_refresh_device_names()
	_save_game_state(false)


func _refresh_device_names() -> void:
	if _dev_fuel != null:
		_dev_fuel.device_name = "Bình nhiên liệu (còn %d)" % fuel
	if _dev_computer != null:
		_dev_computer.device_name = "Máy tính: LAU BỤI PIN" if dust else "Máy tính"
	if _dev_food != null:
		var has_ripe := false
		for tr in trays:
			if tr != null and float(tr["progress"]) >= 1.0:
				has_ripe = true
		_dev_food.device_name = "Nhà kính: THU HOẠCH" if has_ripe else "Nhà kính"


func _add_science(n: int) -> void:
	science += n
	sol_science += n


# ---------- Save / Load ----------

func _save_from_computer() -> void:
	if _save_game_state(true):
		_toast("Đã lưu tiến trình Happy Valley.", Color(0.5, 1.0, 0.6))
	else:
		_toast("Không thể lưu game. Kiểm tra quyền ghi thư mục user://.", Color(1.0, 0.4, 0.4))


func _load_from_computer() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		_toast("Chưa có file lưu. Hãy chọn Lưu tiến trình trước.", Color(1.0, 0.75, 0.3))
		return
	if _load_game_state(true):
		_show_panel("ĐÃ TẢI TIẾN TRÌNH\n\n" + _briefing_text() + "\n\n[Esc] Đóng", "brief")
	else:
		_toast("File lưu không hợp lệ hoặc không tương thích.", Color(1.0, 0.4, 0.4))


func _save_game_state(show_warning: bool = false) -> bool:
	var player_hp := 100.0
	var player_food := 100.0
	var player_position := Vector2.ZERO
	var player_facing := "down"
	if _player != null and is_instance_valid(_player):
		if _player.get("is_dead") != null and bool(_player.get("is_dead")):
			return false # Không ghi đè checkpoint tốt bằng trạng thái đã Game Over.
		if _player.get("hp") != null:
			player_hp = float(_player.get("hp"))
		if _player.get("food") != null:
			player_food = float(_player.get("food"))
		player_position = _player.global_position
		if _player.get("facing") != null:
			player_facing = str(_player.get("facing"))

	var state: Dictionary = {
		"version": SAVE_VERSION,
		"sol": sol, "hour": hour, "elapsed_sol_seconds": _t,
		"power": power, "oxygen": oxygen, "mav_fuel": mav_fuel,
		"eco": eco, "dust": dust, "lamps_on": lamps_on,
		"solar_peak": solar_peak, "dust_factor": dust_factor,
		"o2_gen": o2_gen, "o2_gen_eco": o2_gen_eco,
		"lamp_load": lamp_load, "fuel_per_sol": fuel_per_sol,
		"base_load": base_load, "eco_load": eco_load, "o2_use": o2_use,
		"dust_fired": _dust_fired, "auto_clean_timer": _auto_clean_t,
		"fuel": fuel, "rations": rations, "ate": ate, "data_sent": data_sent,
		"auto_clean": auto_clean, "science": science, "sol_science": sol_science,
		"total_score": total_score, "trays": trays.duplicate(true),
		"upgrades_taken": upgrades_taken.duplicate(true),
		"harvested_cats": _harvested_cats.duplicate(true),
		"pending_events": _pending_events.duplicate(true),
		"water_ice_kg": water_ice_kg, "regolith_kg": regolith_kg,
		"rock_samples": rock_samples, "rover_runs": rover_runs,
		"comms_online": comms_online,
		"mars_research_report_ready": mars_research_report_ready,
		"mars_reports_created": mars_reports_created, "mars_reports_sent": mars_reports_sent,
		"mars_solar_cleaned_this_sol": mars_solar_cleaned_this_sol,
		"mars_last_report": mars_last_report.duplicate(true),
		"mars_report_history": mars_report_history.duplicate(true),
		"mars_last_research_result": mars_last_research_result,
		"player_hp": player_hp, "player_food": player_food,
		"player_position": player_position, "player_facing": player_facing,
		"on_mars_surface": _is_on_mars_surface(),
	}
	var config := ConfigFile.new()
	config.set_value("save", "state", state)
	var error := config.save(SAVE_PATH)
	if error != OK:
		if show_warning:
			push_warning("SolSystem: cannot save game, error %s" % error_string(error))
		return false
	return true


func _load_game_state(show_feedback: bool = false) -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var config := ConfigFile.new()
	var error := config.load(SAVE_PATH)
	if error != OK:
		push_warning("SolSystem: cannot load save, error %s" % error_string(error))
		return false
	var raw_state: Variant = config.get_value("save", "state", {})
	if not (raw_state is Dictionary):
		return false
	var state: Dictionary = raw_state
	if int(state.get("version", -1)) != SAVE_VERSION:
		push_warning("SolSystem: save version is not supported")
		return false
	if float(state.get("player_hp", 100.0)) <= 0.0:
		push_warning("SolSystem: save contains zero HP; refusing to restore a failed run.")
		return false

	sol = clampi(int(state.get("sol", 1)), 1, total_sols)
	hour = clampf(float(state.get("hour", start_hour)), start_hour, end_hour)
	_t = clampf(float(state.get("elapsed_sol_seconds", 0.0)), 0.0, sol_seconds)
	power = clampf(float(state.get("power", start_power)), 0.0, 100.0)
	oxygen = clampf(float(state.get("oxygen", start_oxygen)), 0.0, 100.0)
	mav_fuel = clampf(float(state.get("mav_fuel", 0.0)), 0.0, 100.0)
	eco = bool(state.get("eco", false))
	dust = bool(state.get("dust", false))
	lamps_on = bool(state.get("lamps_on", false))
	solar_peak = maxf(0.0, float(state.get("solar_peak", solar_peak)))
	dust_factor = clampf(float(state.get("dust_factor", dust_factor)), 0.0, 1.0)
	o2_gen = maxf(0.0, float(state.get("o2_gen", o2_gen)))
	o2_gen_eco = maxf(0.0, float(state.get("o2_gen_eco", o2_gen_eco)))
	lamp_load = maxf(0.0, float(state.get("lamp_load", lamp_load)))
	fuel_per_sol = maxi(0, int(state.get("fuel_per_sol", fuel_per_sol)))
	base_load = maxf(0.0, float(state.get("base_load", base_load)))
	eco_load = maxf(0.0, float(state.get("eco_load", eco_load)))
	o2_use = maxf(0.0, float(state.get("o2_use", o2_use)))
	_dust_fired = bool(state.get("dust_fired", dust and hour >= dust_hour))
	_auto_clean_t = maxf(0.0, float(state.get("auto_clean_timer", 0.0)))
	fuel = maxi(0, int(state.get("fuel", fuel_per_sol)))
	rations = maxi(0, int(state.get("rations", rations_per_sol)))
	ate = bool(state.get("ate", false))
	data_sent = bool(state.get("data_sent", false))
	auto_clean = bool(state.get("auto_clean", false))
	science = maxi(0, int(state.get("science", 0)))
	sol_science = maxi(0, int(state.get("sol_science", 0)))
	total_score = maxi(0, int(state.get("total_score", 0)))
	water_ice_kg = maxi(0, int(state.get("water_ice_kg", 0)))
	regolith_kg = maxi(0, int(state.get("regolith_kg", 0)))
	rock_samples = maxi(0, int(state.get("rock_samples", 0)))
	rover_runs = maxi(0, int(state.get("rover_runs", 0)))
	comms_online = bool(state.get("comms_online", false))
	mars_research_report_ready = bool(state.get("mars_research_report_ready", false))
	mars_reports_created = maxi(0, int(state.get("mars_reports_created", 0)))
	mars_reports_sent = maxi(0, int(state.get("mars_reports_sent", 0)))
	mars_solar_cleaned_this_sol = bool(state.get("mars_solar_cleaned_this_sol", false))
	mars_last_research_result = str(state.get("mars_last_research_result", "Chưa thực hiện"))
	var saved_trays: Variant = state.get("trays", trays)
	if saved_trays is Array and saved_trays.size() == trays.size():
		trays = saved_trays.duplicate(true)
	var saved_upgrades: Variant = state.get("upgrades_taken", [])
	if saved_upgrades is Array:
		upgrades_taken = saved_upgrades.duplicate(true)
	var saved_harvested: Variant = state.get("harvested_cats", [])
	if saved_harvested is Array:
		_harvested_cats = saved_harvested.duplicate(true)
	var saved_events: Variant = state.get("pending_events", [])
	if saved_events is Array:
		_pending_events = saved_events.duplicate(true)
	var saved_report: Variant = state.get("mars_last_report", {})
	if saved_report is Dictionary:
		mars_last_report = saved_report.duplicate(true)
	var saved_history: Variant = state.get("mars_report_history", [])
	if saved_history is Array:
		mars_report_history = saved_history.duplicate(true)

	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null and is_instance_valid(_player):
		var player_max_hp := float(_player.get("max_hp")) if _player.get("max_hp") != null else 100.0
		var player_max_food := float(_player.get("max_food")) if _player.get("max_food") != null else 100.0
		var restored_hp := clampf(float(state.get("player_hp", player_max_hp)), 0.0, player_max_hp)
		_player.set("hp", restored_hp)
		_player.set("food", clampf(float(state.get("player_food", player_max_food)), 0.0, player_max_food))
		if _player.get("is_dead") != null:
			_player.set("is_dead", false)
		if _player.has_signal("hp_changed"):
			_player.emit_signal("hp_changed", float(_player.get("hp")), player_max_hp)
		if _player.has_signal("food_changed"):
			_player.emit_signal("food_changed", float(_player.get("food")), player_max_food)

	var desired_surface := bool(state.get("on_mars_surface", false))
	var scene := get_tree().current_scene
	if scene != null:
		_world_controller = scene.find_child("WorldController", true, false)
		if _world_controller != null and _world_controller.has_method("is_on_surface"):
			var currently_surface := bool(_world_controller.call("is_on_surface"))
			if desired_surface and not currently_surface and _world_controller.has_method("enter_exterior"):
				_world_controller.call("enter_exterior")
			elif not desired_surface and currently_surface and _world_controller.has_method("return_to_interior"):
				_world_controller.call("return_to_interior")
		var saved_position: Variant = state.get("player_position", null)
		if saved_position is Vector2 and _player != null and is_instance_valid(_player):
			_player.global_position = saved_position
			if _player.get("facing") != null:
				_player.set("facing", str(state.get("player_facing", "down")))
			var camera := get_viewport().get_camera_2d()
			if camera != null:
				camera.reset_smoothing()

	# Giữ nguyên cờ _dust_fired đã lưu: nếu pin đã được vệ sinh sau sự kiện bụi,
	# không kích hoạt lại cùng sự kiện khi tiếp tục game.	
	_blackout_warned = power <= 0.0
	_low_o2_warned = false
	_critical_o2_warned = false
	_low_power_warned = power < 20.0
	_on_mars_surface = _is_on_mars_surface()
	_last_surface_state = _on_mars_surface
	_refresh_device_names()
	_update_ui()
	if show_feedback:
		_toast("Đã tải tiến trình Happy Valley.", Color(0.5, 1.0, 0.6))
	return true


# ---------- Sự kiện ngẫu nhiên ----------

func _event_def(id: String) -> Dictionary:
	for ev in EVENTS:
		if str(ev["id"]) == id:
			return ev
	return {}


func _schedule_events() -> void:
	_pending_events.clear()
	var s := _sol_def()
	var pool: Array = []
	for ev in EVENTS:
		if int(ev["min_sol"]) > sol:
			continue
		if bool(ev.get("after_dust", false)) and not bool(s["dust"]):
			continue
		pool.append(ev)
	pool.shuffle()
	var n := mini(int(s.get("events", 1)), pool.size())
	for i in n:
		var ev: Dictionary = pool[i]
		var h := randf_range(start_hour + 1.5, end_hour - 2.5)
		if bool(ev.get("after_dust", false)):
			h = randf_range(dust_hour + 0.5, end_hour - 1.5)
		_pending_events.append({"hour": h, "id": str(ev["id"]), "hinted": randf() < 0.6})
	_pending_events.sort_custom(func(a, b): return float(a["hour"]) < float(b["hour"]))


func _trigger_event(id: String) -> void:
	var ev := _event_def(id)
	if ev.is_empty():
		return
	var opts: Array = []
	for opt in ev["options"]:
		opts.append({"label": str(opt["label"]), "cb": _resolve_option.bind(ev, opt)})
	_show_choices("!! SỰ KIỆN: %s" % str(ev["title"]), str(ev["text"]), opts, false)


func _resolve_option(ev: Dictionary, opt: Dictionary) -> void:
	if opt.has("minigame"):
		_start_minigame(str(ev["title"]), int(opt["minigame"]), int(opt.get("need", 1)), _on_event_minigame.bind(ev, opt))
		return
	var failed := opt.has("risk") and randf() < float(opt["risk"])
	if int(opt.get("fuel", 0)) < 0 and fuel < -int(opt["fuel"]):
		failed = true
	_finish_option(ev, opt, failed)


func _on_event_minigame(ok: bool, ev: Dictionary, opt: Dictionary) -> void:
	_finish_option(ev, opt, not ok)


func _finish_option(ev: Dictionary, opt: Dictionary, failed: bool) -> void:
	var eff: Dictionary = opt
	if failed:
		eff = opt.get("fail", {"result": "Mọi chuyện không suôn sẻ."})
	_apply_effects(eff)
	_save_game_state(false)
	var t := "THẤT BẠI\n\n" if failed else "KẾT QUẢ\n\n"
	t += str(eff.get("result", ""))
	if ev.has("lesson"):
		t += "\n\nBÀI HỌC: " + str(ev["lesson"])
	t += "\n\n[Space] tiếp tục"
	_show_panel(t, "info")


func _apply_effects(e: Dictionary) -> void:
	if e.has("power"):
		power = clampf(power + float(e["power"]), 0.0, 100.0)
	if e.has("oxygen"):
		oxygen = clampf(oxygen + float(e["oxygen"]), 0.0, 100.0)
	if e.has("hp") and _player != null:
		var v := float(e["hp"])
		if v < 0.0 and _player.has_method("take_damage"):
			_player.take_damage(-v)
		elif v > 0.0 and _player.has_method("heal"):
			_player.heal(v)
	if e.has("food") and _player != null and _player.has_method("eat"):
		_player.eat(float(e["food"]))
	if e.has("mav"):
		mav_fuel = clampf(mav_fuel + float(e["mav"]), 0.0, 100.0)
	if e.has("science"):
		_add_science(int(e["science"]))
	if e.has("fuel"):
		fuel = maxi(fuel + int(e["fuel"]), 0)
	if e.has("eco"):
		eco = bool(e["eco"])
	if e.has("lamps"):
		lamps_on = bool(e["lamps"])
	if e.has("dust"):
		dust = bool(e["dust"])
	if e.has("hours"):
		_t += float(e["hours"]) * sol_seconds / (end_hour - start_hour)
	if e.has("blight") and bool(e["blight"]):
		for tr in trays:
			if tr != null and float(tr["progress"]) < 1.0:
				tr["progress"] = float(tr["progress"]) * 0.5
	_refresh_device_names()
	_update_ui()


func _on_player_died() -> void:
	_show_panel("NHIỆM VỤ THẤT BẠI\n\nPhi hành gia đã gục ngã trên Mars.\n\n[Space] chơi lại", "final")


# ---------- Mini-game canh thời điểm ----------

func _start_minigame(title: String, rounds: int, need: int, on_done: Callable) -> void:
	_mg_title = title
	_mg_rounds = rounds
	_mg_need = need
	_mg_done = on_done
	_mg_round = 0
	_mg_hits = 0
	_mg_log = ""
	_mg_next_round()
	_show_panel("", "minigame")
	_mg_root.visible = true
	_mg_active = true
	_layout_ui()
	_mg_refresh_text()


func _mg_next_round() -> void:
	_mg_round += 1
	_mg_pos = 0.0
	_mg_dir = 1.0
	_mg_speed = 0.9 + 0.3 * float(_mg_round - 1)
	_mg_half = maxf(0.14 - 0.03 * float(_mg_round - 1), 0.06)
	_mg_zone = randf_range(0.25, 0.75)
	_mg_zone_rect.position.x = (_mg_zone - _mg_half) * _mg_track_width
	_mg_zone_rect.size.x = _mg_half * 2.0 * _mg_track_width


func _mg_refresh_text() -> void:
	_panel_label.text = "%s\n\nLượt %d/%d   |   Trúng: %d (cần %d)\n\nBấm [Space] khi vạch trắng nằm trong vùng XANH!\n\n%s" % [
		_mg_title, _mg_round, _mg_rounds, _mg_hits, _mg_need, _mg_log]


func _update_minigame(delta: float) -> void:
	_mg_pos += _mg_dir * _mg_speed * delta
	if _mg_pos >= 1.0:
		_mg_pos = 1.0
		_mg_dir = -1.0
	elif _mg_pos <= 0.0:
		_mg_pos = 0.0
		_mg_dir = 1.0
	_mg_marker.position.x = _mg_pos * _mg_track_width - 3.0


func _mg_press() -> void:
	var hit := absf(_mg_pos - _mg_zone) <= _mg_half
	if hit:
		_mg_hits += 1
	_mg_log = "Lượt %d: %s" % [_mg_round, "TRÚNG!" if hit else "TRƯỢT"]
	if _mg_round >= _mg_rounds:
		_mg_active = false
		_mg_root.visible = false
		_mg_success = _mg_hits >= _mg_need
		_panel_kind = "mg_result"
		_panel_label.text = "%s\n\nKẾT QUẢ: %d/%d lần trúng — %s\n\n[Space] tiếp tục" % [
			_mg_title, _mg_hits, _mg_rounds, "THÀNH CÔNG" if _mg_success else "THẤT BẠI"]
		_layout_ui()
	else:
		_mg_next_round()
		_mg_refresh_text()


# ---------- Hết Sol, nâng cấp, kết thúc ----------

func _end_sol() -> void:
	var s := _sol_def()
	var p_ok := power >= float(s["goal_power"])
	var o_ok := oxygen >= float(s["goal_o2"])
	var f_ok := ate
	var hp_ratio := 1.0
	if _player != null:
		hp_ratio = float(_player.get("hp")) / maxf(float(_player.get("max_hp")), 1.0)
	var bonus := mini(sol_science * 3, 10)
	var score := (10 if p_ok else 0) + (10 if o_ok else 0) + (10 if f_ok else 0) + int(round(hp_ratio * 10.0)) + bonus
	total_score += score
	_save_game_state(false)

	var t := "SOL %d HOÀN THÀNH — %s\n\n" % [sol, str(s["title"])]
	t += "Pin: %d%%   %s\n" % [int(power), "ĐẠT" if p_ok else "CHƯA ĐẠT"]
	t += "Oxygen: %d%%   %s\n" % [int(oxygen), "ĐẠT" if o_ok else "CHƯA ĐẠT"]
	t += "Thu hoạch nhà kính: %s\n" % ("ĐẠT" if f_ok else "CHƯA ĐẠT")
	t += "Sức khỏe: %d/100\n" % int(hp_ratio * 100.0)
	t += "Khoa học trong Sol: %d (thưởng +%d)\n" % [sol_science, bonus]
	t += "Tên lửa MAV: %d%%\n\n" % int(mav_fuel)
	t += "Điểm Sol: %d/50\n\n" % score
	t += "BÀI HỌC: %s\n\n" % str(s["lesson"])

	if sol >= total_sols:
		var launch_ok := mav_fuel >= 100.0
		var max_total := 50 * total_sols + 50
		var final_total := total_score + (50 if launch_ok else 0)
		var pct := float(final_total) / float(max_total) * 100.0
		var rank := "Stranded Survivor"
		if launch_ok:
			rank = "Cadet"
			if pct >= 75.0:
				rank = "Mission Commander"
			elif pct >= 50.0:
				rank = "Flight Engineer"
		if launch_ok:
			t += "TÊN LỬA MAV PHÓNG THÀNH CÔNG! Bạn đã trở về Trái Đất.\n"
		else:
			t += "MAV chưa đủ nhiên liệu. Bạn mắc kẹt trên Mars, chờ tàu tiếp tế.\n"
		t += "Tổng điểm: %d/%d (%d%%)\nXẾP HẠNG: %s\n\n[Space] chơi lại" % [final_total, max_total, int(pct), rank]
		_show_panel(t, "final")
	else:
		t += "[Space] chọn nâng cấp cho Sol %d" % (sol + 1)
		_show_panel(t, "summary")


func _offer_upgrades() -> void:
	var pool: Array = []
	for u in UPGRADES:
		if not (str(u["id"]) in upgrades_taken):
			pool.append(u)
	pool.shuffle()
	if pool.is_empty():
		_next_sol()
		return
	var opts: Array = []
	for i in mini(3, pool.size()):
		var u: Dictionary = pool[i]
		opts.append({"label": "%s: %s" % [str(u["label"]), str(u["desc"])], "cb": _take_upgrade.bind(str(u["id"]))})
	_show_choices("NÂNG CẤP CĂN CỨ", "Chọn 1 nâng cấp cho các Sol tiếp theo:", opts, false)


func _take_upgrade(id: String) -> void:
	upgrades_taken.append(id)
	match id:
		"solar":
			solar_peak *= 1.2
		"coating":
			dust_factor = minf(dust_factor + 0.25, 0.95)
		"o2gen":
			o2_gen *= 1.25
			o2_gen_eco *= 1.25
		"led":
			lamp_load *= 0.5
		"tank":
			fuel_per_sol += 1
		"robot":
			auto_clean = true
		"load":
			base_load *= 0.85
			eco_load *= 0.85
		"recycle":
			o2_use *= 0.85
	_next_sol()


func _next_sol() -> void:
	sol += 1
	_t = 0.0
	hour = start_hour
	dust = false
	_dust_fired = false
	mars_solar_cleaned_this_sol = false
	ate = false
	data_sent = false
	sol_science = 0
	fuel = fuel_per_sol
	rations = rations_per_sol
	_schedule_events()
	_refresh_device_names()
	_update_ui()
	_save_game_state(false)
	_show_panel(_briefing_text(), "brief")


func _briefing_text() -> String:
	var s := _sol_def()
	var t := "SOL %d/%d — %s\n\n%s\n\n" % [sol, total_sols, str(s["title"]), str(s["brief"])]
	t += "MỤC TIÊU LÚC %02d:00:\n" % int(end_hour)
	t += "  - Pin từ %d%% trở lên\n" % int(float(s["goal_power"]))
	t += "  - Oxygen từ %d%% trở lên\n" % int(float(s["goal_o2"]))
	t += "  - Thu hoạch ít nhất 1 lần ở Nhà kính\n"
	if sol >= total_sols:
		t += "  - Tên lửa MAV đạt 100%% nhiên liệu (hiện %d%%)\n" % int(mav_fuel)
	t += "\nDỰ BÁO:\n"
	if bool(s["dust"]):
		t += "  - Bụi phủ pin mặt trời lúc %02d:00\n" % int(dust_hour)
	if float(s.get("sun", 1.0)) < 1.0:
		t += "  - Bão bụi toàn cầu: nắng chỉ còn %d%%\n" % int(float(s["sun"]) * 100.0)
	var any_hint := false
	for pe in _pending_events:
		if bool(pe["hinted"]):
			t += "  - NASA: %s\n" % str(_event_def(str(pe["id"])).get("hint", ""))
			any_hint = true
	if not any_hint:
		t += "  - Chưa có cảnh báo đặc biệt (vẫn có thể có bất ngờ)\n"
	t += "\n3 HOẠT ĐỘNG NGOÀI SAO HỎA:\n"
	t += "  1. Geology Lab: nghiên cứu mẫu đá, tạo báo cáo khoa học.\n"
	t += "  2. Solar Array: vệ sinh pin mặt trời, phục hồi Power.\n"
	t += "  3. NASA Data Relay: gửi báo cáo để nhận thưởng.\n"
	t += "  Báo cáo: %s | Pin: %s | Đã gửi NASA: %d\n" % [
		_mars_report_status_text(),
		"ĐÃ VỆ SINH" if mars_solar_cleaned_this_sol else "CHƯA VỆ SINH",
		mars_reports_sent]
	t += "\nPhím: E dùng thiết bị | 1-4 chọn | Q tiết kiệm | giữ T tua nhanh\n[Space] tiếp tục"
	return t


# ---------- Phím tắt ----------

func _register_eco_input() -> void:
	if not InputMap.has_action("eco"):
		InputMap.add_action("eco")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_Q
	if not InputMap.action_has_event("eco", ev):
		InputMap.action_add_event("eco", ev)


func _unhandled_input(event: InputEvent) -> void:
	if _panel_open:
		# Các trang thông tin mở từ mục 2/3 của máy tính phải đóng được bằng Esc.
		# Kiểm tra cả ui_cancel lẫn phím vật lý để không phụ thuộc InputMap tùy chỉnh.
		var cancel_pressed := event.is_action_pressed("ui_cancel")
		if event is InputEventKey and event.pressed and not event.echo:
			if event.physical_keycode == KEY_ESCAPE or event.keycode == KEY_ESCAPE:
				cancel_pressed = true
		var can_cancel_panel := _panel_kind in ["info", "brief"] or (_panel_kind == "choice" and _choice_cancelable)
		if cancel_pressed and can_cancel_panel:
			get_viewport().set_input_as_handled()
			_close_panel()
			return

		var accept := event.is_action_pressed("ui_accept")
		match _panel_kind:
			"choice":
				if event is InputEventKey and event.pressed and not event.echo:
					var idx := int(event.physical_keycode) - int(KEY_1)
					if idx >= 0 and idx < _choice_options.size():
						get_viewport().set_input_as_handled()
						var cb: Callable = _choice_options[idx]["cb"]
						_close_panel()
						cb.call()
						return
			"minigame":
				if accept:
					get_viewport().set_input_as_handled()
					_mg_press()
			"mg_result":
				if accept:
					get_viewport().set_input_as_handled()
					_close_panel()
					_mg_done.call(_mg_success)
			"summary":
				if accept:
					get_viewport().set_input_as_handled()
					_close_panel()
					_offer_upgrades()
			"final":
				if accept:
					get_viewport().set_input_as_handled()
					get_tree().paused = false
					# Chơi lại là New Game, không tự nạp lại bản autosave vừa thất bại.
					var absolute_save_path := ProjectSettings.globalize_path(SAVE_PATH)
					if FileAccess.file_exists(SAVE_PATH):
						DirAccess.remove_absolute(absolute_save_path)
					get_tree().reload_current_scene()
			_:
				if accept:
					get_viewport().set_input_as_handled()
					_close_panel()
		return
	if event.is_action_pressed("eco"):
		eco = not eco
		_toast("Chế độ tiết kiệm: BẬT (ít điện, ít oxy)" if eco else "Chế độ tiết kiệm: TẮT", Color(0.7, 0.9, 1.0))
		_update_ui()


# ---------- Giao diện (dựng bằng code) ----------

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 40
	_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer)

	_clock = _label("", 22, Vector2.ZERO, Vector2.ZERO, HORIZONTAL_ALIGNMENT_RIGHT)
	_power_bar = _bar(Color(1.0, 0.85, 0.2), Vector2.ZERO, "POWER")
	_o2_bar = _bar(Color(0.3, 0.75, 1.0), Vector2.ZERO, "OXYGEN")
	_mav_bar = _bar(Color(0.75, 0.45, 1.0), Vector2.ZERO, "MAV")
	_data_bar = _bar(Color(0.25, 0.85, 0.65), Vector2.ZERO, "NASA DATA")

	# HUD thông tin có nền và vùng cuộn để không tràn khỏi màn hình khi nhiều trạng thái.
	_info_panel = Panel.new()
	var info_style := StyleBoxFlat.new()
	info_style.bg_color = Color(0.04, 0.07, 0.12, 0.82)
	info_style.border_color = Color(0.55, 0.68, 0.78, 0.65)
	info_style.set_border_width_all(1)
	info_style.set_corner_radius_all(8)
	_info_panel.add_theme_stylebox_override("panel", info_style)
	_layer.add_child(_info_panel)
	_info_scroll = ScrollContainer.new()
	_info_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_info_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_info_panel.add_child(_info_scroll)
	_info_label = Label.new()
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_info_label.add_theme_font_size_override("font_size", 13)
	_info_label.add_theme_color_override("font_color", Color(0.92, 0.95, 1.0))
	_info_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_info_label.add_theme_constant_override("outline_size", 3)
	_info_scroll.add_child(_info_label)

	_toast_label = _label("", 22, Vector2.ZERO, Vector2.ZERO, HORIZONTAL_ALIGNMENT_CENTER)
	_toast_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast_label.modulate.a = 0.0

	_panel = Panel.new()
	_panel.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.08, 0.18, 0.97)
	sb.border_color = Color(0.9, 1.0, 0.2)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.visible = false
	_layer.add_child(_panel)

	_panel_scroll = ScrollContainer.new()
	_panel_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_panel.add_child(_panel_scroll)
	_panel_label = Label.new()
	_panel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_panel_label.add_theme_color_override("font_color", Color(0.96, 0.97, 1.0))
	_panel_label.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.8))
	_panel_label.add_theme_constant_override("outline_size", 2)
	# ScrollContainer tự giới hạn chiều cao và cho phép cuộn nội dung dài.
	_panel_scroll.add_child(_panel_label)

	_mg_root = Control.new()
	_mg_root.visible = false
	_panel.add_child(_mg_root)
	var mg_bg := ColorRect.new()
	mg_bg.color = Color(0.1, 0.12, 0.2)
	mg_bg.name = "TrackBackground"
	_mg_root.add_child(mg_bg)
	_mg_zone_rect = ColorRect.new()
	_mg_zone_rect.color = Color(0.2, 0.9, 0.4, 0.85)
	_mg_root.add_child(_mg_zone_rect)
	_mg_marker = ColorRect.new()
	_mg_marker.color = Color.WHITE
	_mg_marker.size = Vector2(6.0, 52.0)
	_mg_marker.position = Vector2(0.0, -6.0)
	_mg_root.add_child(_mg_marker)

	get_viewport().size_changed.connect(_on_viewport_size_changed)
	_layout_ui()


func _on_viewport_size_changed() -> void:
	_layout_ui()


func _layout_ui() -> void:
	if _layer == null:
		return
	var vp := get_viewport().get_visible_rect().size
	var safe_w := maxf(vp.x, 320.0)
	var safe_h := maxf(vp.y, 240.0)
	var ui_scale := clampf(minf(safe_w / 1280.0, safe_h / 720.0), 0.72, 1.0)
	var hud_w := minf(260.0, safe_w - 28.0)
	var hud_x := 14.0 if safe_w < 600.0 else safe_w - hud_w - 14.0
	var hud_top := 94.0 if safe_w < 600.0 else 8.0
	var bar_h := 23.0 * ui_scale
	var gap := 5.0 * ui_scale

	_clock.position = Vector2(hud_x, hud_top)
	_clock.size = Vector2(hud_w, 28.0 * ui_scale)
	_clock.add_theme_font_size_override("font_size", int(22.0 * ui_scale))
	var y := hud_top + 32.0 * ui_scale
	for bar in [_power_bar, _o2_bar, _mav_bar, _data_bar]:
		bar.position = Vector2(hud_x, y)
		bar.size = Vector2(hud_w, bar_h)
		var bar_label := bar.get_child(0) as Label
		bar_label.position = Vector2.ZERO
		bar_label.size = bar.size
		bar_label.add_theme_font_size_override("font_size", int(14.0 * ui_scale))
		y += bar_h + gap

	var info_available := safe_h - y - 16.0
	# Trên cửa sổ rất thấp, ẩn thẻ thông tin phụ thay vì ép nó tràn khỏi mép dưới.
	_info_panel.visible = info_available >= 42.0
	if _info_panel.visible:
		var info_h := minf(176.0 * ui_scale, info_available)
		_info_panel.position = Vector2(hud_x, y + 2.0)
		_info_panel.size = Vector2(hud_w, info_h)
		_info_scroll.position = Vector2(7.0, 6.0)
		_info_scroll.size = Vector2(maxf(1.0, hud_w - 14.0), maxf(1.0, info_h - 12.0))
		_info_label.custom_minimum_size = Vector2(maxf(100.0, hud_w - 30.0), 0.0)
		_info_label.add_theme_font_size_override("font_size", int(13.0 * ui_scale))

	# Đồng bộ và co giãn HUD HP/FOOD có sẵn trong Game.tscn.
	var player_bar_w := minf(220.0, safe_w * 0.42)
	var player_bar_h := 28.0 * ui_scale
	if _player_hp_bar != null:
		_player_hp_bar.position = Vector2(16.0, 16.0 * ui_scale)
		_player_hp_bar.size = Vector2(player_bar_w, player_bar_h)
	if _player_hp_label != null:
		_player_hp_label.position = Vector2(16.0, 16.0 * ui_scale)
		_player_hp_label.size = Vector2(player_bar_w, player_bar_h)
		_player_hp_label.add_theme_font_size_override("font_size", int(14.0 * ui_scale))
	if _player_food_bar != null:
		_player_food_bar.position = Vector2(16.0, 52.0 * ui_scale)
		_player_food_bar.size = Vector2(player_bar_w, player_bar_h)
	if _player_food_label != null:
		_player_food_label.position = Vector2(16.0, 52.0 * ui_scale)
		_player_food_label.size = Vector2(player_bar_w, player_bar_h)
		_player_food_label.add_theme_font_size_override("font_size", int(14.0 * ui_scale))

	var toast_w := minf(760.0, safe_w - 28.0)
	_toast_label.position = Vector2((safe_w - toast_w) * 0.5, 88.0 * ui_scale)
	_toast_label.size = Vector2(toast_w, 96.0 * ui_scale)
	_toast_label.add_theme_font_size_override("font_size", int(22.0 * ui_scale))

	if _panel != null:
		var panel_w := minf(700.0, safe_w - 24.0)
		var panel_h := minf(440.0, safe_h - 24.0)
		_panel.size = Vector2(maxf(1.0, panel_w), maxf(1.0, panel_h))
		_panel.position = (Vector2(safe_w, safe_h) - _panel.size) * 0.5
		var mg_visible := _mg_active or _panel_kind == "minigame"
		var bottom_reserved := 76.0 if mg_visible else 16.0
		_panel_scroll.position = Vector2(16.0, 14.0)
		_panel_scroll.size = Vector2(maxf(1.0, panel_w - 32.0), maxf(1.0, panel_h - bottom_reserved - 22.0))
		_panel_label.custom_minimum_size = Vector2(maxf(100.0, _panel_scroll.size.x - 16.0), 0.0)
		_panel_label.add_theme_font_size_override("font_size", int(clampf(19.0 * ui_scale, 14.0, 19.0)))
		_mg_track_width = maxf(140.0, minf(MG_W, panel_w - 52.0))
		_mg_root.position = Vector2((panel_w - _mg_track_width) * 0.5, panel_h - 55.0)
		_mg_root.size = Vector2(_mg_track_width, 40.0)
		var track_bg := _mg_root.get_node_or_null("TrackBackground") as ColorRect
		if track_bg != null:
			track_bg.size = Vector2(_mg_track_width, 40.0)
		if _mg_zone_rect != null:
			_mg_zone_rect.position.x = (_mg_zone - _mg_half) * _mg_track_width
			_mg_zone_rect.size = Vector2(_mg_half * 2.0 * _mg_track_width, 40.0)
		if _mg_marker != null:
			_mg_marker.position.x = _mg_pos * _mg_track_width - 3.0


func _label(text: String, font_size: int, pos: Vector2, sz: Vector2, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.size = sz
	l.horizontal_alignment = align
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	_layer.add_child(l)
	return l


func _bar(col: Color, pos: Vector2, text: String) -> ProgressBar:
	var b := ProgressBar.new()
	b.position = pos
	b.size = Vector2(260.0, 24.0)
	b.max_value = 100.0
	b.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.08, 0.12, 0.85)
	bg.set_corner_radius_all(6)
	var fill := StyleBoxFlat.new()
	fill.bg_color = col
	fill.set_corner_radius_all(5)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fill)
	var l := Label.new()
	l.text = text
	l.size = b.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 5)
	b.add_child(l)
	_layer.add_child(b)
	return b


func _update_ui() -> void:
	if _clock == null:
		return
	var h := int(hour)
	var m := int((hour - float(h)) * 60.0)
	_clock.text = "SOL %d/%d   %02d:%02d" % [sol, total_sols, h, m]

	_power_bar.value = clampf(power, 0.0, 100.0)
	_o2_bar.value = clampf(oxygen, 0.0, 100.0)
	_mav_bar.value = clampf(mav_fuel, 0.0, 100.0)
	(_power_bar.get_child(0) as Label).text = "POWER %d%%" % int(power)
	var surface_now := _is_on_mars_surface()
	(_o2_bar.get_child(0) as Label).text = ("EVA OXYGEN %d%%  (-%.2f/s)" % [int(oxygen), mars_o2_drain_per_sec]) if surface_now else ("OXYGEN %d%%" % int(oxygen))
	(_mav_bar.get_child(0) as Label).text = "MAV %d%%" % int(mav_fuel)
	_power_bar.modulate = Color(1.0, 0.55, 0.55) if power < 20.0 else Color.WHITE
	if surface_now and oxygen <= mars_o2_critical_level:
		_o2_bar.modulate = Color(1.0, 0.35, 0.3)
	elif surface_now and oxygen <= mars_o2_warning_level:
		_o2_bar.modulate = Color(1.0, 0.72, 0.25)
	else:
		_o2_bar.modulate = Color.WHITE

	var data_progress := 0.0
	var data_text := "NASA DATA: CHƯA CÓ"
	if mars_research_report_ready:
		data_progress = 50.0
		data_text = "NASA DATA: CHỜ GỬI"
	elif not mars_last_report.is_empty() and str(mars_last_report.get("status", "")) == "NASA ĐÃ NHẬN":
		data_progress = 100.0
		data_text = "NASA DATA: ĐÃ NHẬN"
	_data_bar.value = data_progress
	(_data_bar.get_child(0) as Label).text = data_text

	# Đồng bộ hai thanh HP/FOOD có sẵn trong Game.tscn với tín hiệu của Player.
	_sync_player_hud()

	var s := _sol_def()
	var lines := PackedStringArray()
	lines.append("[Q] Chế độ: %s" % ("TIẾT KIỆM" if eco else "BÌNH THƯỜNG"))
	lines.append("Đèn nhà kính: %s | %s" % ["BẬT" if lamps_on else "TẮT", _tray_summary()])
	lines.append("Mục tiêu: pin %d%%+, oxy %d%%+, thu hoạch %s" % [
		int(float(s["goal_power"])), int(float(s["goal_o2"])), "xong" if ate else "chưa"])
	lines.append("Khoa học: %d | Nhiệm vụ: %d" % [science, total_score])
	lines.append("Báo cáo: %s" % _mars_report_status_text())
	lines.append("Hồ sơ tạo: %d | NASA nhận: %d" % [mars_reports_created, mars_reports_sent])
	lines.append("Solar Array: %s" % ("ĐÃ VỆ SINH" if mars_solar_cleaned_this_sol else "CẦN VỆ SINH" if dust else "SẠCH"))
	if _is_on_mars_surface():
		lines.append("EVA: Oxygen -%.2f%%/giây | F6: về căn cứ" % mars_o2_drain_per_sec)
		if oxygen <= mars_o2_warning_level:
			lines.append("CẢNH BÁO: Oxygen suit thấp!")
	if dust:
		lines.append("CẢNH BÁO: pin bị phủ bụi!")
	_info_label.text = "\n".join(lines)


func _toast(text: String, col: Color) -> void:
	if _toast_label == null:
		return
	_toast_label.text = text
	_toast_label.add_theme_color_override("font_color", col)
	if _toast_tween != null:
		_toast_tween.kill()
	_toast_label.modulate.a = 1.0
	_toast_tween = create_tween()
	_toast_tween.tween_interval(2.5)
	_toast_tween.tween_property(_toast_label, "modulate:a", 0.0, 0.6)


# ---------- Bảng (panel) dùng chung ----------

func _show_choices(title: String, body: String, options: Array, cancelable := false) -> void:
	_choice_options = options
	_choice_cancelable = cancelable
	var t := title + "\n\n"
	if body != "":
		t += body + "\n\n"
	for i in options.size():
		t += "[%d]  %s\n\n" % [i + 1, str(options[i]["label"])]
	if cancelable:
		t += "[Esc]  Đóng"
	_show_panel(t, "choice")


func _show_panel(text: String, kind: String) -> void:
	_panel_kind = kind
	_panel_label.text = text
	_panel.visible = true
	_panel_open = true
	_layout_ui()
	_panel_scroll.scroll_vertical = 0
	get_tree().paused = true


func _close_panel() -> void:
	_panel.visible = false
	_panel_open = false
	_mg_active = false
	_mg_root.visible = false
	get_tree().paused = false
