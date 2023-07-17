import h2d.Bitmap;
import js.Browser;
import h2d.Anim;
import ent.Bobby;
import hxd.res.Prefab;
import haxe.io.Bytes;
import hxd.Key;

enum Indicator {
	Carrot(n:Int);
	Egg(n:Int);
	KeyGray(n:Int);
	KeyYellow(n:Int);
	KeyRed(n:Int);
	Time(t:Int);
}

enum IndicatorItem {
	Carrot;
	Egg;
	Number10;
	Number01;
	KeyGray;
	KeyYellow;
	KeyRed;
	TimeMinute10;
	TimeMinute01;
	TimeDelimiter;
	TimeSecond10;
	TimeSecond01;
}

class Main extends hxd.App {
	static var LW = 16;
	static var LH = 16;
	static var VW = 10;
	static var VH = 12;

	static var LAYER_SOIL = 0;
	public static var LAYER_ITEM = 1;
	public static var LAYER_PLAYER = 2;
	public static var LAYER_INDICATOR = 3;

	public var bobby_idle:h2d.Tile;
	public var bobby_death:h2d.Tile;
	public var bobby_fade:h2d.Tile;
	public var bobby_left:h2d.Tile;
	public var bobby_right:h2d.Tile;
	public var bobby_up:h2d.Tile;
	public var bobby_down:h2d.Tile;

	var tile_conveyor_left:h2d.Tile;
	var tile_conveyor_right:h2d.Tile;
	var tile_conveyor_up:h2d.Tile;
	var tile_conveyor_down:h2d.Tile;
	var tileset:h2d.Tile;
	var tile_finish:h2d.Tile;
	var hud:h2d.Tile;
	var numbers:h2d.Tile;
	var help:h2d.Tile;

	public var world:h2d.Layers;
	public var levelData:Bytes;
	public var carrotTotal:Int;
	public var eggTotal:Int;
	public var endItem:Int;

	var camera:h2d.Camera;
	var soilLayer:h2d.TileGroup;
	var items:Map<Int, Anim>;
	var indicators:Map<IndicatorItem, Bitmap>;
	var levels:Array<Bytes>;
	var currentLevel:Int;
	var startTime:Float;
	var lastSeconds:Int;
	var bobby:ent.Bobby;

	static var save = hxd.Save.load({level: 0});

	override function init() {
		Bobby.game = this;

		bobby_idle = hxd.Res.image.bobby_idle.toTile();
		bobby_death = hxd.Res.image.bobby_death.toTile();
		bobby_fade = hxd.Res.image.bobby_fade.toTile();
		bobby_left = hxd.Res.image.bobby_left.toTile();
		bobby_right = hxd.Res.image.bobby_right.toTile();
		bobby_up = hxd.Res.image.bobby_up.toTile();
		bobby_down = hxd.Res.image.bobby_down.toTile();
		tile_conveyor_left = hxd.Res.image.tile_conveyor_left.toTile();
		tile_conveyor_right = hxd.Res.image.tile_conveyor_right.toTile();
		tile_conveyor_up = hxd.Res.image.tile_conveyor_up.toTile();
		tile_conveyor_down = hxd.Res.image.tile_conveyor_down.toTile();
		tileset = hxd.Res.image.tileset.toTile();
		tile_finish = hxd.Res.image.tile_finish.toTile();
		hud = hxd.Res.image.hud.toTile();
		numbers = hxd.Res.image.numbers.toTile();
		help = hxd.Res.image.help.toTile();

		s2d.scaleMode = Stretch(VW * 32, VH * 32);

		camera = new h2d.Camera(s2d);
		camera.clipViewport = true;
		camera.setViewport(0, 0, VW * 32, VH * 32);
		camera.setPosition((LW - VW) * 32, (LH - VH) * 32);

		world = new h2d.Layers(s2d);
		soilLayer = new h2d.TileGroup(tileset);
		world.add(soilLayer, LAYER_SOIL);

		items = new Map();
		indicators = new Map();
		levelData = Bytes.alloc(256);
		currentLevel = save.level;
		levels = [];
		for (n in 1...31) {
			var nstr = n < 10 ? "0" + n : "" + n;
			levels.push(hxd.Res.load("level/normal" + nstr + ".blm").entry.getBytes());
		}
		for (n in 1...21) {
			var nstr = n < 10 ? "0" + n : "" + n;
			levels.push(hxd.Res.load("level/egg" + nstr + ".blm").entry.getBytes());
		}

		world.filter = new h2d.filter.Blur(0.3);
		world.filter.smooth = true;

		initLevel();
	}

	function initLevel() {
		var data = levels[currentLevel];
		if (data == null) {
			return;
		}
		levelData.blit(0, data, 4, 256);

		if (save.level != currentLevel) {
			save.level = currentLevel;
			hxd.Save.save(save);
		}

		if (bobby != null) {
			bobby.remove();
		}
		for (item in items) {
			item.remove();
		}
		items.clear();

		carrotTotal = 0;
		eggTotal = 0;
		startTime = hxd.Timer.lastTimeStamp;
		lastSeconds = Std.int(startTime);
		soilLayer.clear();
		for (x in 0...LW) {
			for (y in 0...LH) {
				var pos = x + y * 16;
				var item_type = levelData.get(pos);
				switch (item_type) {
					case 21:
						bobby = new Bobby(x, y, startTime);
					case 19:
						carrotTotal += 1;
					case 44:
						endItem = pos;
					case 45:
						eggTotal += 1;
					default:
				}

				var is_item = setItem(pos, item_type);
				if (!is_item) {
					var x_offset = 32 * (item_type % 8);
					var y_offset = 32 * (item_type >> 3);
					soilLayer.add(x * 32, y * 32, tileset.sub(x_offset, y_offset, 32, 32));
				}
			}
		}

		updateIndicator(Carrot(0));
		updateIndicator(Egg(0));
		updateIndicator(KeyGray(0));
		updateIndicator(KeyYellow(0));
		updateIndicator(KeyRed(0));
		updateIndicator(Time(0));
		updateCamera(bobby.sprite.x, bobby.sprite.y);
	}

	function setItemWith(pos:Int, item_type:Int, sprite:Anim) {
		var old_item = items.get(pos);
		if (old_item != null) {
			old_item.remove();
			items.remove(pos);
			levelData.set(pos, item_type);
		}
		sprite.x = (pos % 16) * 32;
		sprite.y = (pos >> 4) * 32;
		world.add(sprite, LAYER_ITEM);
		items.set(pos, sprite);
	}

	public function setItem(pos:Int, item_type:Int):Bool {
		var new_item = switch (item_type) {
			case 40:
				new Anim([for (i in 0...4) tile_conveyor_left.sub(i * 32, 0, 32, 32)]);
			case 41:
				new Anim([for (i in 0...4) tile_conveyor_right.sub(i * 32, 0, 32, 32)]);
			case 42:
				new Anim([for (i in 0...4) tile_conveyor_up.sub(i * 32, 0, 32, 32)]);
			case 43:
				new Anim([for (i in 0...4) tile_conveyor_down.sub(i * 32, 0, 32, 32)]);
			case _ if (item_type >= 18 && item_type != 21):
				var x_offset = 32 * (item_type % 8);
				var y_offset = 32 * (item_type >> 3);
				new Anim([tileset.sub(x_offset, y_offset, 32, 32)], 1);
			default:
				return false;
		}
		setItemWith(pos, item_type, new_item);
		return true;
	}

	public function updateEndItem() {
		var sprite = new Anim([for (i in 0...4) tile_finish.sub(i * 32, 0, 32, 32)]);
		setItemWith(endItem, 44, sprite);
	}

	function replaceIndicatorImage(key:IndicatorItem, value:Bitmap) {
		var old_value = indicators.get(key);
		if (old_value != null) {
			old_value.remove();
			indicators.remove(key);
		}
		if (value != null) {
			indicators.set(key, value);
			world.add(value, LAYER_INDICATOR);
		}
	}

	public function updateIndicator(target:Indicator) {
		switch (target) {
			case Carrot(n) if (carrotTotal > 0):
				n = carrotTotal - n;
				replaceIndicatorImage(Carrot, new Bitmap(hud.sub(0, 0, 46, 44)));
				replaceIndicatorImage(Egg, null);
				replaceIndicatorImage(Number10, new Bitmap(numbers.sub((Std.int(n / 10)) * 12, 0, 12, 18)));
				replaceIndicatorImage(Number01, new Bitmap(numbers.sub((n % 10) * 12, 0, 12, 18)));
			case Egg(n) if (eggTotal > 0):
				n = eggTotal - n;
				replaceIndicatorImage(Carrot, null);
				replaceIndicatorImage(Egg, new Bitmap(hud.sub(46, 0, 34, 44)));
				replaceIndicatorImage(Number10, new Bitmap(numbers.sub((Std.int(n / 10)) * 12, 0, 12, 18)));
				replaceIndicatorImage(Number01, new Bitmap(numbers.sub((n % 10) * 12, 0, 12, 18)));
			case KeyGray(n):
				var img = n > 0 ? new Bitmap(hud.sub(122, 0, 22, 44)) : null;
				replaceIndicatorImage(KeyGray, img);
			case KeyYellow(n):
				var img = n > 0 ? new Bitmap(hud.sub(122 + 22, 0, 22, 44)) : null;
				replaceIndicatorImage(KeyYellow, img);
			case KeyRed(n):
				var img = n > 0 ? new Bitmap(hud.sub(122 + 22 + 22, 0, 22, 44)) : null;
				replaceIndicatorImage(KeyRed, img);
			case Time(seconds):
				var m = Std.int(seconds / 60);
				var s = seconds % 60;
				// time overflow
				if (m > 99) {
					m = 99;
					s = 99;
				}
				replaceIndicatorImage(TimeMinute10, new Bitmap(numbers.sub((Std.int(m / 10)) * 12, 0, 12, 18)));
				replaceIndicatorImage(TimeMinute01, new Bitmap(numbers.sub((m % 10) * 12, 0, 12, 18)));
				replaceIndicatorImage(TimeDelimiter, new Bitmap(numbers.sub(10 * 12, 0, 12, 18)));
				replaceIndicatorImage(TimeSecond10, new Bitmap(numbers.sub((Std.int(s / 10)) * 12, 0, 12, 18)));
				replaceIndicatorImage(TimeSecond01, new Bitmap(numbers.sub((s % 10) * 12, 0, 12, 18)));
			default:
		}
		if (lastSeconds > Std.int(startTime)) {
			updateCamera(bobby.sprite.x, bobby.sprite.y);
		}
	}

	public function updateCamera(x:Float, y:Float) {
		var new_x = x - VW * 16 + 16;
		var new_y = y - VH * 16 + 16;
		if (new_x < 0) {
			new_x = 0;
		}
		if (new_y < 0) {
			new_y = 0;
		}
		if (new_x > (LW - VW) * 32) {
			new_x = (LW - VW) * 32;
		}
		if (new_y > (LH - VH) * 32) {
			new_y = (LH - VH) * 32;
		}
		camera.setPosition(new_x, new_y);

		// update indicator postions
		var x_right_offset = 32 * 16 - new_x - VW * 32;
		var x_offset = new_x;
		var y_offset = new_y;
		// icon
		var target_img = indicators.get(Carrot);
		var icon_width = 46;
		if (target_img == null) {
			target_img = indicators.get(Egg);
			icon_width = 34;
		}
		target_img.x = 32 * 16 - (icon_width + 4) - x_right_offset;
		target_img.y = 4 + y_offset;
		// number
		var num10_img = indicators.get(Number10);
		num10_img.x = 32 * 16 - (icon_width + 4) - 2 - 12 * 2 - 1 - x_right_offset;
		num10_img.y = 4 + 14 + y_offset;
		var num01_img = indicators.get(Number01);
		num01_img.x = 32 * 16 - (icon_width + 4) - 2 - 12 - x_right_offset;
		num01_img.y = 4 + 14 + y_offset;
		// key
		var key_count = 0;
		for (key_type in [KeyGray, KeyYellow, KeyRed]) {
			var img = indicators.get(key_type);
			if (img != null) {
				img.x = 32 * 16 - (22 + 4) - key_count * 22 - x_right_offset;
				img.y = 4 + 44 + 2 + y_offset;
				key_count += 1;
			}
		}
		// time
		for (idx => time_type in [TimeMinute10, TimeMinute01, TimeDelimiter, TimeSecond10, TimeSecond01]) {
			var img = indicators.get(time_type);
			img.x = 4 + 12 * idx + x_offset;
			img.y = 4 + y_offset;
		}
	}

	override function update(dt:Float) {
		bobby.update(dt);
		if (bobby.dead) {
			initLevel();
		} else if (bobby.faded_out || Key.isPressed(Key.N)) {
			currentLevel = (currentLevel + 1) % 50;
			initLevel();
		} else if (Key.isPressed(Key.P)) {
			currentLevel = (currentLevel + 49) % 50;
			initLevel();
		} else if (Key.isPressed(Key.R)) {
			initLevel();
		}
		if (Std.int(hxd.Timer.lastTimeStamp) != lastSeconds) {
			lastSeconds = Std.int(hxd.Timer.lastTimeStamp);
			updateIndicator(Time(lastSeconds - Std.int(startTime)));
		}
	}

	static function main() {
		hxd.Res.initEmbed();
		new Main();
	}
}
