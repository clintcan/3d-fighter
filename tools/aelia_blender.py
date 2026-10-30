"""Converts the "Aelia" character (Blend Swap 30219 by Abinady10, CC-BY) for the game.

Run with Blender 5.x (scripts in the .blend stay disabled):
  blender -b --disable-autoexec --factory-startup tools/aelia/aelia_source.blend \
      --python tools/aelia_blender.py -- <q_rest.json> <out dir>

q_rest.json: the game skeleton's rest joints (Superhero_Female_FullBody, Godot coordinates),
written by tools/build_aelia.gd -- --dump-rest <file>.

Steps: her own rig is cleared of constraints and posed from its A-pose into the game
skeleton's T-pose, limb by limb (each arm, leg and finger segment turned to the game
bone's direction, the palms twisted to match; the upright torso stays as modelled), and
that pose is baked into the mesh. Her weights are merged
into the game's bone names, the rivets, hair and armour are decimated, the eyes split off,
and the mesh exported (glTF + textures) on an armature whose joints sit at her joints.
tools/build_aelia.gd then gives that skeleton the game skeleton's exact joint orientations.
"""
import json
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
Q_REST = json.loads(open(ARGS[0], encoding="utf-8").read())
OUT_DIR = ARGS[1]

# Decimate ratio per (original) material; the rest are kept as they are.
DECIMATE = {
    "tornillos_material": 0.12,  # ~170 tiny rivets and bolts
    "cabello": 0.3,
    "armadura_material": 0.45,
    "amarillo_material": 0.5,
    "cafe": 0.5,
    "chain_mail_material": 0.6,
    "benda": 0.6,
}
MATERIAL_NAMES = {
    "Piel_material": "MI_Superhero_Aelia_Skin",  # MI_Superhero*: FighterModel's skin shading
    "cabello": "MI_Hair_Aelia",  # MI_Hair*: tinted by CharacterData.hair_color
    "ojo_material": "MI_Eyes_Aelia",  # MI_Eyes*: clearcoat + eye light
    "pestanas_material": "Aelia_Lashes",
    "chain_mail_material": "Aelia_Chainmail",
    "armadura_material": "Aelia_Armour",
    "tornillos_material": "Aelia_Rivets",
    "cafe": "Aelia_Leather",
    "amarillo_material": "Aelia_Gold",
    "benda": "Aelia_Bandage",
}
FINGERS = ["pinky", "ring", "middle", "index"]  # back to front; the thumb is found apart


def q(name: str) -> Vector:
    """A game skeleton joint in Blender coordinates (Godot x, y, z -> Blender x, -z, y)."""
    x, y, z = Q_REST[name][:3]
    return Vector((x, -z, y))


def q_dir(a: str, b: str) -> Vector:
    return (q(b) - q(a)).normalized()


def override(obj):
    return bpy.context.temp_override(active_object=obj, object=obj, selected_objects=[obj],
                                     selected_editable_objects=[obj])


arm = bpy.data.objects["Aelia Rigged"]
body = bpy.data.objects["aelia"]
for o in (arm, body):
    o.hide_set(False)
    o.hide_viewport = False
bpy.context.view_layer.objects.active = arm

# --- 1. Clean rig: no constraints, rest pose, hands under the forearms ---------------
for pb in arm.pose.bones:
    for c in list(pb.constraints):
        pb.constraints.remove(c)
    pb.rotation_mode = "QUATERNION"
    pb.location = (0, 0, 0)
    pb.rotation_quaternion = (1, 0, 0, 0)
    pb.scale = (1, 1, 1)
arm.data.pose_position = "POSE"
bpy.ops.object.mode_set(mode="EDIT")
for side in ("L", "R"):
    hand = arm.data.edit_bones[f"Mano.{side}"]
    hand.use_connect = False
    hand.parent = arm.data.edit_bones[f"Brazo.{side}"]
bpy.ops.object.mode_set(mode="POSE")
bones = arm.data.bones


def head(name: str) -> Vector:
    return arm.matrix_world @ arm.pose.bones[name].head


def tail(name: str) -> Vector:
    return arm.matrix_world @ arm.pose.bones[name].tail


# --- 2. Finger chains: [controller, base, mid, tip] per finger, named by position -----
chains = {}  # (side, finger) -> [base, mid, tip] bone names
for side in ("L", "R"):
    hand_head = bones[f"Mano.{side}"].head_local
    found = []
    for ctrl in bones:
        if not ctrl.name.startswith(f"controlador_menique_{side}"):
            continue
        base = next(b for b in bones if b.name.startswith("menique_1") and b.parent and b.parent.name == f"Mano.{side}"
                    and (b.head_local - ctrl.head_local).length < 1e-4)
        mid = base.children[0]
        tip = mid.children[0]
        found.append((ctrl.name, base.name, mid.name, tip.name))
    found.sort(key=lambda c: (bones[c[1]].head_local - hand_head).length)
    thumb, rest = found[0], sorted(found[1:], key=lambda c: -bones[c[1]].head_local.y)
    for finger, chain in zip(["thumb"] + FINGERS, [thumb] + rest):
        chains[(side, finger)] = list(chain[1:])
        # The controller spans the whole finger and deforms too: fold it into the base bone,
        # which follows it in her rig (copy rotation).
        src = body.vertex_groups.get(chain[0])
        dst = body.vertex_groups.get(chain[1])
        if src and dst:
            for v in body.data.vertices:
                for g in v.groups:
                    if g.group == src.index and g.weight > 0:
                        dst.add([v.index], g.weight, "ADD")
            body.vertex_groups.remove(src)
print("FINGER CHAINS", {f"{s}.{f}": c[0] for (s, f), c in chains.items()})


# --- 3. Pose into the game's T-pose ---------------------------------------------------
def turn(bone: str, a: Vector, b: Vector, target: Vector) -> None:
    """Turns `bone` about its head so the world vector a->b points along `target`."""
    pb = arm.pose.bones[bone]
    rot = (b - a).normalized().rotation_difference(target).to_matrix().to_4x4()
    pivot = arm.matrix_world.inverted() @ head(bone)
    pb.matrix = Matrix.Translation(pivot) @ rot @ Matrix.Translation(-pivot) @ pb.matrix
    bpy.context.view_layer.update()


def aim(bone: str, end: Vector, qa: str, qb: str) -> None:
    turn(bone, head(bone), end, q_dir(qa, qb))


# The spine, neck and head stay as modelled: both bodies stand upright in their rest
# poses, and the two rigs place their spine joints differently inside the torso (matching
# their directions pitched her chest ~25 degrees forward). Only the limbs differ.
for side, s in (("L", "l"), ("R", "r")):
    # Her shoulders stay as modelled too: matching the clavicle direction shrugged them
    # ~29 degrees, lifting the guard's fists in front of her eyes.
    aim(f"Antebrazo.{side}", head(f"Brazo.{side}"), f"upperarm_{s}", f"lowerarm_{s}")
    aim(f"Brazo.{side}", head(f"Mano.{side}"), f"lowerarm_{s}", f"hand_{s}")
    hand = f"Mano.{side}"
    aim(hand, head(chains[(side, "middle")][0]), f"hand_{s}", f"middle_01_{s}")
    # Palm twist: index-to-pinky across the knuckles, about the hand's own axis.
    axis = (head(chains[(side, "middle")][0]) - head(hand)).normalized()
    across = head(chains[(side, "index")][0]) - head(chains[(side, "pinky")][0])
    want = q(f"index_01_{s}") - q(f"pinky_01_{s}")
    across_p = (across - axis * across.dot(axis)).normalized()
    want_p = (want - axis * want.dot(axis)).normalized()
    twist = across_p.rotation_difference(want_p)
    print(f"PALM TWIST {side}: {twist.angle * 57.2958:.1f} deg")
    turn(hand, head(hand), head(hand) + across_p, want_p)
    for finger in ["thumb"] + FINGERS:
        base, mid, tip = chains[(side, finger)]
        aim(base, head(mid), f"{finger}_01_{s}", f"{finger}_02_{s}")
        aim(mid, head(tip), f"{finger}_02_{s}", f"{finger}_03_{s}")
        aim(tip, tail(tip), f"{finger}_03_{s}", f"{finger}_04_leaf_{s}")
    aim(f"Antepierna.{side}", head(f"Pierna.{side}"), f"thigh_{s}", f"calf_{s}")
    aim(f"Pierna.{side}", head(f"Pie.{side}"), f"calf_{s}", f"foot_{s}")
    aim(f"Pie.{side}", head(f"Dedos.{side}"), f"foot_{s}", f"ball_{s}")
    aim(f"Dedos.{side}", tail(f"Dedos.{side}"), f"ball_{s}", f"ball_leaf_{s}")

# Her joints in the T-pose, by game bone name (Blender coordinates).
fit = {"root": Vector((0, 0, 0))}
fit["pelvis"] = (head("Antepierna.L") + head("Antepierna.R")) / 2
for qn, hn in (("spine_01", "Columna"), ("spine_02", "Columna.000"), ("spine_03", "Columna.001"),
               ("neck_01", "Cuello"), ("Head", "Cabeza")):
    fit[qn] = head(hn)
for side, s in (("L", "l"), ("R", "r")):
    for qn, hn in (("clavicle", "Hombro"), ("upperarm", "Antebrazo"), ("lowerarm", "Brazo"), ("hand", "Mano"),
                   ("thigh", "Antepierna"), ("calf", "Pierna"), ("foot", "Pie"), ("ball", "Dedos")):
        fit[f"{qn}_{s}"] = head(f"{hn}.{side}")
    fit[f"ball_leaf_{s}"] = tail(f"Dedos.{side}")
    for finger in ["thumb"] + FINGERS:
        base, mid, tip = chains[(side, finger)]
        fit[f"{finger}_01_{s}"] = head(base)
        fit[f"{finger}_02_{s}"] = head(mid)
        fit[f"{finger}_03_{s}"] = head(tip)
        fit[f"{finger}_04_leaf_{s}"] = tail(tip)
missing = [n for n in Q_REST if n not in fit]
assert not missing, f"unmapped game bones: {missing}"
bpy.ops.object.mode_set(mode="OBJECT")

# --- 4. Bake the pose into the mesh, world space --------------------------------------
for m in list(body.modifiers):
    if m.type != "ARMATURE":
        body.modifiers.remove(m)
with override(body):
    bpy.ops.object.modifier_apply(modifier=body.modifiers[0].name)
mw = body.matrix_world.copy()
body.parent = None
body.matrix_world = mw
with override(body):
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

# --- 5. Weights into the game's bone names ---------------------------------------------
rename = {"Columna": "spine_01", "Columna.000": "spine_02", "Columna.001": "spine_03", "Cuello": "neck_01",
          "Cabeza": "Head", "Boca": "Head", "Cadera": "pelvis"}
for side, s in (("L", "l"), ("R", "r")):
    rename.update({f"Hombro.{side}": f"clavicle_{s}", f"Hombro.{side}.000": f"clavicle_{s}",
                   f"Antebrazo.{side}": f"upperarm_{s}", f"Brazo.{side}": f"lowerarm_{s}", f"Mano.{side}": f"hand_{s}",
                   f"Antepierna.{side}": f"thigh_{s}", f"Pierna.{side}": f"calf_{s}", f"Pie.{side}": f"foot_{s}",
                   f"Dedos.{side}": f"ball_{s}"})
    for finger in ["thumb"] + FINGERS:
        for i, bn in enumerate(chains[(side, finger)]):
            rename[bn] = f"{finger}_0{i + 1}_{s}"
weights = [dict() for _ in body.data.vertices]
names = {g.index: g.name for g in body.vertex_groups}
unmapped = set()
for v in body.data.vertices:
    for g in v.groups:
        if g.weight <= 0:
            continue
        target = rename.get(names[g.group])
        if target is None:
            unmapped.add(names[g.group])
            continue
        weights[v.index][target] = weights[v.index].get(target, 0.0) + g.weight
print("UNMAPPED GROUPS", sorted(unmapped))
for g in list(body.vertex_groups):
    body.vertex_groups.remove(g)
groups = {n: body.vertex_groups.new(name=n) for n in Q_REST}
# A vertex without weights would collapse to the origin in Godot: copy the nearest weighted one.
from mathutils.kdtree import KDTree
weighted = [i for i, w in enumerate(weights) if sum(w.values()) > 0]
kd = KDTree(len(weighted))
for i in weighted:
    kd.insert(body.data.vertices[i].co, i)
kd.balance()
unweighted = [i for i, w in enumerate(weights) if sum(w.values()) <= 0]
for i in unweighted:
    weights[i] = dict(weights[kd.find(body.data.vertices[i].co)[1]])
print("UNWEIGHTED VERTS (given their nearest neighbour's weights)", len(unweighted))
for i, w in enumerate(weights):
    total = sum(w.values())
    for n, x in w.items():
        groups[n].add([i], x / total, "REPLACE")

# --- 6. Decimate per material (vertex-group-limited collapse) ---------------------------
mat_index = {m.name: i for i, m in enumerate(body.data.materials)}


def tri_count(o) -> int:
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def material_tris(o, idx: int) -> int:
    return sum(len(p.vertices) - 2 for p in o.data.polygons if p.material_index == idx)


print("TRIS BEFORE", tri_count(body), {m: material_tris(body, i) for m, i in mat_index.items()})
for mat, ratio in DECIMATE.items():
    idx = mat_index[mat]
    sel = body.vertex_groups.new(name="_decimate")
    verts = {v for p in body.data.polygons if p.material_index == idx for v in p.vertices}
    sel.add(list(verts), 1.0, "REPLACE")
    total = tri_count(body)
    own = material_tris(body, idx)
    mod = body.modifiers.new("dec", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = (total - own * (1.0 - ratio)) / total
    mod.vertex_group = "_decimate"
    mod.vertex_group_factor = 1000.0
    with override(body):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    body.vertex_groups.remove(body.vertex_groups["_decimate"])
print("TRIS AFTER", tri_count(body), {m: material_tris(body, i) for m, i in mat_index.items()})

# --- 7. Eyes into their own mesh (the eye light lights only them) ------------------------
eye = mat_index["ojo_material"]
eyes = body.copy()
eyes.data = body.data.copy()
bpy.context.scene.collection.objects.link(eyes)


def keep_faces(o, keep) -> None:
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not keep(f)], context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(o.data)
    bm.free()


keep_faces(eyes, lambda f: f.material_index == eye)
keep_faces(body, lambda f: f.material_index != eye)
eyes.name = "Eyes"
body.name = "Aelia"
for o in (body, eyes):
    with override(o):
        bpy.ops.object.material_slot_remove_unused()
for m in bpy.data.materials:
    if m.name in MATERIAL_NAMES:
        m.name = MATERIAL_NAMES[m.name]

# --- 8. Armature at her joints, game bone names and hierarchy, then export --------------
arm_data = bpy.data.armatures.new("AeliaSkeleton")
skel = bpy.data.objects.new("Armature", arm_data)
bpy.context.scene.collection.objects.link(skel)
bpy.context.view_layer.objects.active = skel
bpy.ops.object.mode_set(mode="EDIT")
# Q_REST values are [x, y, z, parent index, own index]; Godot orders bones parents first.
index_names = sorted(Q_REST, key=lambda n: Q_REST[n][4])
for n in index_names:
    b = arm_data.edit_bones.new(n)
    b.head = fit[n]
    b.tail = fit[n] + Vector((0, 0, 0.03))  # orientation is replaced in build_aelia.gd
    parent = Q_REST[n][3]
    if parent >= 0:
        b.parent = arm_data.edit_bones[index_names[parent]]
bpy.ops.object.mode_set(mode="OBJECT")
for o in (body, eyes):
    o.parent = skel
    mod = o.modifiers.new("Armature", "ARMATURE")
    mod.object = skel
print("TRIS FINAL", tri_count(body) + tri_count(eyes), "verts", len(body.data.vertices) + len(eyes.data.vertices))

for o in bpy.context.scene.objects:
    o.select_set(o in (skel, body, eyes))
bpy.context.view_layer.objects.active = skel
bpy.ops.export_scene.gltf(filepath=f"{OUT_DIR}/aelia.gltf", export_format="GLTF_SEPARATE", use_selection=True,
                          export_animations=False, export_skins=True, export_yup=True, export_apply=False,
                          export_texture_dir="textures", export_image_format="AUTO", export_morph=False)
print("EXPORTED", f"{OUT_DIR}/aelia.gltf")

# A T-pose preview for checking by eye.
fit_json = {n: [p.x, p.z, -p.y] for n, p in fit.items()}
open(f"{OUT_DIR}/fit.json", "w", encoding="utf-8").write(json.dumps(fit_json))
