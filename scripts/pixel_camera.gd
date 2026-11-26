class_name PixelCamera
extends Camera2D
## Smooth follow camera for the pixel-art world.
## The world must render on whole game pixels, but the player moves by fractions of one, so a plain
## snapped camera scrolls in uneven 0/1/2 px steps (1 game px = PIXEL_SCALE window px), which reads as
## shake. This camera snaps itself to whole game pixels (the low-res render stays pixel-perfect) and
## reports the leftover fraction as `subpixel`; the game shell shifts the upscaled image by it, so the
## world scrolls smoothly in window-pixel steps. The game viewport renders MARGIN_PX extra game pixels on
## every side so the shift never exposes an edge.
## Follows its parent (top_level, so the parent's own rounding doesn't move it). The room bounds are the
## usual limit_* properties; the built-in clamp is off because it would count the margin as visible.

## Emitted every frame after the camera moved: `subpixel` = (exact centre - snapped centre), game px.
signal scrolled(subpixel: Vector2)

const MARGIN_PX := 1

var subpixel := Vector2.ZERO


func _ready() -> void:
	top_level = true
	limit_enabled = false


func _process(_delta: float) -> void:
	var target := get_parent() as Node2D
	if target == null:
		return
	var visible := get_viewport_rect().size - Vector2.ONE * 2.0 * MARGIN_PX
	var c := target.global_position
	c.x = _clamp_axis(c.x, limit_left, limit_right, visible.x)
	c.y = _clamp_axis(c.y, limit_top, limit_bottom, visible.y)
	var snapped := c.round()
	subpixel = c - snapped
	global_position = snapped
	force_update_scroll()
	scrolled.emit(subpixel)


## Keeps a `view`-wide window inside lo..hi (centred when the room is smaller than the view).
static func _clamp_axis(v: float, lo: float, hi: float, view: float) -> float:
	if hi - lo <= view:
		return (lo + hi) / 2.0
	return clampf(v, lo + view / 2.0, hi - view / 2.0)
