//! Mr Boxington, drawn beside animated builds as truecolor half-block pixel art.
//!
//! The sprite is an 18x18 pixel canvas shown as 18x9 terminal cells. Each cell
//! stacks two pixels: `▀` paints the top pixel in fg over the bottom one in bg,
//! `▄` paints only the bottom pixel, and a space with bg paints both. Blank
//! pixels keep the terminal's own background.
//!
//! A frame is `draw(pose_at(inputs))`. Every rule is integer arithmetic on
//! whole milliseconds and counts. The only state carried between frames is the
//! lid the previous frame showed, because the lid descends at most one pixel
//! per drawn frame. `docs/public/favicon.svg` is the key pose, and a test keeps
//! it and the `favicon.png` and `apple-touch-icon.png` drawn from it in step
//! with this sprite; `TUIST_CARGO_CACHE_WRITE_FAVICON=1` makes that test rewrite all three.

pub(super) const WIDTH: usize = 18;
pub(super) const HEIGHT: usize = 9;
/// Canvas pixels per side. Cell row `r` shows pixel rows `2r` and `2r + 1`.
const SIZE: usize = 18;

pub(super) type Rgb = (u8, u8, u8);
/// Palette keys, one per pixel, `.` where the terminal shows through.
type Canvas = [[u8; SIZE]; SIZE];

/// A palette key's colour, or `None` for a transparent pixel.
fn color(key: u8) -> Option<Rgb> {
    Some(match key {
        b'A' => (230, 173, 84),  // amber: the front panel
        b'B' => (242, 196, 121), // bright: the lid's top face
        b'D' => (207, 143, 53),  // deep: the lid's front edge, the base, the open top's rim ends
        b'S' => (189, 125, 35),  // shade: the monocle chain
        b'K' => (32, 25, 14),    // ink: eyelid lines, pupils, ring, mustache
        b'W' => (245, 234, 214), // paper: the bare eye
        b'L' => (214, 232, 232), // lens
        b'G' => (255, 255, 255), // glint
        b'T' => (247, 228, 184), // packing tape
        b'H' => (84, 56, 22),    // the inside of the box, under a raised lid
        b'1' => (230, 150, 92),  // cheeks, hit share below 1/3
        b'2' => (229, 134, 99),  // cheeks, hit share below 2/3
        b'3' => (228, 122, 104), // cheeks, hit share 2/3 and up (the logo's rose)
        b'R' => (214, 62, 70),   // strawberry
        b'Y' => (247, 216, 138), // strawberry seed
        b'V' => (106, 168, 79),  // strawberry leaf
        _ => return None,
    })
}

/// Pixel art stamped onto the canvas: `rows[j]`'s `i`th key lands on pixel
/// `(x + i, y + j)`, and `.` leaves the pixel alone. The layers below skip
/// rustfmt so each one reads as the picture it draws.
#[derive(Clone, Copy)]
struct Layer {
    x: usize,
    y: usize,
    rows: &'static [&'static str],
}

impl Layer {
    const fn at(x: usize, y: usize, rows: &'static [&'static str]) -> Self {
        Self { x, y, rows }
    }

    /// The layer's opaque pixels as `(x, y, key)`, clipped to the canvas.
    fn pixels(self) -> impl Iterator<Item = (usize, usize, u8)> {
        self.rows
            .iter()
            .enumerate()
            .flat_map(move |(j, row)| {
                row.bytes()
                    .enumerate()
                    .filter(|&(_, key)| key != b'.')
                    .map(move |(i, key)| (self.x + i, self.y + j, key))
            })
            .filter(|&(x, y, _)| x < SIZE && y < SIZE)
    }
}

#[rustfmt::skip]
const BODY: Layer = Layer::at(1, 6, &[
    "AAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAA",
    "AAAAAAAAAAAAAAAA",
    "DDDDDDDDDDDDDDDD",
]);
/// The open top of the box, drawn whenever the lid is not shut on it.
const OPENING: Layer = Layer::at(1, 5, &["DHHHHHHHHHHHHHHD"]);
/// The lid, shut. While the build runs, the left end stays hinged to the box
/// and the right end rises by `lid` pixels. Its front edge overhangs the box.
#[rustfmt::skip]
const LID: Layer = Layer::at(0, 4, &[
    "..BBBBBBBBBBBBBB..",
    "DDDDDDDDDDDDDDDDDD",
]);
/// Success only: tape over the lid and a tab onto the front.
#[rustfmt::skip]
const TAPE: Layer = Layer::at(8, 4, &[
    "TT",
    "TT",
    "TT",
]);
/// Failure only: the lid knocked askew, shoved left with its left end down off
/// the edge of the box and its right end up over the open top.
#[rustfmt::skip]
const KNOCKED_LID: Layer = Layer::at(0, 3, &[
    "..........BBBB....",
    "....BBBBBBDDDDDD..",
    "BBBBDDDDDD........",
    "DDDD..............",
]);

/// The bare eye: the white, then the pupil, then the eyelid line over both.
/// The eyelid is exactly as wide as the white.
#[rustfmt::skip]
const EYE_WHITE: Layer = Layer::at(3, 9, &[
    "WWWW",
    "WWWW",
    ".WW.",
]);
/// The skeptic's flat eyelid rests on the pupil, as in the logo.
const EYELID: Layer = Layer::at(3, 8, &["KKKK"]);
/// Testing drops the eyelid a row, onto the white's top row.
const EYELID_SQUINT: Layer = Layer::at(3, 9, &["KKKK"]);
/// A blink: this line and no white or pupil. It shares a row with
/// `MONOCLE_SHUT`, so the two shut eyes are one level line.
const EYE_SHUT: Layer = Layer::at(3, 9, &["KKKK"]);
/// Failure only: both eyes bare and glum, lids sloping down to the outer corners.
#[rustfmt::skip]
const GLUM_LEFT: Layer = Layer::at(2, 8, &[
    "...KK",
    ".KKWW",
    ".WWWW",
    ".WKKW",
    "..KK.",
]);
#[rustfmt::skip]
const GLUM_RIGHT: Layer = Layer::at(10, 8, &[
    "KK...",
    "WWKK.",
    "WWWW.",
    "WKKW.",
    ".KK..",
]);
#[rustfmt::skip]
const PUPIL: &[&str] = &[
    "KK",
    "KK",
];
const PUPIL_DOWN: &[&str] = &["KK"];

#[rustfmt::skip]
const RING: Layer = Layer::at(8, 6, &[
    "..KKKK..",
    ".KLLLLK.",
    "KLLLLLLK",
    "KLLLLLLK",
    "KLLLLLLK",
    ".KLLLLK.",
    "..KKKK..",
]);
/// The one highlight that is always on: inside the lens a pixel in from the
/// ring's top-left chamfer, with lens between it and the tape tab.
const PARKED_GLINT: Layer = Layer::at(10, 8, &["G"]);
/// While looking left, put the highlight across the lens from the pupil.
const PARKED_GLINT_RIGHT: Layer = Layer::at(13, 8, &["G"]);
/// The eye behind the monocle, blinking.
const MONOCLE_SHUT: Layer = Layer::at(9, 9, &["KKKKKK"]);
/// Failure only: popped out and hanging by its dotted chain against the box's
/// right side, the whole ring on the amber so it reads on dark terminals too.
#[rustfmt::skip]
const DROPPED: Layer = Layer::at(13, 7, &[
    "..S.",
    "....",
    "..S.",
    "....",
    "..S.",
    ".KK.",
    "KGLK",
    "KLLK",
    ".KK.",
]);

/// Painted in the blush level's colour. Mirrored about the box's centre line,
/// each just outside a curled mustache tip.
const CHEEKS: [Layer; 2] = [Layer::at(1, 13, &["cc"]), Layer::at(15, 13, &["cc"])];

/// A handlebar: a centre hump above two lobes whose outer ends curl up. Twelve
/// pixels wide, so it centres on the box.
#[rustfmt::skip]
const MUSTACHE: Layer = Layer::at(3, 14, &[
    "K...KKKK...K",
    "KKKKK..KKKKK",
    ".KKK....KKK.",
]);
/// Failure only. Eleven wide: the dropped monocle hangs where a twelfth
/// column would go.
#[rustfmt::skip]
const MUSTACHE_DROOP: Layer = Layer::at(3, 14, &[
    "...KKKKK...",
    ".KKKK.KKKK.",
    "KK.......KK",
]);

/// Success with hits: the keepsake, a strawberry beside the tape. Its tip
/// rests on the lid's top face.
#[rustfmt::skip]
const STRAWBERRY: Layer = Layer::at(4, 0, &[
    "..V.",
    "VVVV",
    "RYRR",
    "RRYR",
    ".RR.",
]);

pub(super) const LID_MAX: u8 = 4;
/// The drawn lid's right edge descends at most this far per drawn frame.
const LID_STEP_PX: u8 = 1;
/// The Compiling list for [0, 4200), the progress bar for [4200, 5400), and
/// you for [5400, 7000).
const GAZE_LOOP_MS: u128 = 7000;
const GAZE_LIST_UNTIL_MS: u128 = 4200;
const GAZE_BAR_UNTIL_MS: u128 = 5400;
/// One blink per window, starting `500 + hash32(window) % 2800` ms into it.
const BLINK_WINDOW_MS: u128 = 4300;
const BLINK_EARLIEST_MS: u128 = 500;
const BLINK_SPREAD_MS: u128 = 2800;
const BLINK_MS: u128 = 160;
/// The glint's clock: band positions 0..3 show for 100 ms each, then the lens
/// rests for 240 ms.
const GLINT_CYCLE_MS: u128 = 640;
const GLINT_STEP_MS: u128 = 100;
const GLINT_POSITIONS: u128 = 4;
const GLINT_SWEEP_MS: u128 = GLINT_STEP_MS * GLINT_POSITIONS;
const GLINT_REST_MS: u128 = GLINT_CYCLE_MS - GLINT_SWEEP_MS;

/// A 32-bit integer hash of a blink window's index.
fn hash32(n: u32) -> u32 {
    let mut v = n.wrapping_mul(2_654_435_761).wrapping_add(12_345);
    v ^= v >> 15;
    v = v.wrapping_mul(2_246_822_519);
    v ^ (v >> 13)
}

fn blinking(ms: u128) -> bool {
    // Truncating the window index is the hash's own wrapping.
    let start =
        BLINK_EARLIEST_MS + u128::from(hash32((ms / BLINK_WINDOW_MS) as u32)) % BLINK_SPREAD_MS;
    (start..start + BLINK_MS).contains(&(ms % BLINK_WINDOW_MS))
}

fn gaze_at(ms: u128) -> Gaze {
    match ms % GAZE_LOOP_MS {
        cycle if cycle < GAZE_LIST_UNTIL_MS => Gaze::List,
        cycle if cycle < GAZE_BAR_UNTIL_MS => Gaze::Bar,
        _ => Gaze::You,
    }
}

/// The lid's target: `ceil(4 * (1 - min(p / 0.9, 1)))` with `p = done / total`,
/// in integers.
///
/// 4 px at the start, then 3, 2 and 1 from 22.5%, 45% and 67.5%, and shut from
/// 90%. An unknown or zero total holds the lid fully open.
fn lid_offset(done: usize, total: Option<usize>) -> u8 {
    let Some(total) = total.filter(|total| *total > 0) else {
        return LID_MAX;
    };
    // 9 * total overflows usize long before total does.
    let n = 9 * total as u128;
    let d = (10 * done.min(total) as u128).min(n);
    (u128::from(LID_MAX) * (n - d)).div_ceil(n) as u8
}

/// The lid to draw, given the lid the previous drawn frame showed.
///
/// Cargo's counts arrive in jumps: an incremental build's first progress line
/// is already 97/98, and frames are skipped while output flows. The target
/// alone would drop the lid several pixels at once, so the drawn lid descends
/// one pixel per drawn frame toward it. A higher target is taken at once. The
/// Model never produces one, since `done` only grows and the total is fixed, so
/// a wrong starting value corrects itself on the first frame.
fn step_lid(shown: u8, target: u8) -> u8 {
    if target < shown {
        shown - LID_STEP_PX
    } else {
        target
    }
}

/// The lens band position 0..3, or `None` for a matte lens.
///
/// The band is keyed off the clock, so a warm build sweeps continuously at a
/// steady pace. A cycle's sweep shows only when the last hit landed no earlier
/// than the rest just before it: a hit during a rest gets the next whole
/// sweep, a hit during a sweep gets the rest of that sweep, and no hit ever
/// shows parts of two sweeps. The lens is lit only while `since_hit_ms < 640`.
fn glint_at(ms: u128, since_hit_ms: Option<u128>) -> Option<u8> {
    let since_hit_ms = since_hit_ms?;
    let phase = ms % GLINT_CYCLE_MS;
    if phase >= GLINT_SWEEP_MS || since_hit_ms > phase + GLINT_REST_MS {
        return None;
    }
    Some((phase / GLINT_STEP_MS) as u8)
}

/// 0 before the first hit, then 1 to 3 as `hits / (hits + misses)` crosses
/// 1/3 and 2/3.
fn cheek_level(hits: u64, misses: u64) -> u8 {
    if hits == 0 {
        return 0;
    }
    let share = 3 * u128::from(hits) / (u128::from(hits) + u128::from(misses));
    1 + share.min(2) as u8
}

/// Everything a frame depends on, as whole numbers.
#[derive(Clone, Copy, Debug)]
pub(super) struct Inputs {
    /// Milliseconds since the build started.
    pub ms: u128,
    /// Milliseconds since the hit count last rose; `None` before the first hit.
    pub since_hit_ms: Option<u128>,
    /// Cargo's units finished, never test counts.
    pub done: usize,
    /// Cargo's units expected; `None` or 0 while unknown.
    pub total: Option<usize>,
    /// The lid the previous drawn frame showed; `LID_MAX` before the first.
    pub lid_shown: u8,
    pub hits: u64,
    pub misses: u64,
    pub testing: bool,
    /// `None` while the outcome is unsettled.
    pub ok: Option<bool>,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) enum Eye {
    #[default]
    Skeptic,
    /// Testing.
    Squint,
    /// A blink, which shuts both eyes.
    Shut,
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) enum Gaze {
    /// Left, toward the Compiling list.
    List,
    /// Down, toward the progress bar.
    Bar,
    /// Straight out of the terminal.
    #[default]
    You,
}

impl Gaze {
    /// The bare eye's pupil and the monocle's. The downward glance uses a
    /// shorter pupil so lens glass remains between it and the ring.
    fn pupils(self) -> [Layer; 2] {
        match self {
            Self::List => [Layer::at(3, 9, PUPIL), Layer::at(10, 9, PUPIL)],
            Self::Bar => [Layer::at(3, 10, PUPIL_DOWN), Layer::at(10, 10, PUPIL_DOWN)],
            Self::You => [Layer::at(4, 9, PUPIL), Layer::at(11, 9, PUPIL)],
        }
    }
}

/// What a frame shows. A finished failure is the default with `failed` set.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(super) struct Pose {
    /// Pixels the lid's right edge rises above its closed position.
    pub lid: u8,
    /// Tape over the shut lid, on success only.
    pub taped: bool,
    /// The knocked lid, glum eyes, drooping mustache and dropped monocle.
    pub failed: bool,
    pub eye: Eye,
    pub gaze: Gaze,
    /// The lens band position 0..3, or `None` for a matte lens.
    pub glint: Option<u8>,
    /// The blush level, 0 to 3.
    pub cheeks: u8,
    pub strawberry: bool,
}

/// Finished frames ignore the clock and the previous lid. While running, only
/// the eyes and the glint follow the clock.
pub(super) fn pose_at(inputs: Inputs) -> Pose {
    let cheeks = cheek_level(inputs.hits, inputs.misses);
    match inputs.ok {
        Some(false) => Pose {
            failed: true,
            ..Pose::default()
        },
        Some(true) => Pose {
            taped: true,
            cheeks,
            strawberry: inputs.hits > 0,
            ..Pose::default()
        },
        None => Pose {
            lid: step_lid(inputs.lid_shown, lid_offset(inputs.done, inputs.total)),
            eye: if blinking(inputs.ms) {
                Eye::Shut
            } else if inputs.testing {
                Eye::Squint
            } else {
                Eye::Skeptic
            },
            gaze: gaze_at(inputs.ms),
            glint: glint_at(inputs.ms, inputs.since_hit_ms),
            cheeks,
            ..Pose::default()
        },
    }
}

fn stamp(canvas: &mut Canvas, layer: Layer) {
    for (x, y, key) in layer.pixels() {
        canvas[y][x] = key;
    }
}

fn stamp_lid(canvas: &mut Canvas, rise: u8) {
    if rise == 0 {
        stamp(canvas, LID);
        return;
    }
    // Hinge the left end at the box. Each column drops by at most one pixel
    // when `rise` drops by one, so jumpy Cargo progress still reads as closing.
    let mut previous_y = LID.y + 1;
    for (x, _) in LID.rows[1].bytes().enumerate() {
        let front_y = LID.y + 1 - usize::from(rise) * x / (SIZE - 1);
        canvas[front_y][x] = b'D';
        if front_y < previous_y {
            canvas[previous_y][x] = b'D';
        }
        if (2..SIZE - 2).contains(&x) {
            canvas[front_y - 1][x] = b'B';
        }
        previous_y = front_y;
    }
}

/// Turn the lens pixels on diagonals `2p + 1` and `2p + 2` into glint. Only
/// pixels still showing lens light up: never the pupil, the ring or the shut
/// line.
fn light_band(canvas: &mut Canvas, position: u8) {
    let band = [2 * position + 1, 2 * position + 2].map(usize::from);
    for (x, y, key) in RING.pixels() {
        if key != b'L' || canvas[y][x] != b'L' {
            continue;
        }
        // The lens diagonal, 1 at the top-left corner to 8 at the bottom-right.
        if band.contains(&(x + y - RING.x - RING.y - 2)) {
            canvas[y][x] = b'G';
        }
    }
}

fn sprite(pose: Pose) -> Canvas {
    let mut canvas = [[b'.'; SIZE]; SIZE];
    stamp(&mut canvas, BODY);
    if pose.failed {
        for layer in [
            OPENING,
            KNOCKED_LID,
            GLUM_LEFT,
            GLUM_RIGHT,
            MUSTACHE_DROOP,
            DROPPED,
        ] {
            stamp(&mut canvas, layer);
        }
        return canvas;
    }
    if pose.lid > 0 {
        stamp(&mut canvas, OPENING);
    }
    stamp_lid(&mut canvas, pose.lid);
    if pose.taped {
        stamp(&mut canvas, TAPE);
    }
    if pose.cheeks > 0 {
        for (x, y, _) in CHEEKS.into_iter().flat_map(Layer::pixels) {
            canvas[y][x] = b'0' + pose.cheeks;
        }
    }
    let [eye_pupil, lens_pupil] = pose.gaze.pupils();
    let (eyelid, monocle) = match pose.eye {
        Eye::Skeptic => (EYELID, lens_pupil),
        Eye::Squint => (EYELID_SQUINT, lens_pupil),
        Eye::Shut => (EYE_SHUT, MONOCLE_SHUT),
    };
    if pose.eye != Eye::Shut {
        stamp(&mut canvas, EYE_WHITE);
        stamp(&mut canvas, eye_pupil);
    }
    stamp(&mut canvas, eyelid);
    stamp(&mut canvas, RING);
    stamp(&mut canvas, monocle);
    stamp(
        &mut canvas,
        if matches!(pose.gaze, Gaze::List | Gaze::Bar) {
            PARKED_GLINT_RIGHT
        } else {
            PARKED_GLINT
        },
    );
    if let Some(position) = pose.glint {
        light_band(&mut canvas, position);
    }
    stamp(&mut canvas, MUSTACHE);
    if pose.strawberry {
        stamp(&mut canvas, STRAWBERRY);
    }
    canvas
}

/// A terminal cell: a glyph from ` `, `▀` and `▄`, and its colours. A space
/// never carries fg.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct Cell {
    pub glyph: char,
    pub fg: Option<Rgb>,
    pub bg: Option<Rgb>,
}

fn cells(canvas: &Canvas) -> [[Cell; WIDTH]; HEIGHT] {
    std::array::from_fn(|r| {
        std::array::from_fn(|x| {
            let (top, bottom) = (canvas[2 * r][x], canvas[2 * r + 1][x]);
            let (glyph, fg, bg) = match (color(top), color(bottom)) {
                (None, None) => (' ', None, None),
                (Some(both), _) if top == bottom => (' ', None, Some(both)),
                (Some(upper), None) => ('▀', Some(upper), None),
                (None, Some(lower)) => ('▄', Some(lower), None),
                (Some(upper), Some(lower)) => ('▀', Some(upper), Some(lower)),
            };
            Cell { glyph, fg, bg }
        })
    })
}

pub(super) fn draw(pose: Pose) -> [[Cell; WIDTH]; HEIGHT] {
    cells(&sprite(pose))
}

#[cfg(test)]
#[path = "mascot_tests.rs"]
mod tests;
