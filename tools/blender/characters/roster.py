"""Character definitions (colours, proportions, outfit pieces)."""

DEFENDER_IDS = ["ace", "rico", "maya", "jax", "kai", "bruno", "nova", "dex", "hana"]
ENEMY_IDS = ["runner", "sprinter", "armored", "jumper", "swarmer", "trickster", "captain",
             "slugger"]
BOSS_IDS = ["iron_slugger", "phantom_captain", "grand_slammer"]
ALL_IDS = DEFENDER_IDS + ENEMY_IDS + BOSS_IDS

BUDGET = {"defender": 14000, "enemy": 9000, "boss": 22000}

DEFENDERS = {
    "ace": dict(
        name="Ace", number=21, accent="#FF4B2B", skin="#9A6342", hair="#1A120D",
        iris="#4A2A12", hair_style="spiky", headwear="cap", emblem="flame",
        props=dict(scale=1.0, muscle=1.05),
        face=dict(jaw=1.0, chin=1.05, brow_angle=0.6, smile=0.5, smirk=0.4, eye_open=0.92),
    ),
    "rico": dict(
        name="Rico", number=8, accent="#3A7BD5", skin="#C68B59", hair="#2A1A10",
        iris="#5A3A1A", hair_style="buzz", headwear="catcher", emblem=None,
        props=dict(scale=1.0, muscle=1.15, chest_w=0.20, chest_d=0.145, waist_w=0.17,
                   waist_d=0.13, pelvis_w=0.185, pelvis_d=0.13, thigh_r=0.104, calf_r=0.068,
                   arm_r=0.058, forearm_r=0.049, sh_half=0.215, neck_r=0.068, upper_arm=0.27,
                   thigh=0.40, shin=0.40, belly=0.6, head=0.285),
        face=dict(jaw=1.0, jaw_w=1.12, chin=1.1, nose=1.15, nose_w=1.2, brow=1.15,
                  smile=0.3, width=1.06),
        gear=True, mitt="catcher",
    ),
    "maya": dict(
        name="Maya", number=5, accent="#2ECC71", skin="#E0AC86", hair="#22150F",
        iris="#5E7A2E", hair_style="ponytail", headwear="cap", emblem="diamond",
        props=dict(scale=0.95, muscle=0.85, chest_w=0.155, chest_d=0.112, waist_w=0.128,
                   waist_d=0.096, pelvis_w=0.165, pelvis_d=0.115, sh_half=0.185, arm_r=0.044,
                   forearm_r=0.037, wrist_r=0.026, thigh_r=0.088, calf_r=0.056, neck_r=0.048,
                   head=0.29, hand_scale=1.0),
        face=dict(jaw=0.15, jaw_w=0.92, chin=0.85, nose=0.78, nose_w=0.85, lips=1.25, eye=1.1,
                  brow=0.6, brow_thick=0.7, cheek=0.9, smile=0.6, lashes=True, width=0.96,
                  eye_open=1.0),
        wristbands=True,
    ),
    "jax": dict(
        name="Jax", number=34, accent="#F39C12", skin="#5E3B24", hair="#120B08",
        iris="#2E1C10", hair_style="buzz", headwear="cap_back", emblem="diamond",
        props=dict(scale=1.06, muscle=1.25, chest_w=0.19, chest_d=0.135, waist_w=0.152,
                   sh_half=0.225, arm_r=0.058, forearm_r=0.049, thigh_r=0.098, calf_r=0.064,
                   neck_r=0.066),
        face=dict(jaw=1.1, jaw_w=1.06, chin=1.0, nose=1.05, nose_w=1.25, lips=1.2, brow=1.1,
                  brow_angle=0.9, smile=0.1, eye_open=0.88),
        beard=True, eyeblack=True,
    ),
    "kai": dict(
        name="Kai", number=11, accent="#29B6F6", skin="#E6B98E", hair="#0E0B0A",
        iris="#2B1B10", hair_style="short", headwear="cap", emblem="diamond",
        props=dict(scale=1.04, muscle=0.92, chest_w=0.168, chest_d=0.12, waist_w=0.138,
                   sh_half=0.198, arm_r=0.048, forearm_r=0.041, thigh_r=0.088, calf_r=0.057,
                   upper_arm=0.30, forearm=0.265, thigh=0.45, shin=0.445),
        face=dict(jaw=0.75, chin=0.95, nose=0.85, nose_w=1.05, eye=0.95, asian=1.0, eye_open=0.9,
                  brow_thick=0.9, smile=0.35, cheek=1.1),
        sunglasses=True,
    ),
    "bruno": dict(
        name="Bruno", number=44, accent="#8E44AD", skin="#F0CDB4", hair="#B5471B",
        iris="#3D7CC9", hair_style="none", headwear="headband", emblem=None,
        props=dict(scale=1.08, muscle=1.35, chest_w=0.215, chest_d=0.155, waist_w=0.19,
                   waist_d=0.15, pelvis_w=0.195, pelvis_d=0.14, sh_half=0.235, arm_r=0.064,
                   forearm_r=0.060, wrist_r=0.036, thigh_r=0.11, calf_r=0.072, neck_r=0.074,
                   belly=0.7, hand_scale=1.2, head=0.285),
        face=dict(jaw=1.2, jaw_w=1.12, chin=1.0, nose=1.2, nose_w=1.25, brow=1.25, brow_thick=1.2,
                  width=1.05, smile=0.4, ear=1.05),
        full_beard=True, undershirt="elbow",
    ),
    "nova": dict(
        name="Nova", number=99, accent="#FFE135", skin="#D8A27A", hair="#DCD3C0",
        iris="#6FA3D8", hair_style="pixie", headwear="cap", emblem="bolt",
        props=dict(scale=0.96, muscle=0.88, chest_w=0.158, chest_d=0.114, waist_w=0.13,
                   waist_d=0.098, pelvis_w=0.162, pelvis_d=0.115, sh_half=0.19, arm_r=0.045,
                   forearm_r=0.038, wrist_r=0.027, thigh_r=0.088, calf_r=0.057, neck_r=0.049,
                   head=0.29, hand_scale=1.02),
        face=dict(jaw=0.1, jaw_w=0.9, chin=0.85, nose=0.75, nose_w=0.85, lips=1.15, eye=1.12,
                  brow=0.6, brow_thick=0.7, brow_angle=0.4, smile=0.5, smirk=0.3, lashes=True,
                  width=0.95, eye_open=0.92),
    ),
    "dex": dict(
        name="Dex", number=2, accent="#1ABC9C", skin="#B98058", hair="#2B1A12",
        iris="#3E8E5E", hair_style="curly", headwear="cap", emblem="diamond",
        props=dict(scale=0.98, muscle=0.9, chest_w=0.162, chest_d=0.116, waist_w=0.134,
                   sh_half=0.192, arm_r=0.046, forearm_r=0.039, thigh_r=0.086, calf_r=0.056),
        face=dict(jaw=0.7, chin=0.95, nose=0.95, brow_angle=-0.2, smirk=1.0, smile=0.2,
                  eye_open=0.85, brow_thick=1.0),
    ),
    "hana": dict(
        name="Hana", number=17, accent="#FF6FA8", skin="#EEC4A2", hair="#1C1311",
        iris="#4B2F1C", hair_style="bob", headwear="visor", emblem=None,
        props=dict(scale=0.94, muscle=0.85, chest_w=0.152, chest_d=0.11, waist_w=0.126,
                   waist_d=0.095, pelvis_w=0.16, pelvis_d=0.112, sh_half=0.182, arm_r=0.043,
                   forearm_r=0.036, wrist_r=0.026, thigh_r=0.086, calf_r=0.055, neck_r=0.047,
                   head=0.295, hand_scale=0.98),
        face=dict(jaw=0.0, jaw_w=0.9, chin=0.8, nose=0.72, nose_w=0.85, lips=1.2, eye=1.15,
                  brow=0.55, brow_thick=0.65, smile=0.8, lashes=True, width=0.95, asian=0.5),
    ),
}

# ---------------------------------------------------------------------------
# enemies ("The Wreckers")
# ---------------------------------------------------------------------------

ENEMIES = {
    "runner": dict(
        accent="#FF7A1A", height=1.80,
        props=dict(scale=1.0, muscle=1.0),
        helmet=dict(flap=True),
    ),
    "sprinter": dict(
        accent="#FFD400", height=1.82,
        props=dict(scale=1.0, muscle=0.85, chest_w=0.155, chest_d=0.112, waist_w=0.125,
                   waist_d=0.095, pelvis_w=0.155, sh_half=0.19, arm_r=0.044, forearm_r=0.037,
                   thigh_r=0.082, calf_r=0.054, thigh=0.45, shin=0.45),
        helmet=dict(flap=False, aero=True, brim=False), lightning=True,
    ),
    "armored": dict(
        accent="#8A939E", height=1.90,
        props=dict(scale=1.04, muscle=1.3, chest_w=0.215, chest_d=0.155, waist_w=0.185,
                   waist_d=0.145, pelvis_w=0.19, pelvis_d=0.135, sh_half=0.235, arm_r=0.062,
                   forearm_r=0.055, thigh_r=0.108, calf_r=0.07, neck_r=0.07),
        helmet=dict(flap=True, riot=True, brim=False), plates=True,
    ),
    "jumper": dict(
        accent="#9BE22D", height=1.82,
        props=dict(scale=1.0, muscle=0.95, thigh=0.45, shin=0.45, calf_r=0.058),
        helmet=dict(flap=True), springs=True,
    ),
    "swarmer": dict(
        accent="#FF7A1A", height=1.20,
        props=dict(scale=0.72, muscle=1.0, head=0.36, hand_scale=1.25, foot_scale=1.15,
                   thigh=0.38, shin=0.37, chest_w=0.185, chest_d=0.135, waist_w=0.16,
                   upper_arm=0.25, forearm=0.22),
        helmet=dict(flap=True, size=1.12), small=True,
    ),
    "trickster": dict(
        accent="#9B5DE5", height=1.84,
        props=dict(scale=1.01, muscle=0.85, chest_w=0.158, chest_d=0.114, waist_w=0.128,
                   pelvis_w=0.158, sh_half=0.19, arm_r=0.044, forearm_r=0.038, thigh_r=0.084,
                   calf_r=0.055, upper_arm=0.30, forearm=0.27),
        hood=True,
    ),
    "captain": dict(
        accent="#C0392B", height=1.92,
        props=dict(scale=1.05, muscle=1.2, chest_w=0.205, chest_d=0.145, waist_w=0.165,
                   sh_half=0.232, arm_r=0.058, forearm_r=0.05, thigh_r=0.1, calf_r=0.066,
                   neck_r=0.066),
        helmet=dict(flap=False, crest=True, brim=True), cape=True, armband=True,
    ),
    "slugger": dict(
        accent="#8B4513", height=2.40,
        props=dict(scale=1.30, muscle=1.4, chest_w=0.22, chest_d=0.16, waist_w=0.19,
                   waist_d=0.15, pelvis_w=0.195, pelvis_d=0.14, sh_half=0.24, arm_r=0.066,
                   forearm_r=0.062, wrist_r=0.038, thigh_r=0.112, calf_r=0.074, neck_r=0.076,
                   head=0.26, hand_scale=1.25, belly=0.4),
        helmet=dict(flap=True, riot=True), plates=True, bat=True, heavy=1.0,
    ),
    # bosses
    "iron_slugger": dict(
        accent="#FF6A00", height=3.60, boss=True,
        props=dict(scale=1.95, muscle=1.45, chest_w=0.23, chest_d=0.165, waist_w=0.20,
                   waist_d=0.155, pelvis_w=0.20, pelvis_d=0.145, sh_half=0.25, arm_r=0.07,
                   forearm_r=0.066, wrist_r=0.04, thigh_r=0.118, calf_r=0.08, neck_r=0.08,
                   head=0.25, hand_scale=1.3, belly=0.3),
        helmet=dict(flap=True, riot=True), plates=True, full_iron=True, seams=True, bat=True,
        heavy=1.0,
    ),
    "phantom_captain": dict(
        accent="#B45CFF", height=3.20, boss=True,
        props=dict(scale=1.70, muscle=1.15, chest_w=0.20, chest_d=0.14, waist_w=0.15,
                   sh_half=0.235, arm_r=0.054, forearm_r=0.047, thigh_r=0.095, calf_r=0.062,
                   neck_r=0.064, upper_arm=0.30, forearm=0.27),
        helmet=dict(flap=False, crest=True, brim=True), cape=True, tattered=True, ghost=True,
        heavy=0.7,
    ),
    "grand_slammer": dict(
        accent="#FFC83D", height=4.20, boss=True,
        props=dict(scale=2.28, muscle=1.5, chest_w=0.235, chest_d=0.17, waist_w=0.20,
                   waist_d=0.155, pelvis_w=0.20, pelvis_d=0.145, sh_half=0.255, arm_r=0.072,
                   forearm_r=0.068, wrist_r=0.042, thigh_r=0.12, calf_r=0.082, neck_r=0.08,
                   head=0.25, hand_scale=1.3),
        helmet=dict(flap=True, riot=True, crest=True), plates=True, gold=True, bat=True,
        golden_bat=True, cape=True, heavy=1.0,
    ),
}
