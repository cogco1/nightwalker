extends RefCounted
## A few quiet doctors on the day clinic's current floor. Attached to World so normal floor/projection
## reconstruction owns their lifetime. They never join the enemies group and cannot obstruct the hero.

const DAY_DOCTOR = preload("res://scripts/levels/hospital/day_doctor.gd")
const CONTAINER_NAME := "DayStaff"
const STAFF := {
	1: [
		{"id": "ward_rounds", "feet": Vector2i(240, 170), "facing": 1, "appearance": 0},
		{"id": "ward_chart", "feet": Vector2i(338, 174), "facing": -1, "appearance": 1},
		{"id": "storage_staff", "feet": Vector2i(569, 174), "facing": -1, "appearance": 2},
	],
	2: [
		{"id": "reception_staff", "feet": Vector2i(164, 118), "facing": -1, "appearance": 1},
		{"id": "treatment_staff", "feet": Vector2i(345, 116), "facing": -1, "appearance": 0},
	],
}


static func refresh(hospital: Node2D, story: Node) -> Node2D:
	if not is_instance_valid(hospital.world):
		return null
	var old: Node = hospital.world.get_node_or_null(CONTAINER_NAME)
	if old != null:
		hospital.world.remove_child(old)
		old.queue_free()
	if not story.chapter_active or story.is_night() or hospital.view_mode != 0:
		return null
	var roster: Array = STAFF.get(hospital.floor_id, [])
	if roster.is_empty():
		return null
	var staff := Node2D.new()
	staff.name = CONTAINER_NAME
	hospital.world.add_child(staff)
	for record: Dictionary in roster:
		var doctor := DAY_DOCTOR.new()
		doctor.configure(record, hospital.floor_id)
		staff.add_child(doctor)
	return staff
