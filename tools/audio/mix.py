"""Mix targets: the playback loudness every sound should have before the call site's own offset.

"Base level" = the file's loudness + its manifest volume_db, where loudness is the maximum
momentary LUFS (400 ms window) for sound effects and integrated LUFS for music/ambience.
build_audio.py measures each file and sets volume_db = target - loudness, so a sound can be
re-synthesised louder or quieter without changing how loud it plays in the game.

Call sites keep their relative offsets (e.g. throws at -10 dB because they are frequent);
the audio manager also applies these volumes to Audio.ui(), which used to ignore them.

Targets by category (LUFS):
    music loops   -23   (calm+wave stems also -23; boss/tense layers add on top)
    jingles       -21   victory / defeat / stings
    stingers      -15   wave/inning/level/achievement/purchase/boss warning; combos rise -15/-14/-13
    card effects  -18   every cast sound sits together
    hits          -20   ball hit / catch / out (throw and swing a little lower, crit a little higher)
    crowd         -20   reactions (small cheers -23, roar -18)
    UI            -19   confirm/back/error, -22 short clicks, -24 hovers
    packs               rarity reveals rise strictly: common -20, rare -18, epic -16.5, legendary -15
"""
from __future__ import annotations

CATEGORIES = {
    "music": {"menu_theme": -23, "battle_theme": -23, "boss_theme": -23, "dugout_theme": -23.5,
              "practice_theme": -23.5, "victory": -20.5, "defeat": -21.5,
              "sting_boss_intro": -20, "sting_boss_defeat": -20},
    "stingers": {"wave_start": -16, "wave_clear": -15.5, "inning_end": -15, "combo_double": -15.5,
                 "combo_triple": -14.5, "combo_grand": -13.5, "boss_warning": -15, "boss_roar": -15.5,
                 "boss_slam": -17, "victory_fanfare": -15, "defeat_sting": -15.5, "level_up": -15.5,
                 "achievement": -15.5, "purchase": -15.5, "coin": -20, "run_scored": -15.5, "gate_open": -17.5,
                 "energy_full": -19},
    "card_effects": {"fire_cast": -18, "frost_cast": -18, "shadow_cast": -18, "lightning_zap": -18.5,
                     "magnet_pull": -18, "earth_rumble": -17.5, "barrage_impact": -18.5, "time_out_whistle": -18,
                     "rally_horn": -18, "aura_hum": -18.5, "heal_chime": -18, "explosion_small": -19,
                     "card_play": -19, "card_draw": -22, "fire_loop": -24},
    "hits": {"ball_hit": -20, "crit_hit": -18, "glove_catch": -21, "throw": -22, "bat_crack": -18,
             "enemy_out": -19.5, "swing_whoosh": -21, "footstep_dirt": -34, "defender_stunned": -21,
             "wall_break": -19, "shield_block": -19.5},
    "crowd": {"crowd_cheer": -19.5, "crowd_groan": -20.5, "crowd_ooh": -20.5, "crowd_small": -23,
              "crowd_big": -20, "crowd_roar": -18, "crowd_groan_small": -22, "crowd_chant": -22.5,
              "crowd_stomp": -22},
    "ui": {"ui_back": -19, "ui_confirm": -19, "ui_error": -19, "card_denied": -19.5, "ui_slide": -20.5,
           "ui_click": -22, "ui_tab": -22, "ui_toggle": -22, "ui_hover": -24, "card_hover": -24},
    "packs": {"pack_shake": -21, "pack_tear": -18, "card_whoosh": -22, "card_flip": -21,
              "reveal_common": -20, "reveal_rare": -18, "reveal_epic": -16.5, "reveal_legendary": -15},
}
TARGETS = {k: v for cat in CATEGORIES.values() for k, v in cat.items()}


def category_of(name: str) -> str:
    for cat, names in CATEGORIES.items():
        if name in names:
            return cat
    return "other"


def apply_targets(files: list) -> None:
    """Set volume_db on manifest entries in place (groups share one volume from their mean loudness)."""
    by_key: dict = {}
    for e in files:
        key = e.get("group") or e["name"]
        if key in TARGETS and e.get("loudness") is not None:
            by_key.setdefault(key, []).append(e)
    for key, entries in by_key.items():
        mean = sum(e["loudness"] for e in entries) / len(entries)
        vol = round(TARGETS[key] - mean, 1)
        for e in entries:
            e["volume_db"] = vol
            e["mix_target"] = TARGETS[key]
            e["mix_category"] = category_of(key)
