package ent;

import js.Browser;
import h2d.Anim;
import hxd.Key;

enum State {
	Idle;
	Death;
	FadeIn;
	FadeOut;
	Left;
	Right;
	Up;
	Down;
}

class Bobby {
	public static var game:Main;

	public var faded_out:Bool = false;
	public var dead:Bool = false;

	var xp:Int;
	var yp:Int;
	var moving_target:{xp:Int, yp:Int};
	var state:State;
	var next_state:State;
	var last_action_time:Float;

	public var sprite:Anim;

	// hud
	var carrot_count:Int = 0;
	var egg_count:Int = 0;
	var key_gray:Int = 0;
	var key_yellow:Int = 0;
	var key_red:Int = 0;

	public function new(xp:Int, yp:Int, start_time:Float) {
		this.xp = xp;
		this.yp = yp;
		this.state = FadeIn;
		this.last_action_time = start_time;

		sprite = new h2d.Anim([for (i in 0...9) game.bobby_fade.sub((9 - i) * 36, 0, 36, 50)], 30);
		sprite.loop = false;
		sprite.x = 32 * (xp + 0.5) - 18;
		sprite.y = 32 * (yp + 0.5) - (50 - 16);
		game.world.add(sprite, Main.LAYER_PLAYER);
	}

	public function remove() {
		sprite.remove();
	}

	function isFinished() {
		if (game.carrotTotal > 0) {
			return carrot_count == game.carrotTotal;
		} else {
			return egg_count == game.eggTotal;
		}
	}

	public function update(dt:Float) {
		if (state != Death && state != FadeIn && state != FadeOut && next_state != Death && next_state != FadeOut) {
			if (Key.isDown(Key.LEFT) || Key.isDown(Key.A)) {
				next_state = Left;
			} else if (Key.isDown(Key.RIGHT) || Key.isDown(Key.D)) {
				next_state = Right;
			} else if (Key.isDown(Key.UP) || Key.isDown(Key.W)) {
				next_state = Up;
			} else if (Key.isDown(Key.DOWN) || Key.isDown(Key.S)) {
				next_state = Down;
			}
		}
		if (hxd.Timer.lastTimeStamp - last_action_time >= 4 && state != Idle) {
			state = Idle;
			sprite.play([for (i in 0...3) game.bobby_idle.sub(i * 36, 0, 36, 50)]);
			sprite.loop = true;
		}
		switch (state) {
			case Death:
				if (sprite.currentFrame >= sprite.frames.length) {
					Browser.console.log("dead");
					dead = true;
				} else if (sprite.currentFrame >= sprite.frames.length - 1) {
					sprite.speed = 2;
				}
			case FadeIn:
				if (sprite.currentFrame >= sprite.frames.length) {
					state = Down;
					sprite.play([game.bobby_down.sub(7 * 36, 0, 36, 50)]);
				}
			case FadeOut:
				if (sprite.currentFrame >= sprite.frames.length) {
					faded_out = true;
				}
			default:
		}

		// Handle next state
		if (next_state != null && moving_target == null) {
			switch (next_state) {
				case Left if (xp > 0):
					moving_target = {xp: xp - 1, yp: yp};
					state = Left;
				case Right if (xp < 15):
					moving_target = {xp: xp + 1, yp: yp};
					state = Right;
				case Up if (yp > 0):
					moving_target = {xp: xp, yp: yp - 1};
					state = Up;
				case Down if (yp < 15):
					moving_target = {xp: xp, yp: yp + 1};
					state = Down;
				default:
			}
			next_state = null;

			if (moving_target != null) {
				last_action_time = hxd.Timer.lastTimeStamp;
				var old_item = game.levelData.get(xp + yp * 16);
				var new_item = game.levelData.get(moving_target.xp + moving_target.yp * 16);
				if (new_item < 18 // lock
					|| (new_item == 33 && key_gray == 0)
					|| (new_item == 35 && key_yellow == 0)
					|| (new_item == 37 && key_red == 0) // stop by sibling item
					|| (new_item == 24 && (state == Right || state == Down))
					|| (new_item == 25 && (state == Left || state == Down))
					|| (new_item == 26 && (state == Left || state == Up))
					|| (new_item == 27 && (state == Right || state == Up))
					|| ((new_item == 28 || new_item == 40 || new_item == 41) && (state == Up || state == Down))
					|| ((new_item == 29 || new_item == 42 || new_item == 43) && (state == Left || state == Right)) // stop by flow
					|| (new_item == 40 && state == Right)
					|| (new_item == 41 && state == Left)
					|| (new_item == 42 && state == Down)
					|| (new_item == 43 && state == Up) // egg
					|| (new_item == 46) // stop by current item
					|| (old_item == 24 && (state == Left || state == Up))
					|| (old_item == 25 && (state == Right || state == Up))
					|| (old_item == 26 && (state == Right || state == Down))
					|| (old_item == 27 && (state == Left || state == Down))
					|| ((old_item == 28 || old_item == 40 || old_item == 41) && (state == Up || state == Down))
					|| ((old_item == 29 || old_item == 42 || old_item == 43) && (state == Left || state == Right))
					|| (old_item == 40 && state == Right)
					|| (old_item == 41 && state == Left)
					|| (old_item == 42 && state == Down)
					|| (old_item == 43 && state == Up)) {
					moving_target = null;
				} else {
					if (new_item == 31) {
						next_state = Death;
					}
					switch (state) {
						case Left:
							sprite.play([for (i in 0...8) game.bobby_left.sub(i * 36, 0, 36, 50)]);
							sprite.loop = true;
						case Right:
							sprite.play([for (i in 0...8) game.bobby_right.sub(i * 36, 0, 36, 50)]);
							sprite.loop = true;
						case Up:
							sprite.play([for (i in 0...8) game.bobby_up.sub(i * 36, 0, 36, 50)]);
							sprite.loop = true;
						case Down:
							sprite.play([for (i in 0...8) game.bobby_down.sub(i * 36, 0, 36, 50)]);
							sprite.loop = true;
						default:
					}
				}
			}
		}

		var old_sprx = sprite.x;
		var old_spry = sprite.y;
		// Handle moving
		if (moving_target != null && next_state == Death && sprite.currentFrame >= 4) {
			state = Death;
			sprite.play([for (i in 0...8) game.bobby_death.sub(i * 44, 0, 44, 54)]);
			var x = (moving_target.xp - xp) / 2 + xp;
			var y = (moving_target.yp - yp) / 2 + yp;
			sprite.x = 32 * (x + 0.5) - 44 / 2;
			sprite.y = 32 * (y + 0.5) - (54 - 32 / 2);
			sprite.speed = 10;
			sprite.loop = false;
			moving_target = null;
			next_state = null;
		} else if (moving_target != null) {
			var dp = 32 / 20;
			var target_x = 32 * (moving_target.xp + 0.5) - 18;
			var target_y = 32 * (moving_target.yp + 0.5) - (50 - 16);
			var old_xp = xp;
			var old_yp = yp;

			if (moving_target.xp > xp) {
				sprite.x += dp;
				if (sprite.x >= target_x) {
					sprite.x = target_x;
					xp = moving_target.xp;
					moving_target = null;
				}
			} else if (moving_target.xp < xp) {
				sprite.x -= dp;
				if (sprite.x <= target_x) {
					sprite.x = target_x;
					xp = moving_target.xp;
					moving_target = null;
				}
			} else if (moving_target.yp > yp) {
				sprite.y += dp;
				if (sprite.y >= target_y) {
					sprite.y = target_y;
					yp = moving_target.yp;
					moving_target = null;
				}
			} else if (moving_target.yp < yp) {
				sprite.y -= dp;
				if (sprite.y <= target_y) {
					sprite.y = target_y;
					yp = moving_target.yp;
					moving_target = null;
				}
			}

			if (moving_target == null) {
				switch (state) {
					case Left:
						sprite.play([game.bobby_left.sub(7 * 36, 0, 36, 50)]);
						sprite.loop = false;
					case Right:
						sprite.play([game.bobby_right.sub(7 * 36, 0, 36, 50)]);
						sprite.loop = false;
					case Up:
						sprite.play([game.bobby_up.sub(7 * 36, 0, 36, 50)]);
						sprite.loop = false;
					case Down:
						sprite.play([game.bobby_down.sub(7 * 36, 0, 36, 50)]);
						sprite.loop = false;
					default:
				}

				var old_pos = old_xp + old_yp * 16;
				var new_pos = xp + yp * 16;
				switch (game.levelData.get(old_pos)) {
					case 24:
						game.setItem(old_pos, 25);
					case 25:
						game.setItem(old_pos, 26);
					case 26:
						game.setItem(old_pos, 27);
					case 27:
						game.setItem(old_pos, 24);
					case 28:
						game.setItem(old_pos, 29);
					case 29:
						game.setItem(old_pos, 28);
					case 30:
						game.setItem(old_pos, 31);
					case 45:
						game.setItem(old_pos, 46);
						egg_count += 1;
						game.updateIndicator(Carrot(egg_count));
						if (egg_count == game.eggTotal) {
							game.updateEndItem();
						}
						Browser.console.log("new egg count", egg_count);
					default: // TODO
				}
				switch (game.levelData.get(new_pos)) {
					// get carrot
					case 19:
						game.setItem(new_pos, 20);
						carrot_count += 1;
						game.updateIndicator(Carrot(carrot_count));
						if (carrot_count == game.carrotTotal) {
							game.updateEndItem();
						}
						Browser.console.log("new carrot count", carrot_count);
					// red switch
					case 22:
						for (x in 0...16) {
							for (y in 0...16) {
								var pos = x + y * 16;
								switch game.levelData.get(pos) {
									// switch
									case 22: game.setItem(pos, 23);
									case 23: game.setItem(pos, 22);
									// right angle
									case 24: game.setItem(pos, 25);
									case 25: game.setItem(pos, 26);
									case 26: game.setItem(pos, 27);
									case 27: game.setItem(pos, 24);
									// line
									case 28: game.setItem(pos, 29);
									case 29: game.setItem(pos, 28);
									default: {}
								}
							}
						}
					// TODO: dead
					case 31:
					// gray lock
					case 32:
						game.setItem(new_pos, 18);
						key_gray += 1;
						game.updateIndicator(KeyGray(key_gray));
						Browser.console.log("add key gray", key_gray);
					case 33 if (key_gray > 0):
						game.setItem(new_pos, 18);
						key_gray -= 1;
						game.updateIndicator(KeyGray(key_gray));
						Browser.console.log("remove key gray", key_gray);
					// yellow lock
					case 34:
						game.setItem(new_pos, 18);
						key_yellow += 1;
						game.updateIndicator(KeyYellow(key_yellow));
						Browser.console.log("add key yellow", key_yellow);
					case 35 if (key_yellow > 0):
						game.setItem(new_pos, 18);
						key_yellow -= 1;
						game.updateIndicator(KeyYellow(key_yellow));
						Browser.console.log("remove key yellow", key_yellow);
					// red lock
					case 36:
						game.setItem(new_pos, 18);
						key_red += 1;
						game.updateIndicator(KeyRed(key_red));
						Browser.console.log("add key red", key_yellow);
					case 37 if (key_red > 0):
						game.setItem(new_pos, 18);
						key_red -= 1;
						game.updateIndicator(KeyRed(key_red));
						Browser.console.log("remove key red", key_yellow);
					// yellow switch
					case 38:
						for (x in 0...16) {
							for (y in 0...16) {
								var pos = x + y * 16;
								switch game.levelData.get(pos) {
									// switch
									case 38: game.setItem(pos, 39);
									case 39: game.setItem(pos, 38);
									// left / right
									case 40: game.setItem(pos, 41);
									case 41: game.setItem(pos, 40);
									// up / down
									case 42: game.setItem(pos, 43);
									case 43: game.setItem(pos, 42);
									default: {}
								}
							}
						}
					// flow
					case 40:
						next_state = Left;
					case 41:
						next_state = Right;
					case 42:
						next_state = Up;
					case 43:
						next_state = Down;
					case 44 if (isFinished()):
						state = FadeOut;
						next_state = null;
						sprite.play([for (i in 0...9) game.bobby_fade.sub(i * 36, 0, 36, 50)]);
						sprite.loop = false;
						hxd.Res.audio.cleared.play();
					default:
				}
			}
		}

		// change camera position
		if ((old_sprx != sprite.x || old_spry != sprite.y) && state != Death) {
			game.updateCamera(sprite.x, sprite.y);
		}
	}
}
