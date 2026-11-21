#!/usr/bin/env bash
# Generates Lorna Mikalle's original sound effects and ambience loops with `rork ai audio sfx`.
# The official exploration theme (lorna_theme.mp3) is the user's own composition and is NOT generated.
set -u
OUT="ios-lorna-mikalle/LornaMikalle/Resources/Audio"
mkdir -p "$OUT"

gen() { # name duration prompt [--loop]
  local name="$1" dur="$2" prompt="$3" extra="${4:-}"
  if [ -f "$OUT/$name.mp3" ]; then echo "skip $name"; return; fi
  rork ai audio sfx "$prompt" -d "$dur" $extra -o "$OUT/$name.mp3" && echo "ok $name" || echo "FAILED $name"
}

batch1() {
  gen step_stone 0.5 "Single soft footstep of a sneaker on old Italian stone pavement, close, clean, no reverb"
  gen step_grass 0.5 "Single soft footstep on short grass, close, clean"
  gen step_run 0.5 "Single quick running footstep of a sneaker on asphalt, close, light"
  gen ui_tap 0.5 "Very short soft glassy UI tap click, gentle, anime game menu"
  gen ui_open 0.6 "Short airy whoosh with a soft magical shimmer for opening a game menu panel"
  gen ui_notify 1.0 "Gentle two-note bell notification chime, warm, anime RPG"
  gen ui_item 0.8 "Short sparkly item pickup sound, small coin and glitter, anime RPG"
}
batch2() {
  gen quest_complete 2.5 "Triumphant short orchestral sting with bells and strings for quest complete, anime RPG, warm and golden"
  gen reward 1.5 "Bright rewarding sparkle and coin cascade jingle, anime RPG"
  gen level_up 2.5 "Uplifting level up fanfare with rising harp glissando and chimes, anime RPG"
  gen discovery 2.0 "Mysterious wonder discovery chime with soft choir pad and harp, location discovered, anime RPG"
  gen spirit_alert 1.5 "Ethereal supernatural alert, soft ghostly whisper swell with glass harmonica, spirit nearby"
  gen encounter_start 2.0 "Dramatic anime encounter start, whoosh into a deep magical impact with shimmering tail"
  gen dialogue_next 0.5 "Tiny soft paper and bell blip for advancing dialogue text, gentle"
}
batch3() {
  gen spirit_reaction 1.2 "Small curious ghostly chirp, cute ethereal spirit voice without words, airy"
  gen friendship 2.0 "Warm heartfelt sparkle with soft piano notes rising, friendship bond increased"
  gen attack_strike 0.7 "Fast martial arts strike whoosh with a crisp energy snap, anime fight"
  gen impact 0.6 "Heavy punchy hit impact with a small magical crackle, anime fight"
  gen dodge 0.6 "Quick sharp swish of a fast dodge sidestep, anime"
  gen guard 1.0 "Magical golden barrier shield forming, resonant crystalline hum with a solid thud"
  gen enemy_defeat 2.0 "Enemy defeated, dark energy dissolving into a fading shimmering sparkle"
}
batch4() {
  gen boss_intro 3.5 "Ominous boss introduction, low brass hit, timpani roll and dark choir swell, Italian crime drama tension"
  gen golden_activate 2.5 "Golden energy power activation, rising bright magical surge with choir and sparkling crackles, anime transformation"
  gen heal 2.0 "Soft healing magic, warm shimmering chimes and gentle rising pad"
  gen teleport 1.2 "Instant teleport, reverse whoosh and golden pop with sparkles"
  gen special_attack 2.5 "Huge golden special attack, charged energy beam blast with explosive impact and sparkling debris, anime"
  gen battle_start 1.5 "Short tense battle start sting, taiko hit and string stab, anime RPG"
}
batch5() {
  gen amb_city 20 "Calm Italian city ambience, distant traffic, faint scooters, distant people chatting in a piazza, occasional distant church bell" --loop
  gen amb_nature 20 "Gentle park ambience with songbirds, soft wind in leaves, very calm" --loop
  gen amb_rain 20 "Steady medium rain on a city street, rain on pavement and gutters, no thunder" --loop
  gen amb_night 20 "Warm summer night ambience in a quiet Italian town, crickets, faint distant traffic hum" --loop
  gen amb_wind 15 "Soft steady outdoor wind breeze ambience, gentle gusts" --loop
  gen aura_loop 6 "Steady humming golden energy aura, warm magical drone with soft sparkles" --loop
}

if [ "${1:-all}" = "all" ]; then
  batch1 & batch2 & batch3 & batch4 & batch5 & wait
else
  "$1"
fi
echo "done"
