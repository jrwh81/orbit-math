// Tiny synthesized sound-effects module. Everything here is generated at
// runtime with the Web Audio API -- no .mp3/.wav files to fetch, so this
// works offline and inside the Capacitor-wrapped mobile shell exactly the
// same as in a browser.

let ctx = null

function audioContext() {
  // Browsers require a user gesture before audio can play, and Safari in
  // particular needs the context created (or resumed) from inside a real
  // click handler -- every public function here is only ever called from
  // inside a click, so this is safe.
  if (!ctx) {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext
    if (!AudioContextClass) return null
    ctx = new AudioContextClass()
  }
  if (ctx.state === "suspended") ctx.resume()
  return ctx
}

// Plays a single tone with a short attack/decay envelope so it doesn't
// click at the start/end.
function tone({ freq, duration = 0.12, type = "sine", startAt = 0, gain = 0.18, glideTo = null }) {
  const audio = audioContext()
  if (!audio) return

  const osc = audio.createOscillator()
  const amp = audio.createGain()

  osc.type = type
  osc.frequency.setValueAtTime(freq, audio.currentTime + startAt)
  if (glideTo) {
    osc.frequency.exponentialRampToValueAtTime(glideTo, audio.currentTime + startAt + duration)
  }

  amp.gain.setValueAtTime(0, audio.currentTime + startAt)
  amp.gain.linearRampToValueAtTime(gain, audio.currentTime + startAt + 0.01)
  amp.gain.exponentialRampToValueAtTime(0.001, audio.currentTime + startAt + duration)

  osc.connect(amp)
  amp.connect(audio.destination)

  osc.start(audio.currentTime + startAt)
  osc.stop(audio.currentTime + startAt + duration + 0.02)
}

// A short rising blip -- used when a link is added to the chain with "+".
// Pitch rises slightly with chain length so longer chains sound more
// energetic as you build them.
export function playAdd(stepIndex = 0) {
  const base = 340 + Math.min(stepIndex, 6) * 24
  tone({ freq: base, duration: 0.09, type: "sine", gain: 0.16 })
}

// A brighter two-note interval -- used when a link is added with "x"
// (double-click), so multiply always feels distinctly punchier than add.
export function playMultiply(stepIndex = 0) {
  const base = 420 + Math.min(stepIndex, 6) * 24
  tone({ freq: base, duration: 0.1, type: "square", gain: 0.09 })
  tone({ freq: base * 1.5, duration: 0.14, type: "triangle", gain: 0.11, startAt: 0.03 })
}

// A soft descending click -- used when the last link is removed.
export function playRemove() {
  tone({ freq: 260, glideTo: 160, duration: 0.1, type: "sine", gain: 0.12 })
}

// A little ascending arpeggio -- used when a chain successfully claims a
// target. This is the "reward" sound and deliberately the most elaborate.
export function playClaim() {
  const notes = [523.25, 659.25, 783.99, 1046.5] // C5 E5 G5 C6
  notes.forEach((freq, i) => {
    tone({ freq, duration: 0.16, type: "triangle", gain: 0.14, startAt: i * 0.06 })
  })
}

// A short low buzz -- used when a submitted chain doesn't match anything.
export function playFail() {
  tone({ freq: 160, glideTo: 90, duration: 0.22, type: "sawtooth", gain: 0.1 })
}

// A single bright chime, reused once per popup in a claim's reward
// cascade (equation -> points -> chain bonus, when it applies -- see
// grid_controller.js#showRewardSequence). step 0 is the base pitch, and
// each subsequent step climbs a fixed major third (4 semitones) higher
// -- the same interval playClaim's own arpeggio climbs by -- so the
// sequence sounds like it's building toward something, in step with
// each popup popping in right as the last one fades.
export function playReward(step = 0) {
  const base = 523.25 // C5, same starting note as playClaim's arpeggio
  const freq = base * Math.pow(2, (step * 4) / 12)
  tone({ freq, duration: 0.18, type: "triangle", gain: 0.15 })
}

// A brighter fanfare -- used once when a whole game completes.
export function playVictory() {
  const notes = [392, 523.25, 659.25, 783.99, 1046.5]
  notes.forEach((freq, i) => {
    tone({ freq, duration: 0.22, type: "triangle", gain: 0.16, startAt: i * 0.09 })
  })
}
