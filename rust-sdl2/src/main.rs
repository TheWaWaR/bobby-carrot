use std::env;
use std::fmt;
use std::thread::sleep;
use std::time::Duration;

use sdl2::{
    event::Event,
    image::LoadTexture,
    keyboard::{Keycode, Scancode},
    pixels::Color,
    rect::Rect,
    render::{BlendMode, Texture, TextureCreator},
};

const FRAMES: u64 = 60;
const FRAMES_PER_STEP: u32 = 2;
const WIDTH_POINTS: u32 = 16;
const HEIGHT_POINTS: u32 = 16;
const VIEW_WIDTH_POINTS: u32 = 10;
const VIEW_HEIGHT_POINTS: u32 = 12;

const MS_PER_FRAME: u64 = 1000 / FRAMES;
const WIDTH: u32 = 32 * WIDTH_POINTS;
const HEIGHT: u32 = 32 * HEIGHT_POINTS;
const VIEW_WIDTH: u32 = 32 * VIEW_WIDTH_POINTS;
const VIEW_HEIGHT: u32 = 32 * VIEW_HEIGHT_POINTS;
const WIDTH_POINTS_DELTA: u32 = WIDTH_POINTS - VIEW_WIDTH_POINTS;
const HEIGHT_POINTS_DELTA: u32 = HEIGHT_POINTS - VIEW_HEIGHT_POINTS;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut map = Map::Normal(1);
    let args = env::args().collect::<Vec<_>>();
    if args.len() > 1 {
        let arg = &args[1];
        let (type_str, num_str) = arg
            .split_once('-')
            .ok_or_else(|| format!("Invalid map: {arg}"))?;
        let num: u32 = num_str.parse()?;
        match type_str {
            "normal" => map = Map::Normal(num),
            "egg" => map = Map::Egg(num),
            _ => return Err(format!("Invalid map: {arg}").into()),
        }
    }
    let mut map_info_fresh = map.load_map_info()?;
    let mut map_info = map_info_fresh.clone();

    let context = sdl2::init()?;
    let video_subsystem = context.video()?;
    let timer = context.timer()?;

    #[cfg(target_os = "linux")]
    let scale = 2.0;
    #[cfg(not(target_os = "linux"))]
    let scale = 1.0;

    let mut show_help = false;
    let mut full_view = false;
    let window = video_subsystem
        .window(
            format!("Bobby Carrot ({})", map).as_str(),
            (VIEW_WIDTH as f32 * scale) as u32,
            (VIEW_HEIGHT as f32 * scale) as u32,
        )
        .build()?;
    let mut canvas = window.into_canvas().present_vsync().build()?;
    canvas.set_scale(scale, scale)?;
    canvas.set_blend_mode(BlendMode::Blend);
    let texture_creator = canvas.texture_creator();
    let mut event_pump = context.event_pump()?;

    let mut frame: u32 = 0;
    let assets = Assets::load_all(&texture_creator)?;
    let mut bobby = Bobby::new(frame, timer.ticks(), map_info.coord_start);

    'running: loop {
        let now_ms = timer.ticks();
        for event in event_pump.poll_iter() {
            match event {
                Event::Quit { .. }
                | Event::KeyDown {
                    keycode: Some(Keycode::Q),
                    ..
                } => break 'running,
                Event::KeyDown {
                    keycode: Some(code),
                    ..
                } => {
                    if code != Keycode::H && code != Keycode::F1 {
                        show_help = false;
                    }
                    match code {
                        Keycode::R => {
                            map_info = map_info_fresh.clone();
                            bobby = Bobby::new(frame, now_ms, map_info.coord_start);
                        }
                        Keycode::N => {
                            map = map.next();
                            canvas
                                .window_mut()
                                .set_title(format!("Bobby Carrot ({})", map).as_str())?;
                            map_info_fresh = map.load_map_info()?;
                            map_info = map_info_fresh.clone();
                            bobby = Bobby::new(frame, now_ms, map_info.coord_start);
                        }
                        Keycode::P => {
                            map = map.previous();
                            canvas
                                .window_mut()
                                .set_title(format!("Bobby Carrot ({})", map).as_str())?;
                            map_info_fresh = map.load_map_info()?;
                            map_info = map_info_fresh.clone();
                            bobby = Bobby::new(frame, now_ms, map_info.coord_start);
                        }
                        Keycode::F => {
                            full_view = !full_view;
                            if full_view {
                                canvas.window_mut().set_size(WIDTH, HEIGHT)?;
                            } else {
                                canvas.window_mut().set_size(VIEW_WIDTH, VIEW_HEIGHT)?;
                            }
                        }
                        Keycode::H | Keycode::F1 => {
                            show_help = !show_help;
                        }
                        _ => {}
                    }
                }
                _ => {}
            }
        }
        let keyboard = event_pump.keyboard_state();
        let is_pressed = |code| keyboard.is_scancode_pressed(code);
        let state_opt = if is_pressed(Scancode::Left) || is_pressed(Scancode::A) {
            Some(State::Left)
        } else if is_pressed(Scancode::Right) || is_pressed(Scancode::D) {
            Some(State::Right)
        } else if is_pressed(Scancode::Up) || is_pressed(Scancode::W) {
            Some(State::Up)
        } else if is_pressed(Scancode::Down) || is_pressed(Scancode::S) {
            Some(State::Down)
        } else {
            None
        };
        if let Some(state) = state_opt {
            bobby.last_action_time = now_ms;
            if !bobby.is_walking() {
                bobby.update_state(state, frame, &map_info.data);
            } else {
                bobby.update_next_state(state, frame);
            }
        }

        // Finished and hit the end position
        if bobby.dead {
            map_info_fresh = map.load_map_info()?;
            map_info = map_info_fresh.clone();
            bobby = Bobby::new(frame, now_ms, map_info.coord_start);
        } else if bobby.is_finished(&map_info)
            && map_info.data[(bobby.coord_src.0 + bobby.coord_src.1 * 16) as usize] == 44
        {
            if bobby.faded_out {
                map = map.next();
                canvas
                    .window_mut()
                    .set_title(format!("Bobby Carrot ({})", map).as_str())?;
                map_info_fresh = map.load_map_info()?;
                map_info = map_info_fresh.clone();
                bobby = Bobby::new(frame, now_ms, map_info.coord_start);
            } else if bobby.state != State::FadeOut {
                bobby.start_frame = frame;
                bobby.state = State::FadeOut;
            }
        } else if now_ms - bobby.last_action_time >= 4000
            && !bobby.is_walking()
            && bobby.state != State::Idle
            && bobby.state != State::Death
            && bobby.state != State::FadeIn
            && bobby.state != State::FadeOut
            && bobby.next_state.is_none()
        {
            bobby.start_frame = frame;
            bobby.state = State::Idle;
        }

        let (bobby_src, bobby_dest) = bobby.update_texture_position(frame, &mut map_info.data);
        let bobby_texture = match bobby.state {
            State::Idle => &assets.bobby_idle_texture,
            State::Death => &assets.bobby_death_texture,
            State::FadeIn => &assets.bobby_fade_texture,
            State::FadeOut => &assets.bobby_fade_texture,
            State::Left => &assets.bobby_left_texture,
            State::Right => &assets.bobby_right_texture,
            State::Up => &assets.bobby_up_texture,
            State::Down => &assets.bobby_down_texture,
        };
        let finished = bobby.is_finished(&map_info);

        canvas.clear();

        for x in 0..WIDTH_POINTS {
            for y in 0..HEIGHT_POINTS {
                let item = map_info.data[x as usize + y as usize * 16] as i32;
                let texture = match item {
                    44 if finished => &assets.tile_finish_texture,
                    40 => &assets.tile_conveyor_left_texture,
                    41 => &assets.tile_conveyor_right_texture,
                    42 => &assets.tile_conveyor_up_texture,
                    43 => &assets.tile_conveyor_down_texture,
                    _ => &assets.tileset_texture,
                };
                let src = if (item == 44 && finished) || (40..44).contains(&item) {
                    Rect::new(32 * ((frame as i32 / (FRAMES as i32 / 10)) % 4), 0, 32, 32)
                } else {
                    Rect::new(32 * (item % 8), 32 * (item / 8), 32, 32)
                };
                canvas.copy_ex(
                    texture,
                    Some(src),
                    Some(Rect::new(32 * x as i32, 32 * y as i32, 32, 32)),
                    0.0,
                    None,
                    false,
                    false,
                )?;
            }
        }
        canvas.copy_ex(
            bobby_texture,
            Some(bobby_src),
            Some(bobby_dest),
            0.0,
            None,
            false,
            false,
        )?;

        // Set view port
        let (x_offset, x_right_offset, y_offset) = if full_view {
            (0, 0, 0)
        } else {
            let step = (frame - bobby.start_frame) as i32;
            let x0 = bobby.coord_src.0 as i32 * 32;
            let y0 = bobby.coord_src.1 as i32 * 32;
            let x1 = bobby.coord_dest.0 as i32 * 32;
            let y1 = bobby.coord_dest.1 as i32 * 32;
            let mut x = if bobby.state == State::Death {
                // death happened at 6/8 of walking
                (x1 - x0) * 6 / 8 + x0 - (VIEW_WIDTH_POINTS as i32 / 2) * 32
            } else {
                (x1 - x0) * step / (8 * FRAMES_PER_STEP as i32) + x0
                    - (VIEW_WIDTH_POINTS as i32 / 2) * 32
            };
            let mut y = if bobby.state == State::Death {
                // death happened at 6/8 of walking
                (y1 - y0) * 6 / 8 + y0 - (VIEW_HEIGHT_POINTS as i32 / 2) * 32
            } else {
                (y1 - y0) * step / (8 * FRAMES_PER_STEP as i32) + y0
                    - (VIEW_HEIGHT_POINTS as i32 / 2) * 32
            };
            x += 16;
            y += 16;
            if x < 0 {
                x = 0;
            }
            if x > WIDTH_POINTS_DELTA as i32 * 32 {
                x = WIDTH_POINTS_DELTA as i32 * 32;
            }
            if y < 0 {
                y = 0;
            }
            if y > HEIGHT_POINTS_DELTA as i32 * 32 {
                y = HEIGHT_POINTS_DELTA as i32 * 32;
            }
            canvas.set_viewport(Rect::new(
                -x,
                -y,
                VIEW_WIDTH + x as u32,
                VIEW_HEIGHT + y as u32,
            ));
            (x, 32 * WIDTH_POINTS_DELTA as i32 - x, y)
        };

        // Indicator
        let (icon_width, num_left) = if map_info.carrot_total > 0 {
            canvas.copy_ex(
                &assets.hud_texture,
                Some(Rect::new(0, 0, 46, 44)),
                Some(Rect::new(
                    32 * 16 - (46 + 4) - x_right_offset,
                    4 + y_offset,
                    46,
                    44,
                )),
                0.0,
                None,
                false,
                false,
            )?;
            (46, map_info.carrot_total - bobby.carrot_count)
        } else {
            canvas.copy_ex(
                &assets.hud_texture,
                Some(Rect::new(46, 0, 34, 44)),
                Some(Rect::new(
                    32 * 16 - (34 + 4) - x_right_offset,
                    4 + y_offset,
                    34,
                    44,
                )),
                0.0,
                None,
                false,
                false,
            )?;
            (34, map_info.egg_total - bobby.egg_count)
        };
        let num_10 = num_left as i32 / 10;
        let num_01 = num_left as i32 % 10;
        canvas.copy_ex(
            &assets.numbers_texture,
            Some(Rect::new(num_01 * 12, 0, 12, 18)),
            Some(Rect::new(
                32 * 16 - (icon_width + 4) - 2 - 12 - x_right_offset,
                4 + 14 + y_offset,
                12,
                18,
            )),
            0.0,
            None,
            false,
            false,
        )?;
        canvas.copy_ex(
            &assets.numbers_texture,
            Some(Rect::new(num_10 * 12, 0, 12, 18)),
            Some(Rect::new(
                32 * 16 - (icon_width + 4) - 2 - 12 * 2 - 1 - x_right_offset,
                4 + 14 + y_offset,
                12,
                18,
            )),
            0.0,
            None,
            false,
            false,
        )?;

        // Key
        let mut keys = Vec::new();
        for _ in 0..bobby.key_gray {
            keys.push((122, keys.len() as i32));
        }
        for _ in 0..bobby.key_yellow {
            keys.push((122 + 22, keys.len() as i32));
        }
        for _ in 0..bobby.key_red {
            keys.push((122 + 22 + 22, keys.len() as i32));
        }
        for (offset, count) in keys {
            canvas.copy_ex(
                &assets.hud_texture,
                Some(Rect::new(offset, 0, 22, 44)),
                Some(Rect::new(
                    32 * 16 - (22 + 4) - count * 22 - x_right_offset,
                    4 + 44 + 2 + y_offset,
                    22,
                    44,
                )),
                0.0,
                None,
                false,
                false,
            )?;
        }

        // time passed
        let passed_secs = ((now_ms - bobby.start_time) / 1000) as i32;
        let mut minutes = passed_secs / 60;
        let mut seconds = passed_secs % 60;
        if minutes > 99 {
            minutes = 99;
            seconds = 99;
        }
        for (idx, offset) in [minutes / 10, minutes % 10, 10, seconds / 10, seconds % 10]
            .into_iter()
            .enumerate()
        {
            canvas.copy_ex(
                &assets.numbers_texture,
                Some(Rect::new(offset * 12, 0, 12, 18)),
                Some(Rect::new(
                    4 + 12 * idx as i32 + x_offset,
                    4 + y_offset,
                    12,
                    18,
                )),
                0.0,
                None,
                false,
                false,
            )?;
        }

        // Show help page
        if show_help {
            canvas.set_draw_color(Color::RGBA(0, 0, 0, 200));
            canvas.fill_rect(Rect::new(
                (32 * 16 - x_offset - x_right_offset - 158) / 2 + x_offset,
                32 * 3 - (160 - 142) / 2 + y_offset,
                158,
                160,
            ))?;
            canvas.copy_ex(
                &assets.help_texture,
                Some(Rect::new(0, 0, 133, 142)),
                Some(Rect::new(
                    (32 * 16 - x_offset - x_right_offset - 133) / 2 + x_offset,
                    32 * 3 + y_offset,
                    133,
                    142,
                )),
                0.0,
                None,
                false,
                false,
            )?;
        }

        canvas.present();

        frame += 1;
        sleep(Duration::from_millis(MS_PER_FRAME));
    }

    Ok(())
}

struct Assets<'a> {
    bobby_idle_texture: Texture<'a>,
    bobby_death_texture: Texture<'a>,
    bobby_fade_texture: Texture<'a>,
    bobby_left_texture: Texture<'a>,
    bobby_right_texture: Texture<'a>,
    bobby_up_texture: Texture<'a>,
    bobby_down_texture: Texture<'a>,
    tile_conveyor_left_texture: Texture<'a>,
    tile_conveyor_right_texture: Texture<'a>,
    tile_conveyor_up_texture: Texture<'a>,
    tile_conveyor_down_texture: Texture<'a>,
    tileset_texture: Texture<'a>,
    tile_finish_texture: Texture<'a>,
    hud_texture: Texture<'a>,
    numbers_texture: Texture<'a>,
    help_texture: Texture<'a>,
}

impl<'a> Assets<'a> {
    pub fn load_all<T>(
        texture_creator: &'a TextureCreator<T>,
    ) -> Result<Assets<'a>, Box<dyn std::error::Error>> {
        let bobby_idle_texture =
            texture_creator.load_texture_bytes(include_bytes!("assets/image/bobby_idle.png"))?;
        let bobby_death_texture =
            texture_creator.load_texture_bytes(include_bytes!("assets/image/bobby_death.png"))?;
        let bobby_fade_texture =
            texture_creator.load_texture_bytes(include_bytes!("assets/image/bobby_fade.png"))?;
        let bobby_left_texture =
            texture_creator.load_texture_bytes(include_bytes!("assets/image/bobby_left.png"))?;
        let bobby_right_texture =
            texture_creator.load_texture_bytes(include_bytes!("assets/image/bobby_right.png"))?;
        let bobby_up_texture =
            texture_creator.load_texture_bytes(include_bytes!("assets/image/bobby_up.png"))?;
        let bobby_down_texture =
            texture_creator.load_texture_bytes(include_bytes!("assets/image/bobby_down.png"))?;

        let tile_conveyor_left_texture = texture_creator
            .load_texture_bytes(include_bytes!("assets/image/tile_conveyor_left.png"))?;
        let tile_conveyor_right_texture = texture_creator
            .load_texture_bytes(include_bytes!("assets/image/tile_conveyor_right.png"))?;
        let tile_conveyor_up_texture = texture_creator
            .load_texture_bytes(include_bytes!("assets/image/tile_conveyor_up.png"))?;
        let tile_conveyor_down_texture = texture_creator
            .load_texture_bytes(include_bytes!("assets/image/tile_conveyor_down.png"))?;
        let tileset_texture =
            texture_creator.load_texture_bytes(include_bytes!("assets/image/tileset.png"))?;
        let tile_finish_texture =
            texture_creator.load_texture_bytes(include_bytes!("assets/image/tile_finish.png"))?;
        let hud_texture =
            texture_creator.load_texture_bytes(include_bytes!("assets/image/hud.png"))?;
        let numbers_texture =
            texture_creator.load_texture_bytes(include_bytes!("assets/image/numbers.png"))?;
        let help_texture =
            texture_creator.load_texture_bytes(include_bytes!("assets/image/help.png"))?;
        Ok(Assets {
            bobby_idle_texture,
            bobby_death_texture,
            bobby_fade_texture,
            bobby_left_texture,
            bobby_right_texture,
            bobby_up_texture,
            bobby_down_texture,
            tile_conveyor_left_texture,
            tile_conveyor_right_texture,
            tile_conveyor_up_texture,
            tile_conveyor_down_texture,
            tileset_texture,
            tile_finish_texture,
            hud_texture,
            numbers_texture,
            help_texture,
        })
    }
}

#[derive(Debug, Clone, Copy)]
enum Map {
    Normal(u32),
    Egg(u32),
}

#[derive(Clone)]
struct MapInfo {
    data: Vec<u8>,
    coord_start: (u32, u32),
    carrot_total: usize,
    egg_total: usize,
}

impl fmt::Display for Map {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match self {
            Map::Normal(n) => write!(f, "Normal-{:02}", n),
            Map::Egg(n) => write!(f, "Egg-{:02}", n),
        }
    }
}

impl Map {
    fn load_map_info(&self) -> Result<MapInfo, Box<dyn std::error::Error>> {
        let data = match self {
            Map::Normal(1) => include_bytes!("assets/level/normal01.blm"),
            Map::Normal(2) => include_bytes!("assets/level/normal02.blm"),
            Map::Normal(3) => include_bytes!("assets/level/normal03.blm"),
            Map::Normal(4) => include_bytes!("assets/level/normal04.blm"),
            Map::Normal(5) => include_bytes!("assets/level/normal05.blm"),
            Map::Normal(6) => include_bytes!("assets/level/normal06.blm"),
            Map::Normal(7) => include_bytes!("assets/level/normal07.blm"),
            Map::Normal(8) => include_bytes!("assets/level/normal08.blm"),
            Map::Normal(9) => include_bytes!("assets/level/normal09.blm"),
            Map::Normal(10) => include_bytes!("assets/level/normal10.blm"),
            Map::Normal(11) => include_bytes!("assets/level/normal11.blm"),
            Map::Normal(12) => include_bytes!("assets/level/normal12.blm"),
            Map::Normal(13) => include_bytes!("assets/level/normal13.blm"),
            Map::Normal(14) => include_bytes!("assets/level/normal14.blm"),
            Map::Normal(15) => include_bytes!("assets/level/normal15.blm"),
            Map::Normal(16) => include_bytes!("assets/level/normal16.blm"),
            Map::Normal(17) => include_bytes!("assets/level/normal17.blm"),
            Map::Normal(18) => include_bytes!("assets/level/normal18.blm"),
            Map::Normal(19) => include_bytes!("assets/level/normal19.blm"),
            Map::Normal(20) => include_bytes!("assets/level/normal20.blm"),
            Map::Normal(21) => include_bytes!("assets/level/normal21.blm"),
            Map::Normal(22) => include_bytes!("assets/level/normal22.blm"),
            Map::Normal(23) => include_bytes!("assets/level/normal23.blm"),
            Map::Normal(24) => include_bytes!("assets/level/normal24.blm"),
            Map::Normal(25) => include_bytes!("assets/level/normal25.blm"),
            Map::Normal(26) => include_bytes!("assets/level/normal26.blm"),
            Map::Normal(27) => include_bytes!("assets/level/normal27.blm"),
            Map::Normal(28) => include_bytes!("assets/level/normal28.blm"),
            Map::Normal(29) => include_bytes!("assets/level/normal29.blm"),
            Map::Normal(30) => include_bytes!("assets/level/normal30.blm"),
            Map::Normal(level) => return Err(format!("Invalid normal level: {}", level).into()),
            Map::Egg(1) => include_bytes!("assets/level/egg01.blm"),
            Map::Egg(2) => include_bytes!("assets/level/egg02.blm"),
            Map::Egg(3) => include_bytes!("assets/level/egg03.blm"),
            Map::Egg(4) => include_bytes!("assets/level/egg04.blm"),
            Map::Egg(5) => include_bytes!("assets/level/egg05.blm"),
            Map::Egg(6) => include_bytes!("assets/level/egg06.blm"),
            Map::Egg(7) => include_bytes!("assets/level/egg07.blm"),
            Map::Egg(8) => include_bytes!("assets/level/egg08.blm"),
            Map::Egg(9) => include_bytes!("assets/level/egg09.blm"),
            Map::Egg(10) => include_bytes!("assets/level/egg10.blm"),
            Map::Egg(11) => include_bytes!("assets/level/egg11.blm"),
            Map::Egg(12) => include_bytes!("assets/level/egg12.blm"),
            Map::Egg(13) => include_bytes!("assets/level/egg13.blm"),
            Map::Egg(14) => include_bytes!("assets/level/egg14.blm"),
            Map::Egg(15) => include_bytes!("assets/level/egg15.blm"),
            Map::Egg(16) => include_bytes!("assets/level/egg16.blm"),
            Map::Egg(17) => include_bytes!("assets/level/egg17.blm"),
            Map::Egg(18) => include_bytes!("assets/level/egg18.blm"),
            Map::Egg(19) => include_bytes!("assets/level/egg19.blm"),
            Map::Egg(20) => include_bytes!("assets/level/egg20.blm"),
            Map::Egg(level) => return Err(format!("Invalid egg level: {}", level).into()),
        };
        let data = data[4..].to_vec();
        let mut start_idx: u32 = 0;
        let mut carrot_total: usize = 0;
        let mut egg_total: usize = 0;
        for (idx, byte) in data.iter().enumerate() {
            match byte {
                19 => carrot_total += 1,
                45 => egg_total += 1,
                21 => start_idx = idx as u32,
                _ => {}
            }
        }
        Ok(MapInfo {
            data,
            coord_start: (start_idx % 16, start_idx / 16),
            carrot_total,
            egg_total,
        })
    }

    fn next(self) -> Map {
        match self {
            Map::Normal(n) if n < 30 => Map::Normal(n + 1),
            Map::Normal(n) if n >= 30 => Map::Egg(1),
            Map::Egg(n) if n < 20 => Map::Egg(n + 1),
            Map::Egg(n) if n >= 20 => Map::Normal(1),
            _ => Map::Normal(1),
        }
    }

    fn previous(self) -> Map {
        match self {
            Map::Normal(n) if n <= 1 => Map::Egg(20),
            Map::Normal(n) if n > 1 => Map::Normal(n - 1),
            Map::Egg(n) if n <= 1 => Map::Normal(30),
            Map::Egg(n) if n > 1 => Map::Egg(n - 1),
            _ => Map::Normal(1),
        }
    }
}

#[derive(Debug)]
struct Bobby {
    state: State,
    next_state: Option<State>,
    start_frame: u32,
    start_time: u32,
    last_action_time: u32,
    coord_src: (u32, u32),
    coord_dest: (u32, u32),
    // hud
    carrot_count: usize,
    egg_count: usize,
    key_gray: usize,
    key_yellow: usize,
    key_red: usize,
    faded_out: bool,
    dead: bool,
}

#[derive(Debug, Eq, PartialEq)]
enum State {
    Idle,
    Death,
    FadeIn,
    FadeOut,
    Left,
    Right,
    Up,
    Down,
}

impl Bobby {
    pub fn new(start_frame: u32, start_time: u32, coord_src: (u32, u32)) -> Bobby {
        Bobby {
            state: State::FadeIn,
            next_state: None,
            start_frame,
            start_time,
            last_action_time: start_time,
            coord_src,
            coord_dest: coord_src,
            // hud
            carrot_count: 0,
            egg_count: 0,
            key_gray: 0,
            key_yellow: 0,
            key_red: 0,
            faded_out: false,
            dead: false,
        }
    }

    fn update_texture_position(&mut self, frame: u32, map_data: &mut [u8]) -> (Rect, Rect) {
        let delta_frame = frame - self.start_frame;
        let is_walking = self.coord_src != self.coord_dest;
        let step = delta_frame / FRAMES_PER_STEP;
        // println!("frame: {frame}, step: {step}, bobby: {:?}", self);
        let (src, dest) = match self.state {
            State::Idle => {
                let step_idle = (step / 2) % 3;
                let src = Rect::new(36 * step_idle as i32, 0, 36, 50);
                let dest = Rect::new(
                    self.coord_src.0 as i32 * 32 + 16 - (36 / 2),
                    self.coord_src.1 as i32 * 32 + 16 - (50 - 32 / 2),
                    36,
                    50,
                );
                return (src, dest);
            }
            State::Death => {
                let mut step_death = step / 3;
                if step_death > 7 {
                    step_death = 7;
                }
                let src = Rect::new((step_death % 8) as i32 * 44, 0, 44, 54);
                let x0 = self.coord_src.0 as i32 * 32;
                let y0 = self.coord_src.1 as i32 * 32;
                let x1 = self.coord_dest.0 as i32 * 32;
                let y1 = self.coord_dest.1 as i32 * 32;
                let x = (x1 - x0) / 2 + x0;
                let y = (y1 - y0) / 2 + y0;
                let dest = Rect::new(x + 16 - (44 / 2), y + 16 - (54 - 32 / 2), 44, 54);
                if step / 3 >= 12 {
                    self.dead = true;
                }
                return (src, dest);
            }
            State::FadeIn => {
                let src = Rect::new((8 - step as i32) * 36, 0, 36, 50);
                let dest = Rect::new(
                    self.coord_src.0 as i32 * 32 + 16 - (36 / 2),
                    self.coord_src.1 as i32 * 32 + 16 - (50 - 32 / 2),
                    36,
                    50,
                );
                if step >= 8 {
                    self.start_frame = frame;
                    self.state = State::Down;
                }
                return (src, dest);
            }
            State::FadeOut => {
                let src = Rect::new(step as i32 * 36, 0, 36, 50);
                let dest = Rect::new(
                    self.coord_src.0 as i32 * 32 + 16 - (36 / 2),
                    self.coord_src.1 as i32 * 32 + 16 - (50 - 32 / 2),
                    36,
                    50,
                );
                if step >= 8 {
                    self.faded_out = true;
                }
                return (src, dest);
            }
            State::Left => {
                let (src_x, dest_x, dest_y) = if is_walking {
                    (
                        36 * ((step + 7) % 8) as i32,
                        (self.coord_src.0 as i32 * 8 - step as i32) * 32 / 8 + 16 - (36 / 2),
                        self.coord_src.1 as i32 * 32 + 16 - (50 - 32 / 2),
                    )
                } else {
                    (
                        36 * 7,
                        self.coord_src.0 as i32 * 32 + 16 - (36 / 2),
                        self.coord_src.1 as i32 * 32 + 16 - (50 - 32 / 2),
                    )
                };
                let src = Rect::new(src_x, 0, 36, 50);
                let dest = Rect::new(dest_x, dest_y, 36, 50);
                if is_walking {
                    assert_eq!(self.coord_src.0, self.coord_dest.0 + 1);
                    assert_eq!(self.coord_src.1, self.coord_dest.1);
                }
                (src, dest)
            }
            State::Right => {
                let (src_x, dest_x, dest_y) = if is_walking {
                    (
                        36 * ((step + 7) % 8) as i32,
                        (self.coord_src.0 as i32 * 8 + step as i32) * 32 / 8 + 16 - (36 / 2),
                        self.coord_src.1 as i32 * 32 + 16 - (50 - 32 / 2),
                    )
                } else {
                    (
                        36 * 7,
                        self.coord_src.0 as i32 * 32 + 16 - (36 / 2),
                        self.coord_src.1 as i32 * 32 + 16 - (50 - 32 / 2),
                    )
                };
                let src = Rect::new(src_x, 0, 36, 50);
                let dest = Rect::new(dest_x, dest_y, 36, 50);
                if is_walking {
                    assert_eq!(self.coord_src.0 + 1, self.coord_dest.0);
                    assert_eq!(self.coord_src.1, self.coord_dest.1);
                }
                (src, dest)
            }
            State::Up => {
                let (src_x, dest_x, dest_y) = if is_walking {
                    (
                        36 * ((step + 7) % 8) as i32,
                        self.coord_src.0 as i32 * 32 + 16 - (36 / 2),
                        (self.coord_src.1 as i32 * 8 - step as i32) * 32 / 8 + 16 - (50 - 32 / 2),
                    )
                } else {
                    (
                        36 * 7,
                        self.coord_src.0 as i32 * 32 + 16 - (36 / 2),
                        self.coord_src.1 as i32 * 32 + 16 - (50 - 32 / 2),
                    )
                };
                let src = Rect::new(src_x, 0, 36, 50);
                let dest = Rect::new(dest_x, dest_y, 36, 50);
                if is_walking {
                    assert_eq!(self.coord_src.0, self.coord_dest.0);
                    assert_eq!(self.coord_src.1, self.coord_dest.1 + 1);
                }
                (src, dest)
            }
            State::Down => {
                let (src_x, dest_x, dest_y) = if is_walking {
                    (
                        36 * ((step + 7) % 8) as i32,
                        self.coord_src.0 as i32 * 32 + 16 - (36 / 2),
                        (self.coord_src.1 as i32 * 8 + step as i32) * 32 / 8 + 16 - (50 - 32 / 2),
                    )
                } else {
                    (
                        36 * 7,
                        self.coord_src.0 as i32 * 32 + 16 - (36 / 2),
                        self.coord_src.1 as i32 * 32 + 16 - (50 - 32 / 2),
                    )
                };
                let src = Rect::new(src_x, 0, 36, 50);
                let dest = Rect::new(dest_x, dest_y, 36, 50);
                if is_walking {
                    assert_eq!(self.coord_src.0, self.coord_dest.0);
                    assert_eq!(self.coord_src.1 + 1, self.coord_dest.1);
                }
                (src, dest)
            }
        };

        if step == 6 && is_walking && self.next_state == Some(State::Death) {
            self.start_frame = frame;
            self.state = State::Death;
        } else if step == 8 && is_walking {
            let old_pos = (self.coord_src.0 + self.coord_src.1 * 16) as usize;
            let new_pos = (self.coord_dest.0 + self.coord_dest.1 * 16) as usize;
            match map_data[old_pos] {
                24 => map_data[old_pos] = 25,
                25 => map_data[old_pos] = 26,
                26 => map_data[old_pos] = 27,
                27 => map_data[old_pos] = 24,
                28 => map_data[old_pos] = 29,
                29 => map_data[old_pos] = 28,
                30 => map_data[old_pos] = 31,
                45 => {
                    map_data[old_pos] = 46;
                    self.egg_count += 1;
                }
                _ => {
                    // TODO
                }
            }
            match map_data[new_pos] {
                // get carrot
                19 => {
                    map_data[new_pos] = 20;
                    self.carrot_count += 1;
                }
                // red switch
                22 => {
                    for x in 0..WIDTH_POINTS {
                        for y in 0..HEIGHT_POINTS {
                            let pos = x as usize + y as usize * 16;
                            match map_data[pos] {
                                // switch
                                22 => map_data[pos] = 23,
                                23 => map_data[pos] = 22,
                                // right angle
                                24 => map_data[pos] = 25,
                                25 => map_data[pos] = 26,
                                26 => map_data[pos] = 27,
                                27 => map_data[pos] = 24,
                                // line
                                28 => map_data[pos] = 29,
                                29 => map_data[pos] = 28,
                                _ => {}
                            }
                        }
                    }
                }
                // TODO: dead
                31 => {}
                // gray lock
                32 => {
                    map_data[new_pos] = 18;
                    self.key_gray += 1;
                }
                33 if self.key_gray > 0 => {
                    map_data[new_pos] = 18;
                    self.key_gray -= 1;
                }
                // yellow lock
                34 => {
                    map_data[new_pos] = 18;
                    self.key_yellow += 1;
                }
                35 if self.key_yellow > 0 => {
                    map_data[new_pos] = 18;
                    self.key_yellow -= 1;
                }
                // red lock
                36 => {
                    map_data[new_pos] = 18;
                    self.key_red += 1;
                }
                37 if self.key_red > 0 => {
                    map_data[new_pos] = 18;
                    self.key_red -= 1;
                }
                // yellow switch
                38 => {
                    for x in 0..WIDTH_POINTS {
                        for y in 0..HEIGHT_POINTS {
                            let pos = x as usize + y as usize * 16;
                            match map_data[pos] {
                                // switch
                                38 => map_data[pos] = 39,
                                39 => map_data[pos] = 38,
                                // left / right
                                40 => map_data[pos] = 41,
                                41 => map_data[pos] = 40,
                                // up / down
                                42 => map_data[pos] = 43,
                                43 => map_data[pos] = 42,
                                _ => {}
                            }
                        }
                    }
                }
                // flow
                40 => self.next_state = Some(State::Left),
                41 => self.next_state = Some(State::Right),
                42 => self.next_state = Some(State::Up),
                43 => self.next_state = Some(State::Down),
                _ => {}
            }

            self.coord_src = self.coord_dest;
            self.start_frame = frame;
            if let Some(state) = self.next_state.take() {
                self.update_state(state, frame, map_data);
            }
        }
        (src, dest)
    }

    fn is_walking(&self) -> bool {
        self.coord_src != self.coord_dest
    }

    fn is_finished(&self, map_info: &MapInfo) -> bool {
        if map_info.carrot_total > 0 {
            self.carrot_count == map_info.carrot_total
        } else {
            self.egg_count == map_info.egg_total
        }
    }

    fn update_next_state(&mut self, state: State, frame: u32) {
        if (frame - self.start_frame) / FRAMES_PER_STEP > 3
            && self.next_state != Some(State::Idle)
            && self.next_state != Some(State::Death)
            && self.next_state != Some(State::FadeIn)
            && self.next_state != Some(State::FadeOut)
        {
            self.next_state = Some(state);
        }
    }

    fn update_state(&mut self, state: State, frame: u32, map_data: &[u8]) {
        // println!("new state: {:?}", state);
        self.start_frame = frame;
        self.state = state;
        self.update_dest(map_data);
    }

    fn update_dest(&mut self, map_data: &[u8]) {
        let old_dest = self.coord_dest;
        match self.state {
            State::Left => {
                if self.coord_dest.0 > 0 {
                    self.coord_dest.0 -= 1;
                }
            }
            State::Right => {
                if self.coord_dest.0 < WIDTH_POINTS - 1 {
                    self.coord_dest.0 += 1;
                }
            }
            State::Up => {
                if self.coord_dest.1 > 0 {
                    self.coord_dest.1 -= 1;
                }
            }
            State::Down => {
                if self.coord_dest.1 < HEIGHT_POINTS - 1 {
                    self.coord_dest.1 += 1;
                }
            }
            _ => {}
        }

        let old_pos = (self.coord_src.0 + self.coord_src.1 * 16) as usize;
        let new_pos = (self.coord_dest.0 + self.coord_dest.1 * 16) as usize;
        let old_item = map_data[old_pos];
        let new_item = map_data[new_pos];
        // The target position is forbidden
        if new_item < 18
            // lock
            || (new_item == 33 && self.key_gray == 0)
            || (new_item == 35 && self.key_yellow == 0)
            || (new_item == 37 && self.key_red == 0)
            // stop by sibling item
            || (new_item == 24 && (self.state == State::Right || self.state == State::Down))
            || (new_item == 25 && (self.state == State::Left || self.state == State::Down))
            || (new_item == 26 && (self.state == State::Left || self.state == State::Up))
            || (new_item == 27 && (self.state == State::Right || self.state == State::Up))
            || ((new_item == 28 || new_item == 40 || new_item == 41)
                && (self.state == State::Up || self.state == State::Down))
            || ((new_item == 29 || new_item == 42 || new_item == 43)
                && (self.state == State::Left || self.state == State::Right))
            // stop by flow
            || (new_item == 40 && self.state == State::Right)
            || (new_item == 41 && self.state == State::Left)
            || (new_item == 42 && self.state == State::Down)
            || (new_item == 43 && self.state == State::Up)
            // egg
            || (new_item == 46)
            // stop by current item
            || (old_item == 24 && (self.state == State::Left || self.state == State::Up))
            || (old_item == 25 && (self.state == State::Right || self.state == State::Up))
            || (old_item == 26 && (self.state == State::Right || self.state == State::Down))
            || (old_item == 27 && (self.state == State::Left || self.state == State::Down))
            || ((old_item == 28 || old_item == 40 || old_item == 41)
                && (self.state == State::Up || self.state == State::Down))
            || ((old_item == 29 || old_item == 42 || old_item == 43)
                && (self.state == State::Left || self.state == State::Right))
            || (old_item == 40 && self.state == State::Right)
            || (old_item == 41 && self.state == State::Left)
            || (old_item == 42 && self.state == State::Down)
            || (old_item == 43 && self.state == State::Up)
        {
            self.coord_dest = old_dest;
        } else if new_item == 31 {
            self.next_state = Some(State::Death);
        }
    }
}
