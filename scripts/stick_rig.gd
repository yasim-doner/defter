extends RefCounted

# ----------------------------------------------------------------------------
# Procedural physical stick-figure rig.
# Origin is at the feet (y = 0), body extends upward (negative y), matching the
# CharacterBody2D draw convention. update() advances the simulation; draw()
# renders it onto a CanvasItem. No frame data — everything is solved from the
# character's velocity / floor state, the same way Fancy Pants drives its rig.
# ----------------------------------------------------------------------------

# --- Skeleton proportions (px) ---
const THIGH := 13.0
const SHIN := 13.0
const UPPER_ARM := 10.0
const FOREARM := 10.0
const SPINE := 15.0          # hip -> chest
const NECK := 6.0            # chest -> head base
const HEAD_R := 8.0
const SHOULDER_W := 8.0
const HIP_W := 5.0

const HIP_HEIGHT := 24.0     # resting hip height above the feet
const STRIDE := 30.0         # full step length
const STEP_H := 10.0         # how high a foot lifts mid-swing

# --- Tuning ---
const SPEED_REF := 230.0     # speed at which we're "fully sprinting"
const LEAN_FROM_ACCEL := 0.0006
const LEAN_MAX := 0.55       # ~31 degrees of forward sprint lean
const HIP_LEAD := 5.0        # how far the hips lead into the lean
const SPINE_STIFF := 240.0   # spring constant for chest follow
const SPINE_DAMP := 22.0
const HEAD_STIFF := 200.0
const HEAD_DAMP := 20.0
const HAND_STIFF := 180.0
const HAND_DAMP := 18.0

# --- Live state ---
var phase := 0.0             # gait cycle, wraps [0,1)
var lean := 0.0             # smoothed body tilt (radians, +x forward)
var squash := 0.0           # >0 squashed (landing), <0 stretched (rising)
var _prev_vx := 0.0
var _prev_vy := 0.0
var _prev_on_floor := true
var _time := 0.0

# Spring-driven joints (in local space, origin at feet)
var hip := Vector2(0, -HIP_HEIGHT)
var chest := Vector2(0, -HIP_HEIGHT - SPINE)
var chest_v := Vector2.ZERO
var head := Vector2(0, -HIP_HEIGHT - SPINE - NECK - HEAD_R)
var head_v := Vector2.ZERO
var hand_l := Vector2(-8, -HIP_HEIGHT - SPINE + 6)
var hand_r := Vector2(8, -HIP_HEIGHT - SPINE + 6)
var hand_l_v := Vector2.ZERO
var hand_r_v := Vector2.ZERO

# Resolved joints (filled each update, read by draw)
var _shoulder_l := Vector2.ZERO
var _shoulder_r := Vector2.ZERO
var _elbow_l := Vector2.ZERO
var _elbow_r := Vector2.ZERO
var _hip_l := Vector2.ZERO
var _hip_r := Vector2.ZERO
var _knee_l := Vector2.ZERO
var _knee_r := Vector2.ZERO
var _foot_l := Vector2.ZERO
var _foot_r := Vector2.ZERO


func _spring(pos: Vector2, vel: Vector2, target: Vector2, k: float, d: float, dt: float) -> Array:
	var force := (target - pos) * k - vel * d
	vel += force * dt
	pos += vel * dt
	return [pos, vel]


# Two-bone IK. Returns the mid joint (knee/elbow). bend = +1/-1 chooses the side
# the joint pops out toward.
func _ik(root: Vector2, target: Vector2, l1: float, l2: float, bend: float) -> Vector2:
	var to := target - root
	var dist := to.length()
	dist = clampf(dist, absf(l1 - l2) + 0.01, l1 + l2 - 0.01)
	if to.length() < 0.001:
		to = Vector2.DOWN
	var base := to.angle()
	var cos_a := clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0)
	var a := acos(cos_a)
	var ja := base + bend * a
	return root + Vector2(cos(ja), sin(ja)) * l1


# vel: world velocity, on_floor: grounded, face: +1 right / -1 left,
# aim: optional gun aim angle (NAN when no gun), gun: holding a weapon.
func update(dt: float, vel: Vector2, on_floor: bool, face: float, gun: bool, aim: float) -> void:
	if dt <= 0.0:
		return
	_time += dt
	var speed := absf(vel.x)
	var accel := (vel.x - _prev_vx) / dt
	_prev_vx = vel.x
	var run_t := clampf(speed / SPEED_REF, 0.0, 1.0)   # 0 idle .. 1 full sprint
	var dir_sign := signf(vel.x)

	# --- Lean: ramps up with speed (sprint pitch) + an acceleration kick ---
	var target_lean := dir_sign * run_t * LEAN_MAX + accel * LEAN_FROM_ACCEL
	target_lean = clampf(target_lean, -LEAN_MAX * 1.25, LEAN_MAX * 1.25)
	if not on_floor:
		target_lean = clampf(dir_sign * run_t * LEAN_MAX * 0.5, -LEAN_MAX, LEAN_MAX)
	lean = lerp(lean, target_lean, clampf(dt * 10.0, 0.0, 1.0))

	# --- Squash & stretch ---
	# Landing impact uses last airborne frame's fall speed (move_and_slide has
	# already zeroed vel.y by the time we run).
	var just_landed := on_floor and not _prev_on_floor
	if just_landed:
		squash = clampf(absf(_prev_vy) / 500.0, 0.15, 1.0)
	elif not on_floor:
		# stretch while moving fast vertically
		squash = lerp(squash, clampf(-absf(vel.y) / 600.0, -0.5, 0.0), clampf(dt * 8.0, 0.0, 1.0))
	else:
		squash = lerp(squash, 0.0, clampf(dt * 10.0, 0.0, 1.0))
	_prev_on_floor = on_floor
	_prev_vy = vel.y

	# --- Gait phase advances with distance travelled (this is what plants feet) ---
	var moving := on_floor and speed > 12.0
	if moving:
		phase = fposmod(phase + (speed * dt) / STRIDE, 1.0)
	else:
		# ease the legs back to a neutral stance
		phase = lerp(phase, 0.0, clampf(dt * 8.0, 0.0, 1.0))

	# --- Hip position: vertical bob during run + squash offset ---
	var bob := 0.0
	if moving:
		bob = -absf(sin(phase * TAU)) * 2.4   # body lifts each step
	var hip_y := -HIP_HEIGHT + bob + squash * 6.0
	# Hips lead into the lean so the centre of mass sits ahead of the feet.
	var hip_x := sin(lean) * HIP_LEAD
	hip = Vector2(hip_x, hip_y)

	# --- Spine direction from lean ---
	var spine_dir := Vector2(sin(lean), -cos(lean))

	# --- Chest & head springs (secondary motion / follow-through) ---
	var chest_target := hip + spine_dir * (SPINE * (1.0 - squash * 0.25))
	var r := _spring(chest, chest_v, chest_target, SPINE_STIFF, SPINE_DAMP, dt)
	chest = r[0]; chest_v = r[1]
	var head_target := chest + spine_dir * (NECK + HEAD_R)
	r = _spring(head, head_v, head_target, HEAD_STIFF, HEAD_DAMP, dt)
	head = r[0]; head_v = r[1]

	# --- Shoulders / hips spread (perpendicular to spine) ---
	var perp := Vector2(spine_dir.y, -spine_dir.x)
	_shoulder_l = chest + perp * (-SHOULDER_W) * face
	_shoulder_r = chest + perp * (SHOULDER_W) * face
	_hip_l = hip + Vector2(-HIP_W * face, 0)
	_hip_r = hip + Vector2(HIP_W * face, 0)

	# --- Feet targets, then IK the knees ---
	if on_floor:
		_foot_l = _foot_target(phase, face, moving, _hip_l)
		_foot_r = _foot_target(fposmod(phase + 0.5, 1.0), face, moving, _hip_r)
	else:
		# Airborne: tuck the legs while rising, reach down while falling.
		var fall_t := clampf(vel.y / 320.0, -1.0, 1.0)   # -1 rising .. +1 falling
		var lead_lift := lerpf(16.0, -3.0, (fall_t + 1.0) * 0.5)   # how high feet tuck
		var trail_lift := lerpf(9.0, -1.0, (fall_t + 1.0) * 0.5)
		_foot_l = Vector2(_hip_l.x + 5.0 * face, -lead_lift)   # front leg tucks high
		_foot_r = Vector2(_hip_r.x - 4.0 * face, -trail_lift)  # back leg trails
	_knee_l = _ik(_hip_l, _foot_l, THIGH, SHIN, face)   # knees bend forward
	_knee_r = _ik(_hip_r, _foot_r, THIGH, SHIN, face)

	# --- Hand targets ---
	var hl_t: Vector2
	var hr_t: Vector2
	if gun and not is_nan(aim):
		# Both hands to the grip, pointing along aim
		var grip := chest + Vector2(cos(aim), sin(aim)) * 16.0
		hr_t = grip
		hl_t = chest + Vector2(cos(aim), sin(aim)) * 9.0 + perp * 3.0
	elif not on_floor:
		var rise := clampf(-vel.y / 320.0, -1.0, 1.0)   # +1 rising, -1 falling
		if rise > 0.0:
			# jumping: arms swing up toward the head
			hl_t = _shoulder_l + Vector2(-2.0 * face, -8.0 - 12.0 * rise)
			hr_t = _shoulder_r + Vector2(2.0 * face, -8.0 - 12.0 * rise)
		else:
			# falling: arms fling out & up for balance
			hl_t = _shoulder_l + Vector2(-16.0 * face, -12.0)
			hr_t = _shoulder_r + Vector2(14.0 * face, -11.0)
	elif moving:
		# Sprinter's pump: bent elbows, hands kept close to the chest so the
		# IK forces a ~90 degree elbow, swinging forward/back out of phase.
		var pump := sin(phase * TAU)
		var fwd_dir := Vector2(cos(lean - PI * 0.5), sin(lean - PI * 0.5))  # along the torso "forward"
		hl_t = chest + perp * (-5.0 * face) + fwd_dir * (pump * 11.0) + Vector2(0, 7.0)
		hr_t = chest + perp * (5.0 * face) + fwd_dir * (-pump * 11.0) + Vector2(0, 7.0)
	else:
		# Idle: hands hang close to the body
		hl_t = _shoulder_l + Vector2(-1.5 * face, 17.0)
		hr_t = _shoulder_r + Vector2(1.5 * face, 17.0)

	r = _spring(hand_l, hand_l_v, hl_t, HAND_STIFF, HAND_DAMP, dt)
	hand_l = r[0]; hand_l_v = r[1]
	r = _spring(hand_r, hand_r_v, hr_t, HAND_STIFF, HAND_DAMP, dt)
	hand_r = r[0]; hand_r_v = r[1]

	_elbow_l = _ik(_shoulder_l, hand_l, UPPER_ARM, FOREARM, -face)
	_elbow_r = _ik(_shoulder_r, hand_r, UPPER_ARM, FOREARM, -face)


# Foot placement: stance half plants the foot and drags it backward at body
# speed (so it appears locked to the ground); swing half arcs it forward.
func _foot_target(p: float, face: float, moving: bool, hip_joint: Vector2) -> Vector2:
	if not moving:
		# neutral stance: foot planted directly under the hip
		return Vector2(hip_joint.x, 0.0)
	var fwd: float
	var lift := 0.0
	if p < 0.5:
		var t := p / 0.5
		fwd = lerp(STRIDE * 0.5, -STRIDE * 0.5, t)
	else:
		var t := (p - 0.5) / 0.5
		var ts := t * t * (3.0 - 2.0 * t)   # smoothstep
		fwd = lerp(-STRIDE * 0.5, STRIDE * 0.5, ts)
		lift = sin(t * PI) * STEP_H
	return Vector2(hip_joint.x + fwd * face, -lift)


# --- Rendering ---------------------------------------------------------------

func _bowed(ci: CanvasItem, a: Vector2, b: Vector2, color: Color, w: float, sd: float) -> void:
	# a short polyline with a tiny living wobble, so it reads as ink on paper
	var mid := (a + b) * 0.5
	var n := (b - a).orthogonal().normalized()
	mid += n * sin(sd) * 0.6
	var pts := PackedVector2Array([a, mid, b])
	ci.draw_polyline(pts, color, w, true)


func draw(ci: CanvasItem, color: Color, w: float) -> void:
	var s := _time * 6.0
	# Legs
	_bowed(ci, _hip_l, _knee_l, color, w, s)
	_bowed(ci, _knee_l, _foot_l, color, w, s + 1.1)
	_bowed(ci, _hip_r, _knee_r, color, w, s + 2.0)
	_bowed(ci, _knee_r, _foot_r, color, w, s + 3.1)
	# Feet (little ink dashes)
	ci.draw_line(_foot_l, _foot_l + Vector2(4, 0), color, w)
	ci.draw_line(_foot_r, _foot_r + Vector2(4, 0), color, w)
	# Spine
	_bowed(ci, hip, chest, color, w, s + 0.5)
	# Arms
	_bowed(ci, _shoulder_l, _elbow_l, color, w, s + 4.0)
	_bowed(ci, _elbow_l, hand_l, color, w, s + 5.1)
	_bowed(ci, _shoulder_r, _elbow_r, color, w, s + 6.0)
	_bowed(ci, _elbow_r, hand_r, color, w, s + 7.1)
	# Neck
	ci.draw_line(chest, head, color, w)
	# Head
	_draw_head(ci, head, HEAD_R, color, w, s)


func _draw_head(ci: CanvasItem, c: Vector2, radius: float, color: Color, w: float, sd: float) -> void:
	var pts := PackedVector2Array()
	var n := 18
	for i in range(n + 1):
		var ang := i * TAU / n
		var wob := Vector2(sin(ang * 3.0 + sd), cos(ang * 2.0 + sd)) * 0.5
		pts.append(c + Vector2(cos(ang), sin(ang)) * radius + wob)
	ci.draw_polyline(pts, color, w, true)
