"""Character definitions (colours, proportions, outfit pieces)."""

DEFENDER_IDS = ["ace", "rico", "maya", "jax", "kai", "bruno", "nova", "dex", "hana"]
ENEMY_IDS = ["runner", "sprinter", "armored", "jumper", "swarmer", "trickster", "captain",
             "slugger"]
BOSS_IDS = ["iron_slugger", "phantom_captain", "grand_slammer"]
ALL_IDS = DEFENDER_IDS + ENEMY_IDS + BOSS_IDS

BUDGET = {"defender": 20000, "enemy": 9000, "boss": 22000}

# Defenders are stylised "hero" figures built by hero.py: ``body`` overrides
# hero.HERO_BASE (s-units), ``height`` is the overall height (top of the
# head-wear) in metres, ``face`` tunes the head shape and the expression.
DEFENDERS = {
    "ace": dict(
        idle="hip", height=1.814,
        name="Ace", number=21, accent="#FF4B2B", skin="#9A6342", hair="#1A120D",
        iris="#5A3418", hair_style="spiky", headwear="cap", emblem="flame",
        body=dict(muscle=1.08),
        face=dict(jaw=0.75, chin=1.05, brow_angle=0.55, mouth="smile", smile=0.55, smirk=0.35,
                  eye_open=0.92),
    ),
    "rico": dict(
        height=1.768,
        name="Rico", number=8, accent="#3A7BD5", skin="#C68B59", hair="#2A1A10",
        iris="#5A3A1A", hair_style="buzz", headwear="catcher", emblem=None,
        body=dict(muscle=1.15, chest_w=0.205, chest_d=0.142, waist_w=0.168, waist_d=0.132,
                  pelvis_w=0.172, pelvis_d=0.126, sh_half=0.228, arm_r=0.061, forearm_r=0.054,
                  thigh_r=0.106, calf_r=0.068, neck_r=0.068, thigh=0.345, shin=0.335, belly=0.5,
                  head=0.305, hip_half=0.104),
        face=dict(jaw=0.95, jaw_w=1.1, chin=1.1, nose=1.15, nose_w=1.2, brow=1.15,
                  mouth="grin", smile=0.75, width=1.05, brow_angle=0.15),
        gear=True, mitt="catcher",
    ),
    "maya": dict(
        height=1.733, female=True,
        name="Maya", number=5, accent="#2ECC71", skin="#E0AC86", hair="#22150F",
        iris="#5E7A2E", hair_style="ponytail", headwear="cap", emblem="diamond",
        body=dict(muscle=0.85, chest_w=0.158, chest_d=0.112, waist_w=0.118, waist_d=0.092,
                  pelvis_w=0.150, pelvis_d=0.108, sh_half=0.188, arm_r=0.044, forearm_r=0.040,
                  wrist_r=0.027, thigh_r=0.088, calf_r=0.056, neck_r=0.047, head=0.305,
                  hand_scale=1.22),
        face=dict(jaw=0.0, jaw_w=0.92, chin=0.85, nose=0.78, nose_w=0.85, eye=1.04, brow=0.6,
                  brow_thick=0.85, cheek=0.95, mouth="open", smile=0.6, mouth_w=0.95,
                  width=0.96, brow_angle=0.45),
        wristbands=True, undershirt="elbow",
    ),
    "jax": dict(
        idle="hip", height=1.923,
        name="Jax", number=34, accent="#F39C12", skin="#5E3B24", hair="#120B08",
        iris="#3A2414", hair_style="buzz", headwear="cap_back", emblem="diamond",
        body=dict(muscle=1.3, chest_w=0.205, chest_d=0.136, waist_w=0.148, sh_half=0.236,
                  arm_r=0.062, forearm_r=0.055, thigh_r=0.100, calf_r=0.066, neck_r=0.066,
                  head=0.30),
        face=dict(jaw=1.0, jaw_w=1.06, chin=1.0, nose=1.05, nose_w=1.25, brow=1.1,
                  brow_angle=0.85, mouth="smile", smile=0.2, eye_open=0.84),
        beard=True, eyeblack=True,
    ),
    "kai": dict(
        height=1.929,
        name="Kai", number=11, accent="#29B6F6", skin="#E6B98E", hair="#0E0B0A",
        iris="#2B1B10", hair_style="short", headwear="cap", emblem="diamond",
        body=dict(muscle=0.95, chest_w=0.172, chest_d=0.118, waist_w=0.128, sh_half=0.205,
                  arm_r=0.049, forearm_r=0.043, thigh_r=0.088, calf_r=0.058, upper_arm=0.30,
                  forearm=0.27, thigh=0.41, shin=0.40, head=0.31),
        face=dict(jaw=0.5, chin=0.95, nose=0.85, nose_w=1.05, eye=0.95, mouth="smile",
                  smile=0.45, cheek=1.05),
        sunglasses=True,
    ),
    "bruno": dict(
        height=1.951,
        name="Bruno", number=44, accent="#8E44AD", skin="#E9BE9E", hair="#B5471B",
        iris="#3D7CC9", hair_style="none", headwear="headband", emblem=None,
        body=dict(muscle=1.4, chest_w=0.228, chest_d=0.162, waist_w=0.200, waist_d=0.160,
                  pelvis_w=0.190, pelvis_d=0.140, sh_half=0.248, arm_r=0.069, forearm_r=0.066,
                  wrist_r=0.039, thigh_r=0.116, calf_r=0.075, neck_r=0.078, belly=0.9,
                  hand_scale=1.5, head=0.295, hip_half=0.108),
        face=dict(jaw=1.2, jaw_w=1.12, chin=1.0, nose=1.25, nose_w=1.3, brow=1.25,
                  brow_thick=1.3, width=1.06, mouth="grin", smile=0.7, ear=1.05,
                  brow_angle=0.2),
        full_beard=True, undershirt="elbow",
    ),
    "nova": dict(
        idle="hip", height=1.751, female=True,
        name="Nova", number=99, accent="#FFE135", skin="#D8A27A", hair="#E6DED0",
        iris="#4F8FD0", hair_style="pixie", headwear="cap", emblem="bolt", brow_col="#8A7458",
        body=dict(muscle=0.9, chest_w=0.162, chest_d=0.114, waist_w=0.120, waist_d=0.094,
                  pelvis_w=0.150, pelvis_d=0.110, sh_half=0.192, arm_r=0.046, forearm_r=0.041,
                  wrist_r=0.028, thigh_r=0.090, calf_r=0.057, neck_r=0.049, head=0.305,
                  hand_scale=1.24),
        face=dict(jaw=0.1, jaw_w=0.9, chin=0.85, nose=0.75, nose_w=0.85, eye=1.06, brow=0.6,
                  brow_thick=0.85, brow_angle=0.7, mouth="smile", smile=0.45, smirk=0.45,
                  width=0.95, eye_open=0.86),
    ),
    "dex": dict(
        idle="hip", height=1.778,
        name="Dex", number=2, accent="#1ABC9C", skin="#B98058", hair="#2B1A12",
        iris="#3E8E5E", hair_style="curly", headwear="cap", emblem="diamond",
        body=dict(muscle=0.92, chest_w=0.170, chest_d=0.116, waist_w=0.128, sh_half=0.200,
                  arm_r=0.048, forearm_r=0.042, thigh_r=0.088, calf_r=0.058),
        face=dict(jaw=0.5, chin=0.95, nose=0.95, mouth="smile", smirk=1.0, smile=0.15,
                  eye_open=0.80, brow_angle=0.1, iris_look=0.6),
    ),
    "hana": dict(
        height=1.722, female=True,
        name="Hana", number=17, accent="#FF6FA8", skin="#EEC4A2", hair="#2A1D19",
        iris="#5A3520", hair_style="bob", headwear="visor", emblem=None,
        body=dict(muscle=0.85, chest_w=0.155, chest_d=0.110, waist_w=0.116, waist_d=0.091,
                  pelvis_w=0.148, pelvis_d=0.108, sh_half=0.185, arm_r=0.043, forearm_r=0.039,
                  wrist_r=0.026, thigh_r=0.086, calf_r=0.055, neck_r=0.046, head=0.31,
                  hand_scale=1.2),
        face=dict(jaw=0.0, jaw_w=0.9, chin=0.8, nose=0.72, nose_w=0.85, eye=1.1, brow=0.55,
                  brow_thick=0.8, mouth="open", smile=0.85, width=0.95, brow_angle=0.2),
    ),
}

# ---------------------------------------------------------------------------
# enemies ("The Wreckers")
# ---------------------------------------------------------------------------

ENEMIES = {
    "runner": dict(
        number=13,
        accent="#FF7A1A", height=1.80,
        props=dict(scale=1.0, muscle=1.0),
        helmet=dict(flap=True),
    ),
    "sprinter": dict(
        number=7,
        accent="#FFD400", height=1.82,
        props=dict(scale=1.0, muscle=0.85, chest_w=0.155, chest_d=0.112, waist_w=0.125,
                   waist_d=0.095, pelvis_w=0.155, sh_half=0.19, arm_r=0.044, forearm_r=0.037,
                   thigh_r=0.082, calf_r=0.054, thigh=0.45, shin=0.45),
        helmet=dict(flap=False, aero=True, brim=False), lightning=True,
    ),
    "armored": dict(
        number=66,
        accent="#8A939E", height=1.90,
        props=dict(scale=1.04, muscle=1.3, chest_w=0.215, chest_d=0.155, waist_w=0.185,
                   waist_d=0.145, pelvis_w=0.19, pelvis_d=0.135, sh_half=0.235, arm_r=0.062,
                   forearm_r=0.055, thigh_r=0.108, calf_r=0.07, neck_r=0.07),
        helmet=dict(flap=True, riot=True, brim=False), plates=True,
    ),
    "jumper": dict(
        number=3,
        accent="#9BE22D", height=1.82,
        props=dict(scale=1.0, muscle=0.95, thigh=0.45, shin=0.45, calf_r=0.058),
        helmet=dict(flap=True), springs=True,
    ),
    "swarmer": dict(
        number=0,
        accent="#FF7A1A", height=1.20,
        props=dict(scale=0.72, muscle=1.0, head=0.38, hand_scale=1.3, foot_scale=1.2,
                   thigh=0.38, shin=0.37, chest_w=0.185, chest_d=0.135, waist_w=0.16,
                   upper_arm=0.25, forearm=0.22),
        helmet=dict(flap=True, size=1.25), small=True,
    ),
    "trickster": dict(
        number=9,
        accent="#9B5DE5", height=1.84,
        props=dict(scale=1.01, muscle=0.85, chest_w=0.158, chest_d=0.114, waist_w=0.128,
                   pelvis_w=0.158, sh_half=0.19, arm_r=0.044, forearm_r=0.038, thigh_r=0.084,
                   calf_r=0.055, upper_arm=0.30, forearm=0.27),
        hood=True,
    ),
    "captain": dict(
        number=1,
        accent="#C0392B", height=1.92,
        props=dict(scale=1.05, muscle=1.2, chest_w=0.205, chest_d=0.145, waist_w=0.165,
                   sh_half=0.232, arm_r=0.058, forearm_r=0.05, thigh_r=0.1, calf_r=0.066,
                   neck_r=0.066),
        helmet=dict(flap=False, crest=True, brim=True), cape=True, armband=True,
    ),
    "slugger": dict(
        number=99,
        accent="#8B4513", height=2.40,
        props=dict(scale=1.30, muscle=1.45, chest_w=0.235, chest_d=0.165, waist_w=0.18,
                   waist_d=0.14, pelvis_w=0.175, pelvis_d=0.13, sh_half=0.25, arm_r=0.068,
                   forearm_r=0.064, wrist_r=0.04, thigh_r=0.104, calf_r=0.074, neck_r=0.078,
                   head=0.25, hand_scale=1.3, belly=0.2),
        helmet=dict(flap=True, riot=True), plates=True, bat=True, heavy=1.0,
    ),
    # bosses
    "iron_slugger": dict(
        number=50,
        accent="#FF6A00", height=3.60, boss=True,
        props=dict(scale=1.95, muscle=1.45, chest_w=0.23, chest_d=0.165, waist_w=0.20,
                   waist_d=0.155, pelvis_w=0.20, pelvis_d=0.145, sh_half=0.25, arm_r=0.07,
                   forearm_r=0.066, wrist_r=0.04, thigh_r=0.118, calf_r=0.08, neck_r=0.08,
                   head=0.25, hand_scale=1.3, belly=0.3),
        helmet=dict(flap=True, riot=True), plates=True, full_iron=True, seams=True, bat=True,
        heavy=1.0,
    ),
    "phantom_captain": dict(
        number=13,
        accent="#B45CFF", height=3.20, boss=True,
        props=dict(scale=1.70, muscle=1.15, chest_w=0.20, chest_d=0.14, waist_w=0.15,
                   sh_half=0.235, arm_r=0.054, forearm_r=0.047, thigh_r=0.095, calf_r=0.062,
                   neck_r=0.064, upper_arm=0.30, forearm=0.27),
        helmet=dict(flap=False, crest=True, brim=True), cape=True, tattered=True, ghost=True,
        heavy=0.7,
    ),
    "grand_slammer": dict(
        number=1,
        accent="#FFC83D", height=4.20, boss=True,
        props=dict(scale=2.28, muscle=1.5, chest_w=0.235, chest_d=0.17, waist_w=0.20,
                   waist_d=0.155, pelvis_w=0.20, pelvis_d=0.145, sh_half=0.255, arm_r=0.072,
                   forearm_r=0.068, wrist_r=0.042, thigh_r=0.12, calf_r=0.082, neck_r=0.08,
                   head=0.25, hand_scale=1.3),
        helmet=dict(flap=True, riot=True, crest=True), plates=True, gold=True, bat=True,
        golden_bat=True, cape=True, heavy=1.0,
    ),
}
