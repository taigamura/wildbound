class_name Glyphs
## Element and UI icons: the SVG paths from core/data.ts GLYPH, rasterised once at runtime
## (white, tinted with modulate), with mipmaps so they stay crisp at any size.

const PATHS := {
	"ember": '<path d="M12 2c1 4 6 6 6 12a6 6 0 0 1-12 0c0-3 2-5 3-6 0 2 1 3 2 3 0-4 1-7 1-9z"/>',
	"tide": '<path d="M12 2C9 7 5 11 5 15a7 7 0 0 0 14 0c0-4-4-8-7-13z"/>',
	"thorn": '<path d="M20 3C10 3 4 9 4 16c0 2 1 5 1 5s2-6 7-9c-3 3-5 6-6 9 9 0 14-7 14-18z"/>',
	"volt": '<path d="M13 1L4 14h7l-2 9 10-13h-7l2-9z"/>',
	"shield": '<path d="M12 2l8 3v6c0 5-3.5 9-8 11-4.5-2-8-6-8-11V5l8-3z"/>',
	"heart": '<path d="M12 21s-8-5-8-11a4.5 4.5 0 0 1 8-3 4.5 4.5 0 0 1 8 3c0 6-8 11-8 11z"/>',
	"star": '<path d="M12 2l3 7h7l-5.5 4.5L18.5 21 12 16.5 5.5 21l2-7.5L2 9h7z"/>',
	"spark": '<path d="M12 1l2.2 7.8L22 11l-7.8 2.2L12 21l-2.2-7.8L2 11l7.8-2.2z"/>',
	"claw": '<path d="M5 18L14 4M9.5 21L18.5 7M14.5 21.5L20.5 12"/>',
	"skull": '<path d="M12 2a9 9 0 0 0-9 9c0 3 1.5 5 3 6v4h12v-4c1.5-1 3-3 3-6a9 9 0 0 0-9-9zm-3.5 9a2 2 0 1 1 0 4 2 2 0 0 1 0-4zm7 0a2 2 0 1 1 0 4 2 2 0 0 1 0-4z"/>',
	"crown": '<path d="M3 7l4.5 4L12 4l4.5 7L21 7l-2 12H5z"/>',
	"moon": '<path d="M15 2a9 9 0 1 0 7 13A8 8 0 0 1 15 2z"/>',
	"chest": '<path d="M3 9a5 5 0 0 1 5-5h8a5 5 0 0 1 5 5v1H3zm0 3h7v2h4v-2h7v8H3z"/>',
	"paw": '<path d="M12 12c3 0 6 3 6 6 0 2-2 3-3.5 3-1 0-1.5-.7-2.5-.7s-1.5.7-2.5.7C8 21 6 20 6 18c0-3 3-6 6-6zM5 8a2 2.5 0 1 1 0 5 2 2.5 0 0 1 0-5zm14 0a2 2.5 0 1 1 0 5 2 2.5 0 0 1 0-5zM9 3a2 2.5 0 1 1 0 5 2 2.5 0 0 1 0-5zm6 0a2 2.5 0 1 1 0 5 2 2.5 0 0 1 0-5z"/>',
	"orb": '<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 2a8 8 0 0 1 7.9 7H15a3 3 0 0 0-6 0H4.1A8 8 0 0 1 12 4z"/>',
	"swap": '<path d="M7 4L3 8l4 4V9h10V7H7zm10 8v3H7v2h10v3l4-4z"/>',
	"up": '<path d="M12 3l8 9h-5v9H9v-9H4z"/>',
	"sound": '<path d="M3 9h4l5-5v16l-5-5H3zm13.5 3a4.5 4.5 0 0 0-2.5-4v8a4.5 4.5 0 0 0 2.5-4zM14 3.2v2.1a7 7 0 0 1 0 13.4v2.1a9 9 0 0 0 0-17.6z"/>',
	"coin": '<path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm1 4v1.1c1.6.3 2.8 1.3 2.9 2.9h-2c-.1-.7-.7-1.1-1.9-1.1-1.1 0-1.7.4-1.7 1s.5.9 2.1 1.3c2.2.5 3.6 1.2 3.6 3.1 0 1.6-1.2 2.6-3 2.9V18h-2v-1.1c-1.8-.3-3.1-1.4-3.1-3.1h2c.1.8.8 1.3 2.1 1.3 1.2 0 1.9-.4 1.9-1.1 0-.6-.5-1-2.2-1.4-2-.4-3.5-1.1-3.5-3 0-1.5 1.1-2.5 2.8-2.8V6z"/>',
	"sword": '<path d="M20 2l-1 5-9 9-2-2 9-9zM7 15l2 2-2 2 1.5 1.5-1.5 1.5L5.5 20.5 4 22l-2-2 1.5-1.5L2 17l1.5-1.5L5 17z"/>',
	"jewel": '<path d="M7 3h10l5 6-10 13L2 9zm1.2 2L5.4 8.4h4.1L11 5zm7.6 0H13l1.5 3.4h4.1zM12 6.2l-1.3 2.2h2.6zM5.6 10.4l5.4 7.1-2.5-7.1zm5 0L12 15l1.4-4.6zm4.9 0L13 17.5l5.4-7.1z"/>',
	"mute": '<path d="M3 9h4l5-5v16l-5-5H3zm13.6-.6L19 10.8l2.4-2.4 1.4 1.4-2.4 2.4 2.4 2.4-1.4 1.4-2.4-2.4-2.4 2.4-1.4-1.4 2.4-2.4-2.4-2.4z"/>',
}

static var _cache := {}

static func tex(key: String) -> Texture2D:
	if _cache.has(key):
		return _cache[key]
	var body: String = PATHS.get(key, PATHS["star"])
	var attrs := 'fill="#fff"'
	if key == "claw":
		attrs = 'fill="none" stroke="#fff" stroke-width="2.6" stroke-linecap="round"'
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><g %s>%s</g></svg>' % [attrs, body]
	var img := Image.new()
	if img.load_svg_from_string(svg, 5.0) != OK:
		img = Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cache[key] = t
	return t
