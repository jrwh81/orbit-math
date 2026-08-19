// Optional, best-effort PixiJS-powered spark burst for claimed cells.
// Completely isolated from the rest of the game: if
// PixiJS fails to load or initialize for ANY reason (CDN hiccup, a
// browser without WebGL, an API mismatch I couldn't verify without
// being able to run this myself), every function here just returns
// false and does nothing further. grid_controller.js falls back to its
// original CSS-based shatter effect whenever that happens -- the game
// must never depend on this working.
//
// Deliberately pinned to PixiJS v7, not the current v8: v8's ESM build
// has a documented bug with some no-bundler CDN setups (rendering
// silently breaks, see pixijs/pixijs#10446) that v7 doesn't share. This
// app has no bundler by design, so the safer, longer-proven version
// wins over the newer one.

let pixiApp = null
let pixiNamespace = null
let pixiLoadAttempted = false

async function ensurePixi(hostElement) {
  if (pixiApp) return { app: pixiApp, PIXI: pixiNamespace }
  if (pixiLoadAttempted) return null // already failed once this page load -- don't keep retrying
  pixiLoadAttempted = true

  try {
    const PIXI = await import("pixi.js")

    const app = new PIXI.Application({
      resizeTo: hostElement,
      backgroundAlpha: 0,
      antialias: true,
      autoDensity: true,
      resolution: window.devicePixelRatio || 1
    })

    // hostElement (the existing .solve-popup-layer) is already
    // position:absolute via CSS -- just append the canvas as a child,
    // don't touch the host's own positioning.
    app.view.style.position = "absolute"
    app.view.style.inset = "0"
    app.view.style.pointerEvents = "none"
    hostElement.appendChild(app.view)

    pixiApp = app
    pixiNamespace = PIXI
    return { app, PIXI }
  } catch (e) {
    console.warn("PixiJS shatter effect unavailable, falling back to CSS particles:", e)
    return null
  }
}

// Matches the game's own accent palette (see --spark-a/-b/-c in
// application.css) so the burst reads as glowing sparks off the number,
// not generic confetti.
const PIECE_COLORS = [0x6ee3ff, 0xffb84d, 0xf0abfc]

// Uniform random point within a disk of the given radius, centered on
// the origin. (r = R*sqrt(random) is required, not just R*random --
// the latter clusters points near the center instead of spreading them
// evenly across the disk's area.)
function randomPointInDisk(radius) {
  const r = radius * Math.sqrt(Math.random())
  const theta = Math.random() * Math.PI * 2
  return { x: r * Math.cos(theta), y: r * Math.sin(theta) }
}

// xPx/yPx: the CENTER of the claimed cell, in pixels relative to
// hostElement. cellSizePx: the cell's actual on-screen width, used to
// size and space the pieces so the burst matches the number's size
// exactly, not an arbitrary guess.
//
// The ~20 pieces are scattered at random points WITHIN a disk roughly
// the size of the digit's footprint (not spawned from a single point),
// so at frame zero they visually approximate the number sitting right
// where it was -- then each one flies outward along its own direction
// from center, like the number itself broke apart into sparks, rather
// than particles bursting from a point.
export async function spawnPixiShatter(hostElement, xPx, yPx, cellSizePx, pieceCount = 20) {
  const pixi = await ensurePixi(hostElement)
  if (!pixi) return false

  const { app, PIXI } = pixi
  const diskRadius = cellSizePx * 0.46 // just inside the cell's own footprint

  for (let i = 0; i < pieceCount; i++) {
    const piece = new PIXI.Graphics()
    const color = PIECE_COLORS[Math.floor(Math.random() * PIECE_COLORS.length)]
    const size = cellSizePx * (0.14 + Math.random() * 0.12)

    piece.beginFill(color)
    piece.drawRoundedRect(-size / 2, -size / 2, size, size, size * 0.15)
    piece.endFill()

    const start = randomPointInDisk(diskRadius)
    piece.x = xPx + start.x
    piece.y = yPx + start.y
    piece.rotation = Math.random() * Math.PI * 2
    app.stage.addChild(piece)

    // Fly outward along the same direction from center as the piece's
    // own starting position -- pieces that started near the edge fly
    // out faster/further than ones that started near the middle, the
    // way a real shattering object would.
    const distFromCenter = Math.sqrt(start.x * start.x + start.y * start.y) || 0.01
    const dirX = start.x / distFromCenter
    const dirY = start.y / distFromCenter
    const speed = cellSizePx * (0.06 + Math.random() * 0.05)
    const vx = dirX * speed + (Math.random() - 0.5) * speed * 0.4
    let vy = dirY * speed + (Math.random() - 0.5) * speed * 0.4
    const rotationSpeed = (Math.random() - 0.5) * 0.35

    let life = 0
    const maxLife = 55 + Math.random() * 25 // ~1-1.3s at 60fps -- a real explosion, not a flicker

    const tick = () => {
      life += 1
      vy += cellSizePx * 0.0025 // gentle gravity, scaled to cell size
      piece.x += vx
      piece.y += vy
      piece.rotation += rotationSpeed
      // Hold full opacity briefly, THEN fade -- reads as "solid chunks
      // flying apart" rather than "sparkles dissolving immediately".
      const t = life / maxLife
      piece.alpha = t < 0.4 ? 1 : Math.max(0, 1 - (t - 0.4) / 0.6)

      if (life >= maxLife) {
        app.ticker.remove(tick)
        app.stage.removeChild(piece)
        piece.destroy()
      }
    }

    app.ticker.add(tick)
  }

  return true
}
