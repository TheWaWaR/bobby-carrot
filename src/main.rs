use std::env;
use std::fmt;
use std::fs;
use std::path::Path;
use std::thread::sleep;
use std::time::Duration;

use sdl2::{
    event::Event,
    image::LoadTexture,
    keyboard::Keycode,
    rect::Rect,
    render::{Texture, TextureCreator},
};

const FRAMES: u64 = 60;
const MS_PER_FRAME: u64 = 1000 / FRAMES;
const FRAMES_PER_STEP: u32 = 2;
const WIDTH_POINTS: u32 = 16;
const HEIGHT_POINTS: u32 = 16;
const WIDTH: u32 = 32 * WIDTH_POINTS;
const HEIGHT: u32 = 32 * HEIGHT_POINTS;

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

    let window = video_subsystem
        .window(format!("Bobby Carrot ({})", map).as_str(), WIDTH, HEIGHT)
        .build()?;
    let mut canvas = window.into_canvas().present_vsync().build()?;
    let texture_creator = canvas.texture_creator();
    let mut event_pump = context.event_pump()?;

    let assets = Assets::load_all(&texture_creator)?;
    let mut bobby = Bobby::new(0, (map_info.start_idx % 16, map_info.start_idx / 16));

    let mut frame: u32 = 0;
    'running: loop {
        for event in event_pump.poll_iter() {
            match event {
                Event::Quit { .. }
                | Event::KeyDown {
                    keycode: Some(Keycode::Escape | Keycode::Q),
                    ..
                } => break 'running,
                Event::KeyDown {
                    keycode: Some(code),
                    ..
                } => {
                    let state_opt = match code {
                        Keycode::Left => Some(State::Left),
                        Keycode::Right => Some(State::Right),
                        Keycode::Up => Some(State::Up),
                        Keycode::Down => Some(State::Down),
                        Keycode::R => {
                            map_info = map_info_fresh.clone();
                            bobby =
                                Bobby::new(0, (map_info.start_idx % 16, map_info.start_idx / 16));
                            None
                        }
                        Keycode::N => {
                            map = map.next();
                            canvas
                                .window_mut()
                                .set_title(format!("Bobby Carrot ({})", map).as_str())?;
                            map_info_fresh = map.load_map_info()?;
                            map_info = map_info_fresh.clone();
                            bobby =
                                Bobby::new(0, (map_info.start_idx % 16, map_info.start_idx / 16));
                            None
                        }
                        Keycode::P => {
                            map = map.previous();
                            canvas
                                .window_mut()
                                .set_title(format!("Bobby Carrot ({})", map).as_str())?;
                            map_info_fresh = map.load_map_info()?;
                            map_info = map_info_fresh.clone();
                            bobby =
                                Bobby::new(0, (map_info.start_idx % 16, map_info.start_idx / 16));
                            None
                        }
                        _ => None,
                    };
                    if let Some(state) = state_opt {
                        if !bobby.is_walking() {
                            bobby.update_state(state, frame, &map_info.data);
                        } else {
                            bobby.update_next_state(state, frame);
                        }
                    }
                }
                _ => {}
            }
        }

        // Finished and hit the end position
        if bobby.carrot_count == map_info.carrot_total
            && map_info.data[(bobby.coord_src.0 + bobby.coord_src.1 * 16) as usize] == 44
        {
            map = map.next();
            canvas
                .window_mut()
                .set_title(format!("Bobby Carrot ({})", map).as_str())?;
            map_info_fresh = map.load_map_info()?;
            map_info = map_info_fresh.clone();
            bobby = Bobby::new(0, (map_info.start_idx % 16, map_info.start_idx / 16));
        }

        let (bobby_src, bobby_dest) = bobby.update_texture_position(frame, &mut map_info.data);
        let bobby_texture = match bobby.state {
            State::Idle => &assets.bobby_idle_texture,
            State::Left => &assets.bobby_left_texture,
            State::Right => &assets.bobby_right_texture,
            State::Up => &assets.bobby_up_texture,
            State::Down => &assets.bobby_down_texture,
        };
        let finished = bobby.carrot_count == map_info.carrot_total;

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
                let src = if (item == 44 && finished) || (40..=43).contains(&item) {
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
}

impl<'a> Assets<'a> {
    pub fn load_all<T>(
        texture_creator: &'a TextureCreator<T>,
    ) -> Result<Assets<'a>, Box<dyn std::error::Error>> {
        let bobby_idle_texture =
            texture_creator.load_texture(Path::new("assets/image/bobby_idle.png"))?;
        let bobby_death_texture =
            texture_creator.load_texture(Path::new("assets/image/bobby_death.png"))?;
        let bobby_fade_texture =
            texture_creator.load_texture(Path::new("assets/image/bobby_fade.png"))?;
        let bobby_left_texture =
            texture_creator.load_texture(Path::new("assets/image/bobby_left.png"))?;
        let bobby_right_texture =
            texture_creator.load_texture(Path::new("assets/image/bobby_right.png"))?;
        let bobby_up_texture =
            texture_creator.load_texture(Path::new("assets/image/bobby_up.png"))?;
        let bobby_down_texture =
            texture_creator.load_texture(Path::new("assets/image/bobby_down.png"))?;

        let tile_conveyor_left_texture =
            texture_creator.load_texture(Path::new("assets/image/tile_conveyor_left.png"))?;
        let tile_conveyor_right_texture =
            texture_creator.load_texture(Path::new("assets/image/tile_conveyor_right.png"))?;
        let tile_conveyor_up_texture =
            texture_creator.load_texture(Path::new("assets/image/tile_conveyor_up.png"))?;
        let tile_conveyor_down_texture =
            texture_creator.load_texture(Path::new("assets/image/tile_conveyor_down.png"))?;
        let tileset_texture =
            texture_creator.load_texture(Path::new("assets/image/tileset.png"))?;
        let tile_finish_texture =
            texture_creator.load_texture(Path::new("assets/image/tile_finish.png"))?;
        let hud_texture = texture_creator.load_texture(Path::new("assets/image/hud.png"))?;
        let numbers_texture =
            texture_creator.load_texture(Path::new("assets/image/numbers.png"))?;
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
    start_idx: u32,
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
        let map_filename = match self {
            Map::Normal(n) => format!("normal{:02}.blm", n),
            Map::Egg(n) => format!("egg{:02}.blm", n),
        };
        let filename = format!("assets/level/{map_filename}");
        let data = fs::read(&filename)
            .map_err(|err| format!("load level file '{}' failed: {}", filename, err))?
            .split_off(4);
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
            start_idx,
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
    coord_src: (u32, u32),
    coord_dest: (u32, u32),
    // hud
    carrot_count: usize,
    egg_count: usize,
    key_gray: usize,
    key_yellow: usize,
    key_red: usize,
    view_mode: bool,
}

#[derive(Debug, Eq, PartialEq)]
enum State {
    Idle,
    Left,
    Right,
    Up,
    Down,
}

impl Bobby {
    pub fn new(start_frame: u32, coord_src: (u32, u32)) -> Bobby {
        Bobby {
            state: State::Down,
            next_state: None,
            start_frame,
            coord_src,
            coord_dest: coord_src,
            // hud
            carrot_count: 0,
            egg_count: 0,
            key_gray: 0,
            key_yellow: 0,
            key_red: 0,
            view_mode: false,
        }
    }

    fn update_texture_position(&mut self, frame: u32, map_data: &mut [u8]) -> (Rect, Rect) {
        let delta_frame = frame - self.start_frame;
        let is_walking = self.coord_src != self.coord_dest;
        let step = delta_frame / FRAMES_PER_STEP;
        // println!("frame: {frame}, step: {step}, bobby: {:?}", self);
        let (src, dest) = match self.state {
            State::Idle => {
                let step_idle = step % 3;
                let src = Rect::new(36 * step_idle as i32, 0, 36, 50);
                let dest = Rect::new(
                    self.coord_src.0 as i32 * 32 + 16 - (36 / 2),
                    self.coord_src.1 as i32 * 32 + 16 - (50 - 32 / 2),
                    36,
                    50,
                );
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

        if step == 8 && is_walking {
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

    fn update_next_state(&mut self, state: State, frame: u32) {
        if (frame - self.start_frame) / FRAMES_PER_STEP > 3 {
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
            || new_item == 31 // TODO: dead, remove this later
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
            // stop by current item
            || (old_item == 24 && (self.state == State::Left || self.state == State::Up))
            || (old_item == 25 && (self.state == State::Right || self.state == State::Up))
            || (old_item == 26 && (self.state == State::Right || self.state == State::Down))
            || (old_item == 27 && (self.state == State::Left || self.state == State::Down))
            || ((old_item == 28 || old_item == 40 || old_item == 41)
                && (self.state == State::Up || self.state == State::Down))
            || ((old_item == 29 || old_item == 42 || old_item == 43)
                && (self.state == State::Left || self.state == State::Right))
        {
            self.coord_dest = old_dest;
        }
    }
}
