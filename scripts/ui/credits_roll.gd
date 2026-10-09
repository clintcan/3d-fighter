class_name CreditsRoll
extends VBoxContainer
## The scrolling credits, shared by the Credits screen (main menu) and the Arcade ending.
## Add it, call start(), and it scrolls up from the bottom of the screen until the last
## line ("THANKS FOR PLAYING!") rests mid-screen, then emits `finished`.

signal finished

const GOLD := Color(1.0, 0.82, 0.3)
const SPEED := 90.0 # pixels per second
## [heading, body]: a heading without a body is a big gold title; ["", ""] is a gap.
const CREDITS := [
	["3D FIGHTER", ""],
	["", ""],
	["Created by", "Clint Christopher Canada"],
	["Made with", "Godot Engine (MIT License)"],
	["", ""],
	["Characters & animations", "Quaternius: Universal Base Characters,\nUniversal Animation Library 1 & 2 (CC0)"],
	["Stage lighting & textures", "Poly Haven: \"Basement Boxing Ring\" HDRI by Sergej\nMajboroda; Terlenka, Fabric Leather 02,\nConcrete Floor Worn 001 (CC0)"],
	["Dojo textures", "Poly Haven: Tatami Mat, Hinoki Planks, Japanese Cedar Planks\n(Charlotte Baglioni, Rico Cilliers), Dark Wood (Dario Barresi,\nDimitrios Savva, Rico Cilliers), White Plaster 02 (Rob Tuytel) (CC0)"],
	["Rooftop skyline", "Poly Haven: \"Shanghai Bund\" HDRI by Greg Zaal (CC0)"],
	["Temple", "Poly Haven: \"Belfast Sunset\" sky (Greg Zaal, Dimitrios Savva,\nJarod Guest), Monastery Stone Floor (Amal Kumar), Japanese Stone\nWall, Gravel Floor 03, Grey Roof Tiles (CC0)"],
	["Beach", "Poly Haven: \"Kloofendal 48d Partly Cloudy\" sky (Greg Zaal,\nJarod Guest), Coast Sand 01, Thatch Roof Angled (Rob Tuytel,\nDimitrios Savva), Palm Tree Bark (Dimitrios Savva, Rico Cilliers),\nBamboo Wall (Amal Kumar) (CC0)"],
	["Night Market", "Poly Haven: \"Qwantani Dusk 2\" sky (Greg Zaal, Jarod Guest),\nAsphalt 02 (Rob Tuytel), Brick Pavement and Rusty Corrugated Iron\n(Charlotte Baglioni), Painted Plaster Wall and Wood Planks (Amal Kumar),\nPainted Metal Shutter (Dario Barresi, Rico Cilliers, Charlotte Baglioni) (CC0)"],
	["Express", "Poly Haven: \"Kloppenheim 06\" sky (Greg Zaal, Jarod Guest),\nAerial Grass Rock (Rob Tuytel) (CC0)"],
	["Kowloon Courtyard", "Poly Haven: Dirty Tiles (Matterfield, Jenelle van Heerden),\nConcrete Wall 006 (Dario Barresi, Charlotte Baglioni) (CC0)"],
	["Outfit fabrics", "Poly Haven: Cotton Jersey and Bi Stretch (colormass, Rico Cilliers),\nDenim Fabric 06 (Greg Zaal, Rico Cilliers) (CC0)"],
	["Music", "\"Heavy Battle 2\", \"Space Battle\" and \"Jazzy Battle Theme\" by MintoDog, \"Determination\"\nby HydroGene, \"Midnight Drive\" by congusbongus,\n\"Boss_Koto\" by G_P, \"Funky House\" by Of Far Different Nature,\n\"Determined Pursuit\" by Emma_MA (OpenGameArt, CC0),\n\"Dragon Dance\" by BiteMe Games (itch.io, CC0)"],
	["Fighter voices", "\"Male Grunt/Yelling sounds\" by HaelDB, \"Female Hurt\nGrunts & Groans\" by AuraVoice (OpenGameArt, CC0)"],
	["Sound effects & announcer", "Kenney: Impact Sounds, Interface Sounds,\nVoiceover Pack: Fighter (CC0)"],
	["Ambient sound", "\"AMB Rain Loop 1\" by kresiek-the-furry, \"High traffic road sounds\"\nby ignasd, \"Background voices\" by pauliuw, \"Crowd Shouting/Speaking\nAmbience\" by starninjas, \"Applause in a large hall or church\" by expl0it3r,\n\"Beach Ocean Waves\" by qubodup, \"Park ambiences\" by thimras, \"Fire Crackling\"\nby antumdeluge, \"Solo Seagull Sound Effects\" by rango-mango (OpenGameArt, CC0)"],
	["Crowd reactions", "Freesound: \"Group Ooh\" and \"Group Wow\" by CHallSmith, \"Crowd Ooohs and Ahhhs\"\nby noah0189, \"Crowd Gasping In Surprise\" by Shane Vincent, \"Small Crowd Gasps\" and\n\"Sporting Event with Steady Cheers\" by craigsmith, \"Millerntor Stadium Crowd Reaction\"\nby Philipp Feit (Sound Of Sankt Pauli), \"Football Crowd - Reaction To Goal\" by D.jones,\n\"Crowd aah\" and \"Crowd shock\" by an anonymous contributor (CC0)"],
	["Train sounds", "Freesound: \"freight train pass fast short heavy rail track clacks\" by kyles,\n\"Train Track Joints Slow (Loop)\" by KayleRustone, \"Train Pass By\" by GreekIrish (CC0)"],
	["Courtyard sounds", "Freesound: \"Jet landing flyover\" by tbaucom, \"Pigeon flock fly away\" by TRP,\n\"pigeon_take_off\" by sinewave1kHz, \"RollerShutter_IT\" by uniuniversal (CC0)"],
	["Logo lettering", "Based on the \"Permanent Marker\" font by Font Diner"],
	["Made for this project", "Ring, arena, dojo, rooftop, temple, beach, night market, the express train,\nthe Kowloon courtyard and crowds, fighter outfits,\nfight and special-move animations, portraits, key art and logo, swing,\nenergy and super sounds"],
	["License", "Code: MIT  ·  Original assets: CC BY 4.0\nThird-party assets: CC0"],
	["", ""],
	["THANKS FOR PLAYING!", ""],
]

var rolling := false


func _init() -> void:
	add_theme_constant_override("separation", 34)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for entry in CREDITS:
		if entry[0] == "" and entry[1] == "":
			var gap := Control.new()
			gap.custom_minimum_size.y = 60
			add_child(gap)
			continue
		var big: bool = entry[1] == ""
		add_child(_label(entry[0], 72 if big else 30, GOLD if big else Color(0.65, 0.7, 0.8)))
		if not big:
			add_child(_label(entry[1], 34, Color.WHITE))


## Starts scrolling from just below the bottom of the viewport.
func start() -> void:
	var view := get_viewport_rect().size
	custom_minimum_size.x = view.x
	position = Vector2(0, view.y)
	rolling = true


func _process(delta: float) -> void:
	if not rolling:
		return
	position.y -= SPEED * delta
	if position.y + size.y < get_viewport_rect().size.y * 0.5:
		rolling = false # the last line rests mid-screen
		finished.emit()


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_constant_override("outline_size", 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label
