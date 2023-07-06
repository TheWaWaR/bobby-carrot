use sdl2::event::Event;
use sdl2::keyboard::Keycode;
use sdl2::rect::Point;
use sdl2::rect::Rect;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let context = sdl2::init()?;
    let video_subsystem = context.video()?;

    let window = video_subsystem.window("Bobby Carrot", 480, 720).build()?;
    let mut canvas = window.into_canvas().present_vsync().build()?;
    let mut event_pump = context.event_pump()?;

    'running: loop {
        for event in event_pump.poll_iter() {
            match event {
                Event::Quit { .. }
                | Event::KeyDown {
                    keycode: Some(Keycode::Escape),
                    ..
                } => {
                    break 'running;
                }
                _ => {}
            }
        }
        canvas.present();
    }

    Ok(())
}
