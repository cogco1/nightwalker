extends Node2D
## The day clinic's harmless staff and sight dispatcher. World reconstruction owns their lifetime; none
## joins the night enemies group. Short room patrols leave the hospital's doors and stair landings clear.

const DAY_DOCTOR = preload("res://scripts/levels/hospital/day_doctor.gd")
const CONTAINER_NAME := "DayStaff"
const STAFF := {
	1: [
		{"id": "ward_rounds", "points": [Vector2(170, 166), Vector2(230, 166), Vector2(230, 178)], "appearance": 0},
		{"id": "ward_chart", "points": [Vector2(314, 172), Vector2(354, 172), Vector2(354, 160)], "appearance": 1},
		{"id": "storage_staff", "points": [Vector2(458, 176), Vector2(566, 176), Vector2(566, 158)], "appearance": 2},
	],
	2: [
		{"id": "reception_staff", "points": [Vector2(181, 88), Vector2(181, 123)], "appearance": 1},
		{"id": "treatment_staff", "points": [Vector2(332, 109), Vector2(385, 109)], "appearance": 0},
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
	var staff: Node2D = load("res://scripts/levels/hospital/hospital_day_staff.gd").new()
	staff.name = CONTAINER_NAME
	hospital.world.add_child(staff)
	for record: Dictionary in roster:
		var doctor := DAY_DOCTOR.new()
		doctor.configure(record, hospital.floor_id, hospital)
		staff.add_child(doctor)
	return staff


func observer_for(hero: Node2D) -> Node2D:
	for doctor in get_children():
		if doctor.sees_player(hero):
			return doctor
	return null


func visible_by(hero: Node2D) -> bool:
	return observer_for(hero) != null
