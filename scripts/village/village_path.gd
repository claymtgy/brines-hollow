class_name VillagePath
extends RefCounted
## A* for villagers over the voxel world, on a 2-voxel (0.36 m) grid.
## A node is a standing spot (x, y, z) in voxels: y is the cell the feet occupy.
## Moves: 8 directions; step up <= STEP_UP voxels, step down <= STEP_DOWN; no corner cutting.
## Pure logic: the world is reached through `standable(x, y, z) -> bool`, so tests can use
## synthetic grids and the game can use native AABB queries.

const GRID := 2
const STEP_UP := 3
const STEP_DOWN := 6
const MAX_EXPANSIONS := 6000

var standable: Callable


func _init(p_standable: Callable) -> void:
	standable = p_standable


## Nearest standable y at (x, z) within +-range of y, preferring y itself, then up, then down.
func find_stand(x: int, y: int, z: int, up := STEP_UP, down := STEP_DOWN) -> int:
	var key := Vector4i(x, y, z, up * 64 + down)
	if _memo.has(key):
		return _memo[key]
	var out := -999999
	if _stand(x, y, z):
		out = y
	else:
		for k in range(1, maxi(up, down) + 1):
			if k <= up and _stand(x, y + k, z):
				out = y + k
				break
			if k <= down and _stand(x, y - k, z):
				out = y - k
				break
	_memo[key] = out
	return out


var _memo := {}
var _stand_memo := {}


func _stand(x: int, y: int, z: int) -> bool:
	var k := Vector3i(x, y, z)
	if not _stand_memo.has(k):
		_stand_memo[k] = standable.call(x, y, z)
	return _stand_memo[k]


## Call when the world changed (edits) so cached standability is re-queried.
func clear_cache() -> void:
	_memo.clear()
	_stand_memo.clear()


func _snap(v: int) -> int:
	return int(floor(float(v) / GRID)) * GRID


## Returns waypoints (Vector3i voxel cells, feet level) from `from` to `to`, or [] if no path.
## The final waypoint is the goal snapped to the grid.
func find_path(from: Vector3i, to: Vector3i) -> Array:
	var s := Vector3i(_snap(from.x), from.y, _snap(from.z))
	s.y = find_stand(s.x, s.y, s.z, 8, 12)
	var g := Vector3i(_snap(to.x), to.y, _snap(to.z))
	g.y = find_stand(g.x, g.y, g.z, 8, 12)
	if s.y < -99999 or g.y < -99999:
		return []
	if s == g:
		return [g]
	var open := _Heap.new()
	var came := {s: s}
	var cost := {s: 0.0}
	open.push(s, _h(s, g))
	var closed := {}
	var expansions := 0
	var best := s
	var best_h := _h(s, g)
	while not open.is_empty():
		var cur: Vector3i = open.pop()
		if closed.has(cur):
			continue
		if cur.x == g.x and cur.z == g.z and absi(cur.y - g.y) <= STEP_UP:
			return _rebuild(came, cur)
		closed[cur] = true
		expansions += 1
		if expansions > MAX_EXPANSIONS:
			break
		var hc := _h(cur, g)
		if hc < best_h:
			best_h = hc
			best = cur
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				if dx == 0 and dz == 0:
					continue
				var nx: int = cur.x + dx * GRID
				var nz: int = cur.z + dz * GRID
				var ny := find_stand(nx, cur.y, nz)
				if ny < -99999:
					continue
				if dx != 0 and dz != 0:
					# no corner cutting: both orthogonal neighbours must be walkable too
					if find_stand(cur.x + dx * GRID, cur.y, cur.z) < -99999 or find_stand(cur.x, cur.y, cur.z + dz * GRID) < -99999:
						continue
				var n := Vector3i(nx, ny, nz)
				if closed.has(n):
					continue
				var step := (1.4142 if dx != 0 and dz != 0 else 1.0) + absf(ny - cur.y) * 0.15
				var nc: float = cost[cur] + step
				if nc < cost.get(n, INF):
					cost[n] = nc
					came[n] = cur
					open.push(n, nc + _h(n, g))
	# Unreachable within budget: walk as close as we got (better than standing still).
	return _rebuild(came, best) if best != s else []


func _h(a: Vector3i, b: Vector3i) -> float:
	var dx := absf(a.x - b.x) / GRID
	var dz := absf(a.z - b.z) / GRID
	return maxf(dx, dz) + 0.4142 * minf(dx, dz)


func _rebuild(came: Dictionary, end: Vector3i) -> Array:
	var out := [end]
	var c: Vector3i = end
	while came[c] != c:
		c = came[c]
		out.push_front(c)
	return out


## Minimal binary min-heap of (priority, Vector3i).
class _Heap:
	var pri: Array[float] = []
	var val: Array[Vector3i] = []

	func is_empty() -> bool:
		return pri.is_empty()

	func push(v: Vector3i, p: float) -> void:
		pri.append(p)
		val.append(v)
		var i := pri.size() - 1
		while i > 0:
			var parent := (i - 1) >> 1
			if pri[parent] <= pri[i]:
				break
			_swap(i, parent)
			i = parent

	func pop() -> Vector3i:
		var top := val[0]
		var last := pri.size() - 1
		_swap(0, last)
		pri.pop_back()
		val.pop_back()
		var i := 0
		var n := pri.size()
		while true:
			var l := i * 2 + 1
			var r := l + 1
			var m := i
			if l < n and pri[l] < pri[m]: m = l
			if r < n and pri[r] < pri[m]: m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var tp := pri[a]; pri[a] = pri[b]; pri[b] = tp
		var tv := val[a]; val[a] = val[b]; val[b] = tv
