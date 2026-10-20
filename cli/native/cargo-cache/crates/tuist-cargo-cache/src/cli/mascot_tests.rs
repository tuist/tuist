use super::*;
use std::fmt::Write as _;

/// A running frame's inputs, the lid caught up with a known total of 60.
fn running() -> Inputs {
    Inputs {
        ms: 0,
        since_hit_ms: None,
        done: 0,
        total: Some(60),
        lid_shown: LID_MAX,
        hits: 0,
        misses: 0,
        testing: false,
        ok: None,
    }
}

/// The logo pose, and the favicon: the success frame at full cheeks, no strawberry.
fn key_pose() -> Pose {
    Pose {
        taped: true,
        cheeks: 3,
        ..Pose::default()
    }
}

fn rows(canvas: &Canvas) -> Vec<&str> {
    canvas
        .iter()
        .map(|row| std::str::from_utf8(row).unwrap())
        .collect()
}

fn every_pose() -> Vec<Pose> {
    let mut poses = Vec::new();
    for lid in 0..=LID_MAX {
        for eye in [Eye::Skeptic, Eye::Squint, Eye::Shut] {
            for gaze in [Gaze::List, Gaze::Bar, Gaze::You] {
                for glint in [None, Some(0), Some(1), Some(2), Some(3)] {
                    for cheeks in 0..=3 {
                        poses.push(Pose {
                            lid,
                            eye,
                            gaze,
                            glint,
                            cheeks,
                            ..Pose::default()
                        });
                    }
                }
            }
        }
    }
    for cheeks in 0..=3 {
        for strawberry in [false, true] {
            poses.push(Pose {
                taped: true,
                cheeks,
                strawberry,
                ..Pose::default()
            });
        }
    }
    poses.push(Pose {
        failed: true,
        ..Pose::default()
    });
    poses
}

#[test]
fn every_cell_shows_its_two_pixels_with_half_blocks() {
    for pose in every_pose() {
        let canvas = sprite(pose);
        for key in canvas.iter().flatten() {
            assert!(*key == b'.' || color(*key).is_some(), "{pose:?}");
        }
        let cells = cells(&canvas);
        assert_eq!((cells.len(), cells[0].len()), (9, 18));
        for (r, row) in cells.iter().enumerate() {
            for (x, cell) in row.iter().enumerate() {
                // What the terminal paints on top and below. A half block
                // without fg would paint the terminal's default fg.
                let shown = match cell.glyph {
                    ' ' if cell.fg.is_none() => (cell.bg, cell.bg),
                    '▀' if cell.fg.is_some() => (cell.fg, cell.bg),
                    '▄' if cell.fg.is_some() => (cell.bg, cell.fg),
                    _ => panic!("{cell:?} at ({x}, {r}) in {pose:?}"),
                };
                let pixels = (color(canvas[2 * r][x]), color(canvas[2 * r + 1][x]));
                assert_eq!(shown, pixels, "({x}, {r}) in {pose:?}");
            }
        }
    }
}

#[test]
fn monocle_pupils_stay_clear_of_the_glint_and_ring() {
    for gaze in [Gaze::List, Gaze::Bar, Gaze::You] {
        for glint in [None, Some(0), Some(1), Some(2), Some(3)] {
            let canvas = sprite(Pose {
                gaze,
                glint,
                ..Pose::default()
            });
            let [_, pupil] = gaze.pupils();
            for (x, y, _) in pupil.pixels() {
                assert_eq!(canvas[y][x], b'K', "{gaze:?} {glint:?} at ({x}, {y})");
                if glint.is_none() && y == pupil.y + pupil.rows.len() - 1 {
                    assert_eq!(canvas[y + 1][x], b'L', "{gaze:?} at ({x}, {y})");
                }
            }
            let parked = if matches!(gaze, Gaze::List | Gaze::Bar) {
                PARKED_GLINT_RIGHT
            } else {
                PARKED_GLINT
            };
            assert_eq!(canvas[parked.y][parked.x], b'G');
        }
    }
}

#[test]
fn both_pupils_follow_the_downward_left_glance() {
    let [list_eye, list_lens] = Gaze::List.pupils();
    let [bar_eye, bar_lens] = Gaze::Bar.pupils();
    let [you_eye, you_lens] = Gaze::You.pupils();
    for (list, bar, you) in [
        (list_eye, bar_eye, you_eye),
        (list_lens, bar_lens, you_lens),
    ] {
        assert!(list.x < you.x);
        assert_eq!(bar.x, list.x);
        assert_eq!(bar.y, list.y + 1);
    }
}

#[test]
fn finished_frames_ignore_the_clock_and_the_previous_lid() {
    for ok in [true, false] {
        let finished = Inputs {
            since_hit_ms: Some(0),
            done: 60,
            hits: 3,
            misses: 4,
            ok: Some(ok),
            ..running()
        };
        let base = pose_at(finished);
        for ms in (0..20_000).step_by(37) {
            for since_hit_ms in [0, 90, 650] {
                for lid_shown in 0..=LID_MAX {
                    let inputs = Inputs {
                        ms,
                        since_hit_ms: Some(since_hit_ms),
                        lid_shown,
                        ..finished
                    };
                    assert_eq!(pose_at(inputs), base);
                }
            }
        }
    }
}

#[test]
fn the_lid_target_never_rises_and_unknown_totals_hold_it_up() {
    for total in [None, Some(0)] {
        assert!((0..1000).all(|done| lid_offset(done, total) == LID_MAX));
    }
    for total in 1..500 {
        // Overruns clamp.
        let targets: Vec<_> = (0..total + 3)
            .map(|done| lid_offset(done, Some(total)))
            .collect();
        assert_eq!((targets[0], targets[total + 2]), (LID_MAX, 0), "{total}");
        assert!(targets.is_sorted_by(|a, b| a >= b), "rises at {total}");
        let moves = targets.windows(2).filter(|pair| pair[0] != pair[1]);
        assert!(moves.count() <= usize::from(LID_MAX), "{total}");
    }
    let at = |total, dones: &[usize]| -> Vec<u8> {
        dones
            .iter()
            .map(|&done| lid_offset(done, Some(total)))
            .collect()
    };
    assert_eq!(
        at(60, &[13, 14, 26, 27, 40, 41, 53, 54]),
        [4, 3, 3, 2, 2, 1, 1, 0]
    );
    assert_eq!(
        at(400, &[89, 90, 179, 180, 269, 270, 359, 360]),
        [4, 3, 3, 2, 2, 1, 1, 0]
    );
    assert_eq!(at(3, &[0, 1, 2, 3]), [4, 3, 2, 0]);
    assert_eq!(lid_offset(97, Some(98)), 0);
    assert_eq!(lid_offset(usize::MAX, Some(usize::MAX)), 0);
    assert_eq!(lid_offset(usize::MAX, Some(1)), 0);
    assert_eq!(lid_offset(0, Some(usize::MAX)), LID_MAX);
}

#[test]
fn the_drawn_lid_descends_one_pixel_and_rises_at_once() {
    for shown in 0..=LID_MAX {
        for target in 0..=LID_MAX {
            let expected = if target < shown { shown - 1 } else { target };
            assert_eq!(step_lid(shown, target), expected, "{shown} {target}");
        }
    }
}

#[test]
fn a_lone_hit_shows_one_sweep_in_order() {
    for step in [80, 90, 100] {
        for hit in 20_000..20_000 + GLINT_CYCLE_MS {
            let lit: Vec<_> = (hit..hit + 2000)
                .step_by(step)
                .map(|ms| glint_at(ms, Some(ms - hit)))
                .collect();
            let runs = lit
                .chunk_by(|a, b| a.is_some() == b.is_some())
                .filter(|run| run[0].is_some());
            assert!(runs.count() <= 1, "a hit at {hit} lights two sweeps");
            let mut positions: Vec<_> = lit.into_iter().flatten().collect();
            assert!(positions.is_sorted(), "a hit at {hit} runs backwards");
            // A hit in the rest or during the first position gets all four.
            if !(GLINT_STEP_MS..GLINT_SWEEP_MS).contains(&(hit % GLINT_CYCLE_MS)) {
                positions.dedup();
                assert_eq!(positions, [0, 1, 2, 3], "a hit at {hit} misses its sweep");
            }
        }
    }
    for ms in (0..30_000).step_by(7) {
        for since_hit_ms in (0..800).step_by(10) {
            if glint_at(ms, Some(since_hit_ms)).is_some() {
                assert!(since_hit_ms < GLINT_CYCLE_MS, "{ms} {since_hit_ms}");
            }
        }
        // A hit before every frame: the band follows the clock alone.
        let phase = ms % GLINT_CYCLE_MS;
        let expected = (phase < GLINT_SWEEP_MS).then_some((phase / GLINT_STEP_MS) as u8);
        assert_eq!(glint_at(ms, Some(0)), expected, "{ms}");
        assert_eq!(glint_at(ms, None), None);
    }
}

#[test]
fn one_blink_per_window_and_the_gaze_loop() {
    assert_eq!(
        [hash32(0), hash32(1), hash32(2)],
        [125_198_284, 4_151_757_144, 2_535_090_149]
    );
    for window in 0..200 {
        let shut: Vec<_> = (window * BLINK_WINDOW_MS..(window + 1) * BLINK_WINDOW_MS)
            .filter(|&ms| blinking(ms))
            .collect();
        assert_eq!(shut.len(), 160, "{window}");
        assert_eq!(shut[159] - shut[0], 159, "{window}");
        if window < 3 {
            let start = shut[0] - window * BLINK_WINDOW_MS;
            assert_eq!(start, [2384, 1644, 1449][window as usize]);
        }
    }
    // Both eyes shut on one level line.
    let blink = sprite(Pose {
        eye: Eye::Shut,
        ..Pose::default()
    });
    assert_eq!(&blink[9], b".AAKKKKAKKKKKKKKA.");
    assert_eq!(
        [0, 4199, 4200, 5399, 5400, 6999, 7000].map(gaze_at),
        [
            Gaze::List,
            Gaze::List,
            Gaze::Bar,
            Gaze::Bar,
            Gaze::You,
            Gaze::You,
            Gaze::List
        ]
    );
}

#[test]
fn cheeks_warm_with_the_hit_share() {
    assert_eq!((cheek_level(0, 0), cheek_level(0, 50)), (0, 0));
    assert_eq!(
        [1, 9, 10, 19, 20, 30].map(|hits| cheek_level(hits, 30 - hits)),
        [1, 1, 2, 2, 3, 3]
    );
    assert_eq!(cheek_level(u64::MAX, u64::MAX), 2);
}

#[test]
fn only_a_build_that_hit_the_cache_earns_the_strawberry() {
    let finished = |hits, ok| {
        pose_at(Inputs {
            since_hit_ms: (hits > 0).then_some(5000),
            done: 60,
            hits,
            misses: 10,
            ok,
            ..running()
        })
    };
    for (hits, ok, strawberry) in [
        (0, Some(true), false),
        (1, Some(true), true),
        (1, None, false),
        (1, Some(false), false),
    ] {
        let pose = finished(hits, ok);
        assert_eq!(pose.strawberry, strawberry, "{hits} {ok:?}");
        let drawn = sprite(pose).iter().flatten().any(|key| *key == b'R');
        assert_eq!(drawn, strawberry, "{hits} {ok:?}");
    }
}

#[test]
fn failure_differs_from_every_success() {
    let failed = sprite(Pose {
        failed: true,
        ..Pose::default()
    });
    for cheeks in 0..=3 {
        for strawberry in [false, true] {
            let success = Pose {
                taped: true,
                cheeks,
                strawberry,
                ..Pose::default()
            };
            assert_ne!(failed, sprite(success));
        }
    }
}

#[test]
fn golden_sprites() {
    let start = pose_at(Inputs {
        total: None,
        ..running()
    });
    // Testing, looking at the bar, just after a hit, the lid a pixel up.
    let testing = pose_at(Inputs {
        ms: 4600,
        since_hit_ms: Some(50),
        done: 45,
        lid_shown: 2,
        hits: 2,
        misses: 8,
        testing: true,
        ..running()
    });
    let failed = pose_at(Inputs {
        ms: 9000,
        since_hit_ms: Some(5000),
        done: 24,
        lid_shown: 2,
        hits: 10,
        misses: 14,
        ok: Some(false),
        ..running()
    });
    assert_eq!(
        rows(&sprite(key_pose())),
        [
            "..................",
            "..................",
            "..................",
            "..................",
            "..BBBBBBTTBBBBBB..",
            "DDDDDDDDTTDDDDDDDD",
            ".AAAAAAATTKKKKAAA.",
            ".AAAAAAAAKLLLLKAA.",
            ".AAKKKKAKLGLLLLKA.",
            ".AAWKKWAKLLKKLLKA.",
            ".AAWKKWAKLLKKLLKA.",
            ".AAAWWAAAKLLLLKAA.",
            ".AAAAAAAAAKKKKAAA.",
            ".33AAAAAAAAAAAA33.",
            ".AAKAAAKKKKAAAKAA.",
            ".AAKKKKKAAKKKKKAA.",
            ".AAAKKKAAAAKKKAAA.",
            ".DDDDDDDDDDDDDDDD.",
        ]
    );
    assert_eq!(
        (start.lid, start.gaze, start.eye),
        (LID_MAX, Gaze::List, Eye::Skeptic)
    );
    assert_eq!(
        rows(&sprite(start)),
        [
            "..................",
            ".............BBB.D",
            ".........BBBBDDDDD",
            ".....BBBBDDDDD....",
            "..BBBDDDDD........",
            "DDDDDDHHHHHHHHHHD.",
            ".AAAAAAAAAKKKKAAA.",
            ".AAAAAAAAKLLLLKAA.",
            ".AAKKKKAKLLLLGLKA.",
            ".AAKKWWAKLKKLLLKA.",
            ".AAKKWWAKLKKLLLKA.",
            ".AAAWWAAAKLLLLKAA.",
            ".AAAAAAAAAKKKKAAA.",
            ".AAAAAAAAAAAAAAAA.",
            ".AAKAAAKKKKAAAKAA.",
            ".AAKKKKKAAKKKKKAA.",
            ".AAAKKKAAAAKKKAAA.",
            ".DDDDDDDDDDDDDDDD.",
        ]
    );
    assert_eq!(
        testing,
        Pose {
            lid: 1,
            eye: Eye::Squint,
            gaze: Gaze::Bar,
            glint: Some(1),
            cheeks: 1,
            ..Pose::default()
        }
    );
    assert_eq!(
        rows(&sprite(testing)),
        [
            "..................",
            "..................",
            "..................",
            "..................",
            "..BBBBBBBBBBBBBB.D",
            "DDDDDDDDDDDDDDDDDD",
            ".AAAAAAAAAKKKKAAA.",
            ".AAAAAAAAKLLGGKAA.",
            ".AAAAAAAKLLGGGLKA.",
            ".AAKKKKAKLGGLLLKA.",
            ".AAKKWWAKGKKLLLKA.",
            ".AAAWWAAAKLLLLKAA.",
            ".AAAAAAAAAKKKKAAA.",
            ".11AAAAAAAAAAAA11.",
            ".AAKAAAKKKKAAAKAA.",
            ".AAKKKKKAAKKKKKAA.",
            ".AAAKKKAAAAKKKAAA.",
            ".DDDDDDDDDDDDDDDD.",
        ]
    );
    assert_eq!(
        failed,
        Pose {
            failed: true,
            ..Pose::default()
        }
    );
    assert_eq!(
        rows(&sprite(failed)),
        [
            "..................",
            "..................",
            "..................",
            "..........BBBB....",
            "....BBBBBBDDDDDD..",
            "BBBBDDDDDDHHHHHHD.",
            "DDDDAAAAAAAAAAAAA.",
            ".AAAAAAAAAAAAAASA.",
            ".AAAAKKAAAKKAAAAA.",
            ".AAKKWWAAAWWKKASA.",
            ".AAWWWWAAAWWWWAAA.",
            ".AAWKKWAAAWKKWASA.",
            ".AAAKKAAAAAKKAKKA.",
            ".AAAAAAAAAAAAKGLK.",
            ".AAAAAKKKKKAAKLLK.",
            ".AAAKKKKAKKKKAKKA.",
            ".AAKKAAAAAAAKKAAA.",
            ".DDDDDDDDDDDDDDDD.",
        ]
    );
}

/// Favicon pixel `(x, y)`'s palette key: sprite pixel `(x + 1, y + 3)`, the key
/// pose's 16 box columns centred vertically. The last favicon row falls below
/// the canvas and stays transparent.
fn favicon_key(canvas: &Canvas, x: usize, y: usize) -> u8 {
    canvas.get(y + 3).map_or(b'.', |row| row[x + 1])
}

const FAVICON: usize = 16;

/// The favicon, with one merged `<path>` per colour.
fn favicon_svg() -> String {
    const N: usize = FAVICON;
    let canvas = sprite(key_pose());
    let key = |x: usize, y: usize| favicon_key(&canvas, x, y);
    // Most-used colour first; ties keep the order they are first met in.
    let mut keys: Vec<(u8, usize)> = Vec::new();
    for y in 0..N {
        for x in 0..N {
            if key(x, y) == b'.' {
                continue;
            }
            match keys.iter_mut().find(|(k, _)| *k == key(x, y)) {
                Some((_, count)) => *count += 1,
                None => keys.push((key(x, y), 1)),
            }
        }
    }
    keys.sort_by_key(|&(_, count)| std::cmp::Reverse(count));
    let mut svg = String::from(concat!(
        r#"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" shape-rendering="crispEdges" role="img" aria-labelledby="tuist_cargo_cache-favicon-title" aria-describedby="tuist_cargo_cache-favicon-desc">"#,
        "\n",
        r#"  <title id="tuist_cargo_cache-favicon-title">mr boxington</title>"#,
        "\n",
        r#"  <desc id="tuist_cargo_cache-favicon-desc">Mr Boxington as a 16 by 16 pixel icon: a cardboard box taped shut, with a skeptical eye, a monocle, a handlebar mustache and rosy cheeks</desc>"#,
        "\n",
    ));
    for (paint, _) in keys {
        // Greedy rectangles: along each row, as wide and then as tall as the colour runs.
        let mut todo = [[false; N]; N];
        for (y, row) in todo.iter_mut().enumerate() {
            for (x, pixel) in row.iter_mut().enumerate() {
                *pixel = key(x, y) == paint;
            }
        }
        let (r, g, b) = color(paint).unwrap();
        write!(svg, r##"  <path fill="#{r:02x}{g:02x}{b:02x}" d=""##).unwrap();
        for y in 0..N {
            let mut x = 0;
            while x < N {
                if !todo[y][x] {
                    x += 1;
                    continue;
                }
                let w = (x..N).take_while(|&i| todo[y][i]).count();
                let h = (y..N)
                    .take_while(|&j| todo[j][x..x + w].iter().all(|&pixel| pixel))
                    .count();
                for row in &mut todo[y..y + h] {
                    row[x..x + w].fill(false);
                }
                write!(svg, "M{x} {y}h{w}v{h}h-{w}z").unwrap();
                x += w;
            }
        }
        svg.push_str("\"/>\n");
    }
    svg.push_str("</svg>\n");
    svg
}

/// The PNG icons: the favicon scaled up by whole pixels and centred on a
/// square, over a backdrop or left transparent.
const PNG_ICONS: [(&str, usize, usize, Option<Rgb>); 2] = [
    ("favicon.png", 64, 4, None),
    // iOS fills transparency with black, so the touch icon sits on the site's background.
    ("apple-touch-icon.png", 180, 10, Some((0x19, 0x17, 0x13))),
];

fn icon_rgba(side: usize, scale: usize, backdrop: Option<Rgb>) -> Vec<u8> {
    let canvas = sprite(key_pose());
    let inset = (side - FAVICON * scale) / 2;
    let mut rgba = Vec::with_capacity(side * side * 4);
    for y in 0..side {
        for x in 0..side {
            let inside = |at: usize| at.checked_sub(inset).filter(|at| *at < FAVICON * scale);
            let key = match (inside(x), inside(y)) {
                (Some(x), Some(y)) => favicon_key(&canvas, x / scale, y / scale),
                _ => b'.',
            };
            match color(key).or(backdrop) {
                Some((r, g, b)) => rgba.extend([r, g, b, 255]),
                None => rgba.extend([0; 4]),
            }
        }
    }
    rgba
}

/// An 8-bit RGBA PNG with unfiltered rows.
fn encode_png(side: usize, rgba: &[u8]) -> Vec<u8> {
    use std::io::Write as _;
    let mut rows = Vec::new();
    for row in rgba.chunks(side * 4) {
        rows.push(0);
        rows.extend_from_slice(row);
    }
    let mut zlib = flate2::write::ZlibEncoder::new(Vec::new(), flate2::Compression::best());
    zlib.write_all(&rows).unwrap();
    let side = u32::try_from(side).unwrap().to_be_bytes();
    let mut png = b"\x89PNG\r\n\x1a\n".to_vec();
    for (kind, data) in [
        (b"IHDR", [&side[..], &side, &[8, 6, 0, 0, 0]].concat()),
        (b"IDAT", zlib.finish().unwrap()),
        (b"IEND", Vec::new()),
    ] {
        let mut crc = flate2::Crc::new();
        crc.update(kind);
        crc.update(&data);
        png.extend(u32::try_from(data.len()).unwrap().to_be_bytes());
        png.extend(kind);
        png.extend(&data);
        png.extend(crc.sum().to_be_bytes());
    }
    png
}

/// The pixels of an 8-bit RGBA PNG as `(side, rgba)`, whatever filters an
/// optimiser chose, with every fully transparent pixel as zeroes. `None` for
/// anything else, which the check then reports as a mismatch.
fn decode_png(png: &[u8]) -> Option<(usize, usize, Vec<u8>)> {
    use std::io::Read as _;
    let mut chunks = png.strip_prefix(b"\x89PNG\r\n\x1a\n")?;
    let (mut width, mut height, mut compressed) = (0, 0, Vec::new());
    while let Some(len) = chunks.get(..4) {
        let len = u32::from_be_bytes(len.try_into().ok()?) as usize;
        let data = chunks.get(8..8 + len)?;
        match chunks.get(4..8)? {
            b"IHDR" if data.get(8..)? == [8, 6, 0, 0, 0] => {
                width = u32::from_be_bytes(data[..4].try_into().ok()?) as usize;
                height = u32::from_be_bytes(data[4..8].try_into().ok()?) as usize;
            }
            b"IHDR" => return None,
            b"IDAT" => compressed.extend_from_slice(data),
            _ => {}
        }
        chunks = chunks.get(12 + len..)?;
    }
    let mut rows = Vec::new();
    flate2::read::ZlibDecoder::new(&compressed[..])
        .read_to_end(&mut rows)
        .ok()?;
    let stride = width * 4;
    let mut rgba = vec![0u8; stride * height];
    for y in 0..height {
        let row = rows.get(y * (stride + 1)..(y + 1) * (stride + 1))?;
        for i in 0..stride {
            let at = y * stride + i;
            let left = if i >= 4 { rgba[at - 4] } else { 0 };
            let up = if y > 0 { rgba[at - stride] } else { 0 };
            let corner = if y > 0 && i >= 4 {
                rgba[at - stride - 4]
            } else {
                0
            };
            let predicted = match row[0] {
                0 => 0,
                1 => left,
                2 => up,
                3 => ((u16::from(left) + u16::from(up)) / 2) as u8,
                4 => {
                    let estimate = i16::from(left) + i16::from(up) - i16::from(corner);
                    let [a, b, c] = [left, up, corner].map(|v| (estimate - i16::from(v)).abs());
                    if a <= b && a <= c {
                        left
                    } else if b <= c {
                        up
                    } else {
                        corner
                    }
                }
                _ => return None,
            };
            rgba[at] = row[1 + i].wrapping_add(predicted);
        }
    }
    for pixel in rgba.chunks_mut(4).filter(|pixel| pixel[3] == 0) {
        pixel.fill(0);
    }
    Some((width, height, rgba))
}

/// The browser tab and the terminal show the same drawing: the committed
/// favicon and the PNG icons are generated from the sprite.
#[test]
fn favicon_is_drawn_from_the_sprite() {
    // Read at run time: env! would put this checkout's path in the cache key.
    let Some(manifest_dir) = std::env::var_os("CARGO_MANIFEST_DIR") else {
        return;
    };
    let public = std::path::Path::new(&manifest_dir).join("../../docs/public");
    // A packaged crate carries no docs tree to compare with.
    if !public.is_dir() {
        return;
    }
    let svg = favicon_svg();
    let write =
        std::env::var_os("TUIST_CARGO_CACHE_WRITE_FAVICON").is_some_and(|value| value == "1");
    if write {
        std::fs::write(public.join("favicon.svg"), &svg).unwrap();
    }
    let hint = "does not match the sprite's key pose; run this test with \
                TUIST_CARGO_CACHE_WRITE_FAVICON=1 to regenerate the favicon and icons";
    // A Windows checkout may convert line endings.
    let committed = std::fs::read_to_string(public.join("favicon.svg"))
        .unwrap_or_default()
        .replace("\r\n", "\n");
    assert!(committed == svg, "docs/public/favicon.svg {hint}\n\n{svg}");
    for (name, side, scale, backdrop) in PNG_ICONS {
        let rgba = icon_rgba(side, scale, backdrop);
        if write {
            std::fs::write(public.join(name), encode_png(side, &rgba)).unwrap();
        }
        let committed = std::fs::read(public.join(name)).unwrap_or_default();
        assert!(
            decode_png(&committed) == Some((side, side, rgba)),
            "docs/public/{name} {hint}"
        );
    }
}
