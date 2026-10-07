# Builds the PhunTaxi pay phone as a 3D model, to stand in for the four
# phuninteriors_01_16..19 sprites through B42's media/spriteModels.txt.
#
#   blender -b --factory-startup --python Art/phone/make_phone.py
#
# Writes, into the mod (model PhunTaxi.PayPhone in scripts/PhunTaxi_Models.txt):
#   media/textures/PhunTaxi/PayPhone.png   the texture, painted from the sprite's colours
#   media/models_X/PhunTaxi/PayPhone.glb   the mesh, as vanilla ships its IsoObject models
# and next to this file:
#   phone.blend      the scene, for hand editing
#   preview_*.png    isometric renders, to hold up against the sprites
#
# Units are vanilla's, measured off models_X/IsoObject/blender/ramp20.blend and
# stairs4.blend: a tile is 1 x 1 centred on the origin, the floor is z = 0 and
# one storey is 2.449. Built facing -Y (the open front, where the traveller
# stands) with the post on the back half of the tile, which is where the
# sprite has it. Each facing is the same model with its own `rotate` in
# spriteModels.txt.
#
# The axes are the Sprite Model Editor's (media/lua/client/DebugUIs/
# SpriteModelEditor.lua draws the north wall at z = -0.5 and the west wall at
# x = -0.5) and suggested model x east, z south, y up. Blender -Y exports as
# glTF +Z, so that read the open front as south at rotate 0 0 0. In game every
# facing came out backwards (seen 2026-10-07), S and N first, then E and W,
# so all four are 180 from that reading: E -90, S 180, W 90, N 0.

import bpy, bmesh, math, os
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
MEDIA = os.path.join(HERE, "..", "..", "Contents", "mods", "PhunTaxi", "common", "media")
NAME = "PhunTaxi_PayPhone"
TEX = 512

# ---------------------------------------------------------------------------
# Texture. Regions are (x, y, w, h) in pixels, top down. Colours were read
# off the sprite.
# ---------------------------------------------------------------------------

R = {
    "metal":   (0, 0, 256, 256),
    "inside":  (256, 0, 128, 128),
    "post":    (384, 0, 128, 128),
    "body":    (256, 128, 128, 128),
    "handset": (384, 128, 128, 128),
    "taxi":    (0, 256, 64, 256),
    "panel":   (64, 256, 64, 256),
    "face":    (256, 256, 128, 256),
    "shelf":   (384, 256, 128, 128),
    "cord":    (384, 384, 128, 128),
}

def rgb(h):
    return np.array([int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)])

METAL = rgb("8a8d94")
METAL_HI = rgb("b4b7bd")
INSIDE = rgb("5e6168")
POST = rgb("45464a")
BODY = rgb("3a3d42")
HANDSET = rgb("26282b")
YELLOW = rgb("d9d09a")
YELLOW_DIM = rgb("bfb27a")
INK = rgb("36352a")
GREEN = rgb("93c48c")
SHELF = rgb("a39a62")

rng = np.random.default_rng(42)
img = np.ones((TEX, TEX, 4))

def fill(region, colour, noise=0.025):
    x, y, w, h = region
    n = rng.normal(0, noise, (h, w, 1)) if noise else 0
    img[y:y + h, x:x + w, :3] = np.clip(colour + n, 0, 1)

def rect(region, rx, ry, rw, rh, colour):
    """A rectangle inside a region, in fractions of it."""
    x, y, w, h = region
    x0, y0 = x + int(rx * w), y + int(ry * h)
    img[y0:y0 + max(1, int(rh * h)), x0:x0 + max(1, int(rw * w)), :3] = colour

def edge(region, colour, px=4):
    x, y, w, h = region
    img[y:y + px, x:x + w, :3] = colour
    img[y + h - px:y + h, x:x + w, :3] = colour
    img[y:y + h, x:x + px, :3] = colour
    img[y:y + h, x + w - px:x + w, :3] = colour

# 5 x 7 block letters; all four are mirror symmetric, so the panel reads the
# same from either side of the hood.
FONT = {
    "T": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
    "A": [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    "X": ["#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"],
    "I": ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"],
}

def letters(region, word, colour):
    x, y, w, h = region
    cell = min(w * 0.75 / 5, h * 0.9 / (len(word) * 8))
    cell = int(cell)
    lx = x + (w - cell * 5) // 2
    ly = y + (h - cell * (len(word) * 8 - 1)) // 2
    for i, ch in enumerate(word):
        for r, row in enumerate(FONT[ch]):
            for c, bit in enumerate(row):
                if bit == "#":
                    py, px = ly + (i * 8 + r) * cell, lx + c * cell
                    img[py:py + cell, px:px + cell, :3] = colour

fill(R["metal"], METAL)
edge(R["metal"], METAL_HI, 6)
fill(R["inside"], INSIDE)
fill(R["post"], POST, 0.04)
fill(R["body"], BODY)
fill(R["handset"], HANDSET, 0.01)
fill(R["cord"], HANDSET, 0.0)
fill(R["shelf"], SHELF)
edge(R["shelf"], YELLOW_DIM, 6)

# The lit side panel, with a soft glow down the middle as on the sprite.
fill(R["taxi"], YELLOW, 0.015)
x, y, w, h = R["taxi"]
glow = 1 - 0.18 * np.abs(np.linspace(-1, 1, w))[None, :, None]
img[y:y + h, x:x + w, :3] *= glow
letters(R["taxi"], "TAXI", INK)
edge(R["taxi"], METAL, 3)
fill(R["panel"], YELLOW, 0.015)
x, y, w, h = R["panel"]
img[y:y + h, x:x + w, :3] *= glow
edge(R["panel"], METAL, 3)

# The phone's face: display, coin slot, keypad, card slot.
fill(R["face"], BODY)
edge(R["face"], rgb("2a2c30"), 4)
rect(R["face"], 0.18, 0.06, 0.64, 0.12, rgb("1d2a1d"))
rect(R["face"], 0.22, 0.08, 0.56, 0.08, GREEN)
rect(R["face"], 0.70, 0.24, 0.08, 0.10, rgb("1a1b1d"))
for row in range(4):
    for col in range(3):
        rect(R["face"], 0.20 + col * 0.15, 0.40 + row * 0.08, 0.10, 0.055, rgb("9a9ca1"))
rect(R["face"], 0.25, 0.80, 0.50, 0.03, rgb("1a1b1d"))
rect(R["face"], 0.15, 0.88, 0.70, 0.08, rgb("4c4f55"))

# ---------------------------------------------------------------------------
# Mesh. Every part is a box; each face's UVs are its planar projection
# within the box, laid into the part's region, so nothing needs unwrapping.
# ---------------------------------------------------------------------------

def uv_region(name):
    x, y, w, h = R[name]
    # Image pixels are top down, UVs bottom up.
    return x / TEX, 1 - (y + h) / TEX, w / TEX, h / TEX

parts = []

def box(name, lo, hi, regions, bevel=0.0):
    """regions: one region name for every face, or a dict by face direction
    (+x, -x, +y, -y, +z, -z) with "*" as the rest."""
    if isinstance(regions, str):
        regions = {"*": regions}
    parts.append((name, Vector(lo), Vector(hi), regions, bevel))

def build():
    bm = bmesh.new()
    uv = bm.loops.layers.uv.new("UVMap")
    for name, lo, hi, regions, bevel in parts:
        size = hi - lo
        res = bmesh.ops.create_cube(bm, size=1.0)
        verts = res["verts"]
        for v in verts:
            v.co = Vector((lo.x + (v.co.x + 0.5) * size.x,
                           lo.y + (v.co.y + 0.5) * size.y,
                           lo.z + (v.co.z + 0.5) * size.z))
        faces = {f for v in verts for f in v.link_faces}
        if bevel > 0:
            # Round the hood's top front edge, as on the sprite.
            front_top = [e for f in faces for e in f.edges
                         if all(abs(v.co.z - hi.z) < 1e-6 and abs(v.co.y - lo.y) < 1e-6
                                for v in e.verts)]
            res = bmesh.ops.bevel(bm, geom=list(set(front_top)), offset=bevel,
                                  segments=4, affect="EDGES", profile=0.5)
            faces = {f for v in bm.verts if (v.co - (lo + hi) / 2).length < size.length
                     for f in v.link_faces if f.is_valid}
            faces = {f for f in faces if all(lo.x - 1e-4 <= v.co.x <= hi.x + 1e-4 and
                                             lo.y - 1e-4 <= v.co.y <= hi.y + 1e-4 and
                                             lo.z - 1e-4 <= v.co.z <= hi.z + 1e-4
                                             for v in f.verts)}
        bm.normal_update()
        for f in faces:
            n = f.normal
            axis = max(range(3), key=lambda i: abs(n[i]))
            key = ("+" if n[axis] > 0 else "-") + "xyz"[axis]
            rx, ry, rw, rh = uv_region(regions.get(key, regions.get("*")))
            # Horizontal axis of the face, then up (z) or y for flat faces.
            ua, va = {0: (1, 2), 1: (0, 2), 2: (0, 1)}[axis]
            for loop in f.loops:
                co = loop.vert.co
                u = (co[ua] - lo[ua]) / max(size[ua], 1e-6)
                v = (co[va] - lo[va]) / max(size[va], 1e-6)
                if key in ("-y", "+x"):
                    u = 1 - u  # read left to right from outside
                loop[uv].uv = (rx + min(max(u, 0), 1) * rw, ry + min(max(v, 0), 1) * rh)
    mesh = bpy.data.meshes.new(NAME)
    bm.to_mesh(mesh)
    bm.free()
    return mesh

# Dimensions, in tiles.
W = 0.50            # hood width
BACK = 0.42         # back of the hood, toward +Y
DEPTH = 0.30        # hood depth
T = 0.04            # sheet thickness
POST_W = 0.12
HOOD_LO = 0.80      # bottom of the hood
HOOD_HI = 1.80      # top of the hood
FRONT = BACK - DEPTH

# Post, under the back half of the hood.
pc = BACK - DEPTH * 0.55
box("post", (-POST_W / 2, pc - POST_W / 2, 0.0),
    (POST_W / 2, pc + POST_W / 2, HOOD_LO), "post")
# Back panel.
box("back", (-W / 2, BACK - T, HOOD_LO), (W / 2, BACK, HOOD_HI),
    {"*": "metal", "-y": "inside"})
# Side panels: lit TAXI outside, plain lit panel inside.
box("left", (-W / 2, FRONT, HOOD_LO), (-W / 2 + T, BACK - T, HOOD_HI),
    {"*": "metal", "-x": "taxi", "+x": "panel"})
box("right", (W / 2 - T, FRONT, HOOD_LO), (W / 2, BACK - T, HOOD_HI),
    {"*": "metal", "+x": "taxi", "-x": "panel"})
# Roof, rounded at the front.
box("roof", (-W / 2, FRONT - 0.02, HOOD_HI - 0.06), (W / 2, BACK, HOOD_HI + 0.03),
    {"*": "metal", "-z": "inside"}, bevel=0.05)
# Floor of the hood, standing proud of the front, and the shelf on it.
box("base", (-W / 2, FRONT - 0.02, HOOD_LO - 0.05), (W / 2, BACK, HOOD_LO + 0.03),
    {"*": "metal", "+z": "inside"})
box("shelf", (-W / 2 + T, FRONT, HOOD_LO + 0.03), (W / 2 - T, FRONT + 0.10, HOOD_LO + 0.08),
    "shelf")
# The phone itself, on the back panel.
PH_W, PH_D = 0.22, 0.08
box("phone", (-PH_W / 2 + 0.03, BACK - T - PH_D, HOOD_LO + 0.30),
    (PH_W / 2 + 0.03, BACK - T, HOOD_LO + 0.82), {"*": "body", "-y": "face"})
# Handset in its cradle, left of the phone, and its cord.
hx = -PH_W / 2 + 0.03 - 0.035
box("handset", (hx - 0.025, BACK - T - 0.07, HOOD_LO + 0.45),
    (hx + 0.025, BACK - T - 0.01, HOOD_LO + 0.75), "handset")
box("cord", (hx - 0.008, BACK - T - 0.05, HOOD_LO + 0.12),
    (hx + 0.008, BACK - T - 0.034, HOOD_LO + 0.45), "cord")

# ---------------------------------------------------------------------------
# Scene, export, previews.
# ---------------------------------------------------------------------------

bpy.ops.wm.read_factory_settings(use_empty=True)
mesh = build()
obj = bpy.data.objects.new(NAME, mesh)
bpy.context.scene.collection.objects.link(obj)

os.makedirs(os.path.join(MEDIA, "textures", "PhunTaxi"), exist_ok=True)
os.makedirs(os.path.join(MEDIA, "models_X", "PhunTaxi"), exist_ok=True)
png = os.path.abspath(os.path.join(MEDIA, "textures", "PhunTaxi", "PayPhone.png"))
image = bpy.data.images.new(NAME, TEX, TEX, alpha=True)
image.pixels = img[::-1].ravel().tolist()
image.filepath_raw = png
image.file_format = "PNG"
image.save()
image.filepath = png

mat = bpy.data.materials.new(NAME)
mat.use_nodes = True
nodes = mat.node_tree.nodes
bsdf = nodes.get("Principled BSDF")
texnode = nodes.new("ShaderNodeTexImage")
texnode.image = image
texnode.interpolation = "Closest"
mat.node_tree.links.new(texnode.outputs["Color"], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.8
mesh.materials.append(mat)

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "phone.blend"))
bpy.ops.export_scene.gltf(filepath=os.path.abspath(os.path.join(MEDIA, "models_X", "PhunTaxi", "PayPhone.glb")),
                          export_format="GLB", use_selection=False,
                          export_image_format="NONE")

# Isometric previews, one per facing, framed like a 128 x 256 tile.
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in \
    [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] \
    else "BLENDER_EEVEE"
scene.render.resolution_x, scene.render.resolution_y = 256, 512
scene.render.film_transparent = True
world = bpy.data.worlds.new("w")
world.use_nodes = True
world.node_tree.nodes["Background"].inputs[1].default_value = 1.0
scene.world = world
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
sun.data.energy = 3.0
sun.rotation_euler = (math.radians(50), 0, math.radians(30))
scene.collection.objects.link(sun)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.type = "ORTHO"
cam.data.ortho_scale = 2.6
scene.collection.objects.link(cam)
scene.camera = cam

# PZ's camera looks from screen bottom, where +x and +y both point. The model
# faces -Y, so a facing is the turn that points -Y at that direction.
TURN = {"E": 90, "S": 0, "W": -90, "N": 180}
for facing, deg in TURN.items():
    obj.rotation_euler = (0, 0, math.radians(deg))
    # Blender +Y is PZ's -y (north), so the PZ camera sits at Blender (+x, -y).
    d = Vector((1, -1, 0)).normalized() * 6
    d.z = 6 * math.tan(math.radians(30))
    target = Vector((0, 0, 1.0))
    cam.location = target + d
    cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = os.path.join(HERE, "preview_%s.png" % facing)
    bpy.ops.render.render(write_still=True)
obj.rotation_euler = (0, 0, 0)
print("DONE", NAME, len(mesh.vertices), "verts", len(mesh.polygons), "faces")
