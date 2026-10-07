# Builds the Project Viewpoint model pack for the garage's taxi, from vanilla's
# own CarTaxi: the body mesh, its four wheels, and its shell skin.
#
#   blender -b --factory-startup --python Art/taxi/make_taxi.py
#
# Viewpoint (workshop 3809306528) draws nothing for phuninteriors_02_*: they
# are in none of its vanilla tables and have no tile geometry. A model pack
# binds a sprite to an OBJ, so the whole car is bound to ONE tile of the ten
# it stands on and the other nine are left alone. See PhunInteriors'
# scripts/viewpointpack.pl for what is known about packs.
#
# Writes, into the mod (media/viewpoint/):
#   taxi.obj, taxi.mtl, taxi.png    the car, and its atlas: the shell skin on
#                                   the left half, the wheel on the right
#   phuntaxi.properties             the manifest
# and next to this file:
#   taxi.blend       the scene, for looking at
#   preview_iso.png  an isometric render, to hold up against the sprite
#
# Sources, all read from the game install (set PZ_MEDIA to move it):
#   models_X/vehicles/Vehicles_CarTaxi.FBX   ASCII FBX, which Blender cannot
#                                            import, so it is parsed here
#   models/Vehicles_Wheel.txt                PZ's own text mesh
#   textures/Vehicles/vehicle_cartaxishell.png, vehicle_wheel.png
#
# Sizes are the vehicle script's (scripts/generated/vehicles/vehicle_taxi.txt):
# the mesh at 0.008 (its model script) times 1.82 (the vehicle's scale), the
# wheels at the script's offsets times 1.82. That lands the wheels in the
# body's arches, which is the check that the scale is right. Height is not
# taken from the physics: the wheel centre is put just under the arch top, and
# the ground under the wheels.
#
# Model space is Viewpoint's: origin at the CENTRE of the bound tile, x east,
# y SOUTH, z up, a tile is 1. Blender works in x east, y NORTH, z up, which is
# the FBX's own frame (front +y, right side +x), and the OBJ writer flips y.

import bpy, bmesh, math, os, re
import numpy as np
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
MOD = os.path.join(HERE, "..", "..", "Contents", "mods", "PhunTaxi", "common", "media")
OUT = os.path.abspath(os.path.join(MOD, "viewpoint"))
GAME = os.environ.get("PZ_MEDIA", r"D:\Steam\steamapps\common\ProjectZomboid\media")
NAME = "PhunTaxi_Taxi"

SCALE = 1.82                    # vehicle CarTaxi: model scale
MESH_SCALE = 0.008 * SCALE      # model Vehicles_CarTaxi: scale, times the above
WHEEL_X = 0.3626 * SCALE        # wheel FrontLeft offset x
WHEEL_FRONT = 0.8516 * SCALE    # wheel FrontLeft offset z (forward)
WHEEL_REAR = -0.6099 * SCALE    # wheel RearLeft offset z
ARCH_GAP = 0.02                 # between the tyre and the arch top, in tiles

# The car stands north to south on 2 x 5 squares, front to the north:
#   phuninteriors_02_10 _11      north row (the hood)
#                    _12 _13
#                    _14 _15
#                    _16 _17
#                    _18 _19      south row (plate and tail lights)
# The bind goes on _14, the west square of the middle row, so the car's
# centre is half a tile east of it. Read off the lotpack of cell 87,49.
ANCHOR = "phuninteriors_02_14"
ANCHOR_X, ANCHOR_Y = 0.5, 0.0


# ---------------------------------------------------------------------------
# Sources.
# ---------------------------------------------------------------------------

def fbx_array(text, key, start=0):
    """The numbers of the first `key: *N { a: ... }` at or after start."""
    m = re.compile(key + r": \*\d+ \{\s*a: ([^}]*)\}", re.S).search(text, start)
    return [float(x) for x in m.group(1).split(",")], m.end()

def read_body():
    with open(os.path.join(GAME, "models_X", "vehicles", "Vehicles_CarTaxi.FBX"), encoding="latin-1") as f:
        text = f.read()
    verts, _ = fbx_array(text, "Vertices")
    index, _ = fbx_array(text, "PolygonVertexIndex")
    # The first UV layer is the shell's; the second is the overlays'.
    uv_at = text.index("LayerElementUV: 0")
    uvs, after = fbx_array(text, "UV", uv_at)
    uv_index, _ = fbx_array(text, "UVIndex", after)
    pos = [Vector(verts[i:i + 3]) * MESH_SCALE for i in range(0, len(verts), 3)]
    faces, face = [], []
    for corner, i in enumerate(int(x) for x in index):
        last = i < 0
        vi = ~i if last else i
        t = int(uv_index[corner])
        # Bottom up already; the shell takes the atlas's left half.
        face.append((vi, (uvs[2 * t] * 0.5, uvs[2 * t + 1])))
        if last:
            faces.append(face)
            face = []
    return pos, faces

def read_wheel():
    with open(os.path.join(GAME, "models", "Vehicles_Wheel.txt")) as f:
        lines = [l.strip() for l in f]
    count = int(lines[lines.index("# Vertex Count:") + 1])
    at = lines.index("# Vertex Buffer:") + 1
    pos, uv = [], []
    for i in range(count):
        p = [float(x) for x in lines[at + i * 3].split(",")]
        t = [float(x) for x in lines[at + i * 3 + 2].split(",")]
        # The axle is x. Top down UVs (the hub is at v 0.6 from the top of
        # the image), into the atlas's right half.
        pos.append(Vector(p) * SCALE)
        uv.append((0.5 + t[0] * 0.5, 1 - t[1]))
    at = lines.index("# Face Data:") + 1
    faces = []
    for l in lines[at:]:
        if l and not l.startswith("#"):
            faces.append([(int(x), uv[int(x)]) for x in l.split(",")])
    return pos, faces


bpy.ops.wm.read_factory_settings(use_empty=True)
body_pos, body_faces = read_body()
wheel_pos, wheel_faces = read_wheel()
wheel_r = max(math.hypot(p.y, p.z) for p in wheel_pos)

# Where the arches are: the lowest outer body point above each axle that is
# still above the sill, which is the arch's top.
def arch_top(axle):
    zs = [p.z for p in body_pos
          if abs(p.x) > WHEEL_X and abs(p.y - axle) < wheel_r * 0.4 and p.z > -0.35]
    return min(zs)

arch = min(arch_top(WHEEL_FRONT), arch_top(WHEEL_REAR))
wheel_z = arch - wheel_r - ARCH_GAP
ground = wheel_z - wheel_r

# The car's footprint, centred on the origin, with the ground at z 0.
lo = Vector([min(p[i] for p in body_pos) for i in range(3)])
hi = Vector([max(p[i] for p in body_pos) for i in range(3)])
centre = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, ground))


# ---------------------------------------------------------------------------
# Mesh.
# ---------------------------------------------------------------------------

bm = bmesh.new()
uv_layer = bm.loops.layers.uv.new("UVMap")

def add(pos, faces, offset):
    verts = [bm.verts.new(p + offset - centre) for p in pos]
    for face in faces:
        try:
            f = bm.faces.new([verts[i] for i, _ in face])
        except ValueError:
            continue  # a duplicate face
        for loop, (_, uv) in zip(f.loops, face):
            loop[uv_layer].uv = uv

add(body_pos, body_faces, Vector((0, 0, 0)))
for x in (WHEEL_X, -WHEEL_X):
    for y in (WHEEL_FRONT, WHEEL_REAR):
        add(wheel_pos, wheel_faces, Vector((x, y, wheel_z)))
bmesh.ops.triangulate(bm, faces=bm.faces[:])
mesh = bpy.data.meshes.new(NAME)
bm.to_mesh(mesh)
bm.free()
# Smooth round the curves, hard at the panel edges: smoothing everything
# darkened the doors in blotches.
mesh.shade_smooth()
mesh.set_sharp_from_angle(angle=math.radians(35))
obj = bpy.data.objects.new(NAME, mesh)
bpy.context.scene.collection.objects.link(obj)


# ---------------------------------------------------------------------------
# Atlas: shell 512 x 512 on the left, the 128 wheel scaled up on the right.
# ---------------------------------------------------------------------------

def pixels(name):
    im = bpy.data.images.load(os.path.join(GAME, "textures", "Vehicles", name))
    w, h = im.size
    return np.array(im.pixels[:]).reshape(h, w, 4)   # bottom up

shell = pixels("vehicle_cartaxishell.png")
wheel = pixels("vehicle_wheel.png")
wheel = np.repeat(np.repeat(wheel, shell.shape[0] // wheel.shape[0], 0), shell.shape[1] // wheel.shape[1], 1)
atlas = np.concatenate([shell, wheel], axis=1)
atlas[..., 3] = 1.0

os.makedirs(OUT, exist_ok=True)
png = os.path.join(OUT, "taxi.png")
image = bpy.data.images.new(NAME, atlas.shape[1], atlas.shape[0], alpha=False)
image.pixels = atlas.ravel().tolist()
image.filepath_raw = png
image.file_format = "PNG"
image.save()
image.filepath = png

mat = bpy.data.materials.new(NAME)
mat.use_nodes = True
nodes = mat.node_tree.nodes
tex = nodes.new("ShaderNodeTexImage")
tex.image = image
mat.node_tree.links.new(tex.outputs["Color"], nodes["Principled BSDF"].inputs["Base Color"])
mesh.materials.append(mat)


# ---------------------------------------------------------------------------
# OBJ, triangles in both windings (vanilla draws the car with culling off,
# and nothing says which way Viewpoint culls), y flipped to Viewpoint's south.
# ---------------------------------------------------------------------------

normals = [tuple(n.vector) for n in mesh.corner_normals]
uvs = mesh.uv_layers.active.data
with open(os.path.join(OUT, "taxi.obj"), "w", newline="\n") as f:
    f.write("# generated by Art/taxi/make_taxi.py -- do not edit\n")
    f.write("mtllib taxi.mtl\nusemtl m\n")
    for v in mesh.vertices:
        f.write("v %.5f %.5f %.5f\n" % (v.co.x, -v.co.y, v.co.z))
    for d in uvs:
        f.write("vt %.5f %.5f\n" % tuple(d.uv))
    for n in normals:
        f.write("vn %.4f %.4f %.4f\n" % (n[0], -n[1], n[2]))
    for n in normals:
        f.write("vn %.4f %.4f %.4f\n" % (-n[0], n[1], -n[2]))
    back = len(normals)
    for p in mesh.polygons:
        c = list(p.loop_indices)
        v = [mesh.loops[i].vertex_index + 1 for i in c]
        # Flipping y mirrors the winding, so Blender's order is the back face.
        f.write("f %s\n" % " ".join("%d/%d/%d" % (v[k], c[k] + 1, c[k] + 1 + back) for k in (0, 1, 2)))
        f.write("f %s\n" % " ".join("%d/%d/%d" % (v[k], c[k] + 1, c[k] + 1) for k in (2, 1, 0)))

with open(os.path.join(OUT, "taxi.mtl"), "w", newline="\n") as f:
    f.write("newmtl m\nKd 1 1 1\nd 1\nmap_Kd taxi.png\n")

with open(os.path.join(OUT, "phuntaxi.properties"), "w", newline="\n") as f:
    f.write("# generated by Art/taxi/make_taxi.py -- do not edit\n")
    f.write("id=phuntaxi\nname=PhunTaxi taxi\nversion=1\n")
    f.write("model.pt-taxi=taxi.obj\n")
    # model,degrees,x,y,z,scale
    f.write("bind.%s=pt-taxi,0,%g,%g,0,1\n" % (ANCHOR, ANCHOR_X, ANCHOR_Y))

bpy.ops.wm.save_as_mainfile(filepath=os.path.join(HERE, "taxi.blend"))


# ---------------------------------------------------------------------------
# Preview: PZ's camera, looking from the south east, so the front (north) is
# up and to the right, as on the sprite.
# ---------------------------------------------------------------------------

scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in \
    [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] \
    else "BLENDER_EEVEE"
scene.render.resolution_x, scene.render.resolution_y = 640, 512
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
cam.data.ortho_scale = 6.5
scene.collection.objects.link(cam)
scene.camera = cam
d = Vector((1, -1, 0)).normalized() * 12
d.z = 12 * math.tan(math.radians(30))
target = Vector((0, 0, 0.6))
cam.location = target + d
cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
scene.render.filepath = os.path.join(HERE, "preview_iso.png")
bpy.ops.render.render(write_still=True)

print("DONE %s: %d verts, %d tris, %.2f x %.2f x %.2f tiles, wheel r %.3f, ground %.3f under the mesh origin"
      % (NAME, len(mesh.vertices), len(mesh.polygons),
         hi.x - lo.x, hi.y - lo.y, hi.z - ground, wheel_r, ground))
