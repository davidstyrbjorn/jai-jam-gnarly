
RELEASE_BUILD :: false;

GAME_AREA_SIZE :: (2 * SEGMENT_SIZE); // 43
UI_HEIGHT :: 7;

COLS: s16 : GAME_AREA_SIZE; // 43, for a square playable area
ROWS: s16 : GAME_AREA_SIZE + UI_HEIGHT; // 50, total window height in tiles

UI_START_Y :: GAME_AREA_SIZE; // 43, UI starts right after the game area

tile_w: s16 = 20;
tile_h: s16 = 20;

GOAL_COLOR :: rl.Color.{ 255, 215, 0, 255 };

STANDING_ON_WALL_BG :: rl.Color.{ 100, 100, 100, 100 };

Level_Goal :: enum {
  REACH_END :: 0;
  COLLECT_COINS :: 1;
  REACH_END_WITH :: 2;
  KILL_ALL_ENEMIES :: 3;
}

LIGHT_SOURCE_KINDS :: struct{
  kind: Entity_Kind;
  strength: s16;
}.[ .{ .DEAD_MARTYR, 6 }, .{ .FIRE, 6 }, .{ .FIREBALL, 4 } ];

FIRE_COLOR_1 :: rl.Color.{ 255,90,0,50 };
FIRE_COLOR_2 :: rl.Color.{ 255,154,0,50 };

CYCLE_START_X :: 3;
CYCLE_Y :: UI_START_Y + 3;

State :: enum {
  TRANSITION;
  PLAYING;
  PICKING_LOOP;
  MENU;
  GIVEN_UP;
}

GameState :: struct {
  // Used for editing
  edit_mode: bool = false;
  selected_point: SVector;

  // PICKING_LOOP related
  editing_loop_index: int = -1;
  modifying_loop_index: bool = false;
  desired_character_type: CharacterType;
  on_back_button: bool = false;

  loop: [4]CharacterType;
  loop_locked: [4]bool;
  current_loop_idx: int = 0;
  loops: int = 0;
  floors_cleared: int = 0;

  light_t: float;
  player_light_str: s16 = 12;

  shake_duration: float = 0.0;
  shake_intensity: float = 0.0;
  transition_t: float = 0.0;
  transition_origin: Vector2;
  spawn_level_flag: bool = false;

  transition_out: bool;

  standing_on_vision: bool = false;

  level_goal: Level_Goal = .REACH_END; 
  reach_end_with: CharacterType;

  state: State = .MENU;
}
game_state: GameState;
world: EntityWorld;

SVector :: struct {
  x, y: s16;
}

operator == :: (left: SVector, right: SVector) -> bool {
  return left.x == right.x && left.y == right.y;
}

operator + :: (left: SVector, right: SVector) -> SVector {
  return sxy(left.x + right.x, left.y + right.y);
}

is_zero :: (s: SVector) -> bool {
  return s.x == 0 && s.y == 0;
}

sdistance :: (a: SVector, b: SVector) -> float {
  a_float := Vector2.{ a.x.(float), a.y.(float) };  
  b_float := Vector2.{ b.x.(float), b.y.(float) };
  return distance(a_float, b_float);  
}

buffer: [COLS][ROWS]Cell;

CharacterType :: enum {
  SWIPER :: 0;
  TINKERER :: 1;
  MARTYR :: 2;
  DIGGER :: 3;
  // ALCHEMIST - randomly change type of tile
  WIZARD :: 4;
}

/// --- BEGIN ENTITY 

PlayerMove :: struct {
  old_pos: SVector;
  new_pos: SVector;
  player: *Entity;
}

LightUpdate :: struct {}
PlayerDied :: struct {}
FireballMove :: struct { _: bool; }
PlayerPerformedAction :: struct { _: u8; }
LevelCompleted :: struct {}
EnemyKilled :: struct {}

Command :: Tagged_Union(PlayerMove, PlayerDied, FireballMove, PlayerPerformedAction, LevelCompleted, EnemyKilled);

EntityWorld :: struct {
  entities: [..]Entity;   
  entity_groups: [NUM_ENTITY_KIND][..]*Entity;
  cached_id_to_index: Table.Table(u32, s32); 
  
  // For the logic that doesn't fit as an entity but still wants update and such
  update_systems: [..]#type (float);
  render_systems: [..]#type ();

  queued_commands: [..]Command; // Gets flushed into commands at the start of every update 
  commands: [..]Command; // Gets flushed at the end of every update

  dirty: bool; // To indicate we need to rebuild our arrays
  next_id: u32 = 0;
}

EntityInitProc :: #type (e: *Entity);
EntityUpdateProc :: #type (*Entity, dt: float);
EntityRenderProc :: #type (e: *Entity);

empty_init :: (_: *Entity) {}
empty_update :: (_: *Entity, _: float) {}
empty_render :: (_: *Entity) {}

// Mega entity struct
Entity :: struct {
  id: u32;
  init_proc: EntityInitProc = empty_init;
  update_proc: EntityUpdateProc = empty_update;
  render_proc: EntityRenderProc = empty_render;
  kind: Entity_Kind;
  behaviour: u16;

  spawn_pos: SVector;
  pos: SVector;
  offset: Vector2;
  color: rl.Color;
  background: rl.Color;
  glyph: int;
  move_tick: s16;
  alpha_modifier: float = 1.0;
  door_open: bool;
  character_type: CharacterType;
  swiping_dir: SVector;
  swipe_counter: float;
  action_prepped: bool = false;
  laser_direction: SVector;
  laser_state: enum {
    OFF :: 0;
    OFF2 :: 1;
    ON :: 2;
    ON2 :: 3;
    LOOP_BACK :: 4;
  };
  fire_t: float;

  fireball_direction: SVector;
  fireball_t: float;
}

NUM_ENTITY_KIND :: 14;
Entity_Kind :: enum u32 {
  PLAYER;
  ENEMY; 
  WALL; 
  DOOR; 
  LEVER; 
  KILL_TILE; 
  FIRE; 
  DEAD_MARTYR;
  DIGGABLE; 
  GOAL; 
  LASER;
  FIREBALL;
  COIN;
  VISION;
}

entity_world_init :: (world: *EntityWorld) {
  Table.init(*world.cached_id_to_index); 
}

entity_world_deinit :: (world: *EntityWorld) {
  Table.deinit(*world.cached_id_to_index);
  array_reset(*world.entities);
  array_reset(*world.update_systems);
  array_reset(*world.render_systems);
}

entity_world_update :: (world: *EntityWorld, dt: float) {
  if world.dirty {
    entity_world_rebuild(world);
  }
  world.dirty = false;

  for world.queued_commands {
    array_add(*world.commands, it);
  }
  array_reset(*world.queued_commands);

  for world.update_systems {
    it(dt);
  }

  for *world.entities {
    it.update_proc(it, dt);
  }

  array_reset(*world.commands);
}

entity_world_push_command :: (world: *EntityWorld, command: Command) {
  array_add(*world.queued_commands, command);
}

entity_world_render :: (world: *EntityWorld) {
  for world.render_systems {
    it();
  }
  for *world.entities {
    it.render_proc(it);
  }
}

entity_world_clear :: (world: *EntityWorld) {
  array_reset(*world.entities);
  entity_world_rebuild(world); // rebuild instantly here
}

entity_world_add :: (world: *EntityWorld, e: Entity) {
  array_add(*world.entities, e);
  new_e := *world.entities[world.entities.count-1];
  new_e.id = world.next_id;
  world.next_id += 1;
  new_e.init_proc(new_e);
  world.dirty = true;
}

entity_world_remove :: (world: *EntityWorld, id: u32) {
  index, success := Table.table_find(*world.cached_id_to_index, id);
  assert(success, "Should never happen! Index should always be in the cache table");
  array_unordered_remove_by_index(*world.entities, index);
  world.dirty = true;
}

entity_world_rebuild :: (world: *EntityWorld) {
  for 0..NUM_ENTITY_KIND-1 {
    array_reset(*world.entity_groups[it]);
  }
  for *world.entities {
    array_add(*world.entity_groups[it.kind], it);
  }

  Table.table_reset(*world.cached_id_to_index);
  for i : 0..world.entities.count-1 {
    Table.table_add(*world.cached_id_to_index, world.entities[i].id, i.(s32));
  }
}

/// --- END ENTITY

color :: inline (r: u8, g: u8, b: u8, a: u8 = 255) -> rl.Color {
  return rl.Color.{r, g, b, a};
}

color_random :: (a: u8  = 255) -> rl.Color {
  r := cast(u8)(random_get() % 255);
  g := cast(u8)(random_get() % 255);
  b := cast(u8)(random_get() % 255);
  return color(r, g, b, a);
}

xy :: inline (x: s16, y: s16) -> SVector {
  return SVector.{x, y};
}

sxy :: (x: s16, y: s16) -> SVector {
  return SVector.{x, y};
}

heuristic :: (p1: SVector, p2: SVector) -> s16 {
  return (abs(p1.x - p2.x) + abs(p1.y - p2.y)).(s16);
}

is_valid :: (pos: SVector) -> bool {
  return pos.x >= 0 && pos.x < COLS && pos.y >= 0 && pos.y < ROWS;
}

is_walkable :: (pos: SVector) -> bool, Entity_Kind {
  entity := find_entity_at(pos);
  if entity == null {
    return true, Entity_Kind.PLAYER;
  }

  if entity.kind == .DOOR {
    return entity.door_open, Entity_Kind.DOOR;
  }

  if entity.kind == {
    case .WALL; #through;
    case .LEVER; #through;
    case .DIGGABLE; #through;
    case .LASER; #through;
    case .KILL_TILE; return false, entity.kind;
  }

  return true, entity.kind;
}

is_occupied_by_enemy :: (pos: SVector) -> u32, bool {
  for world.entity_groups[Entity_Kind.ENEMY] {
    if it.pos.x == pos.x && it.pos.y == pos.y then return it.id, true;
  }

  return 0, false;
}

clear_buffer :: () {
  for y : 0..ROWS-1 {
    for x : 0..COLS-1 {
      cell := *buffer[x][y];
      cell.fg = color(0, 0, 0, 0);
      cell.bg = color(0, 0, 0, 0);
    }
  }
}

create_goal :: (pos: SVector) {
  goal_update :: (goal: *Entity, dt: float) {
    for world.commands {
      player_move := isa(it, PlayerMove);
      if player_move {
        if player_move.new_pos.x == goal.pos.x && player_move.new_pos.y == goal.pos.y {
          level_completed(player_move.new_pos);
        }
      }
    }
  }

  goal: Entity;
  goal.kind = .GOAL;
  goal.pos = pos;
  goal.color = GOAL_COLOR;
  goal.color.a = 0;
  goal.glyph = 88;

  goal.update_proc = goal_update;

  entity_world_add(*world, goal);
}

create_coin :: (pos: SVector) {
  coin_render :: (coin: *Entity) {
    cell := *buffer[coin.pos.x][coin.pos.y];
    cell.bg = color(233, 173, 3, cell.bg.a);
  }

  coin_update :: (coin: *Entity, dt: float) {
    for world.commands {
      if isa(it, PlayerMove) {
        player := world.entity_groups[Entity_Kind.PLAYER][0];
        if player.pos == coin.pos {
          // pickup le coin, self immolate
          trigger_screen_shake(2, 0.4);
          entity_world_remove(*world, coin.id);
          entity_world_rebuild(*world);

          if world.entity_groups[Entity_Kind.COIN].count == 0 {
            level_completed(player.pos);
          }
        }
      }
    }
  }
  
  coin: Entity;
  coin.kind = .COIN;
  coin.pos = pos;
  coin.glyph = "$"[0];
  coin.color = color(233,173,3);

  coin.update_proc = coin_update;
  coin.render_proc = coin_render;

  // Remove existing entity on this spot
  existing_entity := find_entity_at(pos);
  if existing_entity != null {
    entity_world_remove(*world, existing_entity.id);
  }

  entity_world_add(*world, coin);
}

create_wall :: (pos: SVector) {
  wall: Entity;

  wall.kind = .WALL;

  wall.pos = pos;
  wall.color = color(100, 100, 100, 255);
  wall.glyph = 35;

  entity_world_add(*world, wall);
}

create_vision :: (pos: SVector) {
  vision: Entity;

  vision.kind = .VISION;
  vision.pos = pos;
  vision.color = color(0,158,96);
  vision.glyph = "V"[0];

  entity_world_add(*world, vision);
}

laser_direction_to_glyph :: (dir: SVector) -> u8 {
  if dir.x == 1 then return ">"[0];
  if dir.x == -1 then return "<"[0];
  if dir.y == -1 then return "^"[0];
  if dir.y == 1 then return "v"[0];
  return "?"[0];
}

laser_pos_open :: (pos: SVector) -> bool {
  e := find_entity_at(pos);
  if !e {
    return true;
  }

  if e.kind == {
    case .WALL; #through;
    case .DOOR; #through;
    case .LEVER; #through;
    case .KILL_TILE; #through;
    case .DEAD_MARTYR; #through;
    case .DIGGABLE; #through;
    case .GOAL; #through;
    case .LASER; return false;
  }

  if !is_valid(pos) {
    return false;
  }

  return true;
}

get_laser_path :: (laser: *Entity) -> [..]SVector {
  path: [..]SVector;
  path.allocator = temp;
  pos := laser.pos + laser.laser_direction;
  while laser_pos_open(pos) {
    array_add(*path, pos);
    pos += laser.laser_direction;
  }
  return path;
}

create_laser :: (pos: SVector, dir: SVector) {
  render_laser :: (laser: *Entity) {
    cell := *buffer[laser.pos.x][laser.pos.y];
    cell.fg = laser.color;
    cell.glyph = laser.glyph;

    // Draw glyph in the direction of the laser until we hit something that stops it
    if laser.laser_state == .ON || laser.laser_state == .ON2 {
      MINIMUM_ALPHA :: 30;
      alpha: u16 = 255;
      path := get_laser_path(laser);
      player := world.entity_groups[Entity_Kind.PLAYER][0];
      for path {
        cell = *buffer[it.x][it.y];
        cell.glyph = "*"[0];
        cell.fg = rl.RED;
        cell.fg.a = alpha.(u8);

        new_alpha := cell.fg.a.(u64) + get_lit_alpha(player.pos, it, 6);
        new_alpha = min(new_alpha, 255);
        cell.fg.a = new_alpha.(u8);

        alpha = max(alpha-30, MINIMUM_ALPHA);
      }
    }
  }

  update_laser :: (laser: *Entity, dt: float) {
    laser.glyph = laser_direction_to_glyph(laser.laser_direction);

    cell := *buffer[laser.pos.x][laser.pos.y];
    cell.shake = false;
    if laser.laser_state == {
      case .OFF;
        laser.color = color(90, 90, 90, 255);
      case .OFF2;
        laser.color = color(90, 90, 90, 255);
        cell.shake = true;
      case .ON; #through;
      case .ON2;
        laser.color = color(255, 0, 0);
    }

    for world.commands {
      player_move := isa(it, PlayerMove);
      performed_action := isa(it, PlayerPerformedAction);
      if player_move || performed_action {
        laser.laser_state += 1;
        if laser.laser_state == .LOOP_BACK then laser.laser_state = .OFF;
      }
    }
  }

  laser: Entity;
  laser.update_proc = update_laser;
  laser.render_proc = render_laser;

  // Tiles that blocks laser
  // WALL, DOOR, LEVER, KILL_TILE, DEAD_MARTYR, DIGGABLE, GOAL, LASER
  // Tiles that laser goes through
  // FIRE
  // Tiles that laser kills
  // PLAYER, ENEMY
  
  laser.kind = .LASER;
  laser.glyph = laser_direction_to_glyph(dir);
  laser.color = color(255, 0, 0);

  laser.pos = pos;
  laser.laser_direction = dir;
  laser.laser_state = .OFF;

  entity_world_add(*world, laser);
}

create_fireball :: (pos: SVector, dir: SVector) {
  fireball_render :: (fireball: *Entity) {
    cell := *buffer[fireball.pos.x][fireball.pos.y];
    cell.fg = fireball.color;
    cell.glyph = fireball.glyph;
  }

  fireball_update :: (fireball: *Entity, dt: float) {
    FIREBALL_FREQ :: 0.1;
    fireball.fireball_t += dt;
    if fireball.fireball_t > FIREBALL_FREQ {
      fireball.fireball_t = 0;

      cmd: Command;
      set(*cmd, FireballMove.{ true });
      entity_world_push_command(*world, cmd);
      prev_pos := fireball.pos;
      fireball.pos += fireball.fireball_direction;
      walkable, kind := is_walkable(fireball.pos); 
      if !walkable {
        entity_world_remove(*world, fireball.id);
        trigger_screen_shake(2, 0.25);
        return;
      }

      // Random chance to leave a fire if the tile is empty
      if kind == .FIREBALL {
        if random_get() % 100 > 50 {
          create_fire(prev_pos);
        }
      }
    } 
  }
  
  fireball: Entity;
  fireball.kind = .FIREBALL;
  fireball.glyph = "*"[0];
  fireball.color = FIRE_COLOR_1;
  fireball.color.a = 255;
  fireball.pos = pos;
  fireball.fireball_direction = dir;
  fireball.fireball_t = 0.0;

  fireball.render_proc = fireball_render;
  fireball.update_proc = fireball_update;

  entity_world_add(*world, fireball);
}

create_diggable :: (pos: SVector) {
  diggable: Entity;

  diggable.pos = pos;
  diggable.color = color(79, 58, 43, 255);
  diggable.kind = .DIGGABLE;    
  diggable.glyph = 35;

  entity_world_add(*world, diggable);
}

create_lever :: (pos: SVector) {
  lever: Entity;

  lever.kind = .LEVER;

  lever.pos = pos;
  lever.color = color(0, 139, 139, 255);
  lever.glyph = 76;

  entity_world_add(*world, lever);
}

create_door :: (pos: SVector) {

  door_update :: (door: *Entity, dt: float) {
    if(door.door_open) {
      door.color.a = 0;
    }
  }

  door: Entity;
  door.kind = .DOOR;
  door.pos = pos;
  door.color = color(0, 139, 139, 255);
  door.glyph = 68;

  door.update_proc = door_update;

  entity_world_add(*world, door);
}

create_dead_martyr :: (pos: SVector) {
  dead_martyr: Entity;
  dead_martyr.kind = .DEAD_MARTYR;

  dead_martyr.pos = pos;
  dead_martyr.color = CHARACTER_COLORS[CharacterType.MARTYR];
  dead_martyr.alpha_modifier = 0.25;
  dead_martyr.glyph = GLYPH.MARTYR.(int);

  entity_world_add(*world, dead_martyr);
}

create_kill_tile :: (pos: SVector) {
  kill_tile: Entity;
  kill_tile.kind = .KILL_TILE;

  kill_tile.pos = pos;
  kill_tile.color = color_random();
  kill_tile.glyph = cast(int)(32 + random_get() % (126-32));

  entity_world_add(*world, kill_tile);
}

create_fire :: (pos: SVector) {
  fire_update :: (fire: *Entity, dt: float) {
    FIRE_UPDATE_FREQ :: .2;
    fire.fire_t += dt;
    if fire.fire_t > FIRE_UPDATE_FREQ {
      fire.fire_t = 0;
      fire.glyph = FIRE_GLYPHS[random_get() % FIRE_GLYPHS.count];
    }
  }

  fire_render :: (fire: *Entity) {
    cell := *buffer[fire.pos.x][fire.pos.y];
    cell.fg = fire.color;
    cell.bg = fire.background;
    cell.glyph = fire.glyph;
  }

  fire: Entity;
  fire.kind = .FIRE;

  fire.pos = pos;
  fire.color = color(255, 0, 0, 100);
  fire.background = FIRE_COLOR_1;
  fire.update_proc = fire_update;
  fire.render_proc = fire_render;

  entity_world_add(*world, fire);
}

create_enemy :: (pos: SVector) {
  enemy: Entity;
  enemy.kind = .ENEMY;

  enemy_update :: (enemy: *Entity, dt: float) {
    if game_state.edit_mode {
      enemy.color = color(90, 90, 90, 255);
      enemy.move_tick = 0;
      return;
    }

    enemy.alpha_modifier = 1.0;
    // Check if enemy is inside the beam of a laser
    for laser : world.entity_groups[Entity_Kind.LASER] {
      if laser.laser_state == .ON || laser.laser_state == .ON2 {
        for pos : get_laser_path(laser) {
          if pos == enemy.pos {
            entity_world_remove(*world, enemy.id);
            cmd: Command;
            set(*cmd, EnemyKilled.{});
            entity_world_push_command(*world, cmd);
            trigger_screen_shake(2, 1);
            break;
          }
        }
      }
    }

    // Check if we're hit by a fireball
    for fireball : world.entity_groups[Entity_Kind.FIREBALL] {
      if fireball.pos == enemy.pos {
        create_fire(enemy.pos);
        entity_world_remove(*world, enemy.id);
        entity_world_remove(*world, fireball.id);
        cmd: Command;
        set(*cmd, EnemyKilled.{});
        entity_world_push_command(*world, cmd);
        trigger_screen_shake(2, 1);
        break;
      }
    }

    for world.commands {
      player_move := isa(it, PlayerMove);
      performed_action := isa(it, PlayerPerformedAction);
      if player_move || performed_action {
        player := world.entity_groups[Entity_Kind.PLAYER][0];
        // The enemy doesn't react to the swiper character
        if player_move && player.character_type == .SWIPER {
          return;
        }

        sees_player, t := has_line_of_sight(enemy, player, 8);
        if sees_player {
          enemy.color = color(255, 20, 50, enemy.color.a);
        } else {
          enemy.color = color(90, 90, 90, enemy.color.a);
        }

        // Move?
        enemy.move_tick += 1;
        if enemy.move_tick % 2 == 0 && has_line_of_sight(enemy, player, 8) {
          // Check if we're neighbouring to the player, if so lets go ahead and kill them 
          if is_direct_neighbour(player.pos, enemy.pos) {
            cmd: Command;
            set(*cmd, PlayerDied.{});
            entity_world_push_command(*world, cmd);
          }else {
            move_enemy_towards_player(player, enemy);
          }
        }
      }
      else if isa(it, PlayerDied) {
        enemy.pos = enemy.spawn_pos;
      }
    }
  }

  enemy.update_proc = enemy_update;

  enemy.pos = pos;
  enemy.spawn_pos = pos;
  enemy.move_tick = 0;
  enemy.color = color(90, 90, 90, 255);
  enemy.glyph = 69;

  // Remove existing entity on this spot
  existing_entity := find_entity_at(pos);
  if existing_entity != null {
    entity_world_remove(*world, existing_entity.id);
  }

  entity_world_add(*world, enemy);
}

open_closest_door :: (from: SVector) {
  segment_start := get_segment_start(from);
  closest_door: *Entity = null;
  for y: segment_start.y..segment_start.y+SEGMENT_SIZE-1 {
    for x: segment_start.x..segment_start.x+SEGMENT_SIZE-1 {
      e := find_entity_at(xy(x,y));
      if !e then continue;
      if e.kind == .DOOR {
        if !closest_door then closest_door = e;
        else {
          if sdistance(e.pos, from) < sdistance(closest_door.pos, from) {
            closest_door = e;
          }
        } 
      }
    }
  }

  if closest_door {
    closest_door.door_open = true;
  }
}

tinkerer_place_wall :: (at: SVector) {
  e := find_entity_at(at);
  if e {
    // Check if e is a type of tile we are allowed to place blocks on?
    // TODO: Ask ALI
    return;
  }

  create_wall(at);
}

find_entity_of_kind_at :: (kind: Entity_Kind, pos: SVector) -> *Entity {
  for world.entity_groups[kind] {
    if it.pos == pos return it;
  }
  return null;
}

create_player :: () {
  set_player_pos :: (player: *Entity, x: s16, y: s16) {
    command: Command;
    set(*command, PlayerMove.{ player.pos, xy(x, y), player });
    entity_world_push_command(*world, command);

    player.pos = xy(x, y);
  }

  // Return true or false depending on if we successfully moved or not
  move_player :: (player: *Entity, delta: SVector) -> bool {
    new_pos := xy(player.pos.x + delta.x, player.pos.y + delta.y);
    // Check for wall
    walkable, kind := is_walkable(new_pos);
    if kind == .KILL_TILE {
      // @MECHANIC "Martyrs can cover up KILL TILES"
      if player.character_type == .MARTYR  {
        entity_world_remove(*world, find_entity_at(new_pos).id);
        create_dead_martyr(new_pos);
      }

      command: Command;
      set(*command, PlayerDied.{});
      entity_world_push_command(*world, command); 
      return false;
    }
    if kind == .FIRE && player.character_type != .SWIPER {
      // @MECHANIC: Fire kills player unless you are a swiper
      command: Command;
      set(*command, PlayerDied.{});
      entity_world_push_command(*world, command); 
      return false;
    }
    if player.character_type == .SWIPER && kind == .ENEMY {
      // @MECHANIC: Swiper can kill enemies by moving through them
      entity_world_remove(*world, find_entity_at(new_pos).id);
      player.swiping_dir = xy(0, 0);
      player.swipe_counter = 0.0;
      
      cmd: Command;
      set(*cmd, EnemyKilled.{});
      entity_world_push_command(*world, cmd);
      
      trigger_screen_shake(2, 1);
      return false;
    }
    if kind == .GOAL && game_state.level_goal == .REACH_END_WITH {
      if player.character_type != game_state.reach_end_with {
        trigger_screen_shake(2, 0.4);
        return false;
      } 
    }
    
    if (!game_state.edit_mode && !walkable) || !is_valid(new_pos) || kind == .ENEMY then return false;

    set_player_pos(player, new_pos.x, new_pos.y);

    if player.character_type == .SWIPER && is_zero(player.swiping_dir) {
      player.swiping_dir = delta;
      player.swipe_counter = 0;
    }

    return true;
  }

  is_explodeable :: (entity: *Entity) -> bool {
    return entity.kind == .ENEMY; // TODO:
  }


  EXPLODABLE_KINDS :: Entity_Kind.[ .ENEMY, .WALL, .KILL_TILE, .FIRE, .DIGGABLE ];
  EXPLODE_RADIUS: s16 : 2;
  martyr_explode :: (origin: SVector) {
    // 1. Create a temporary list to hold the IDs of entities to remove.
    ids_to_remove: [..]u32;
    ids_to_remove.allocator = temp; // Use temporary storage

    // Find all entities within the radius that should be exploded.
    for y: -EXPLODE_RADIUS..EXPLODE_RADIUS {
        for x: -EXPLODE_RADIUS..EXPLODE_RADIUS {
            pos := origin + xy(x, y);

            if !is_valid(pos) continue;

            // Find an entity at this position.
            maybe_e := find_entity_at(pos);
            if maybe_e {
                // Check if its kind is in our list of explodable types.
                for kind_to_check : EXPLODABLE_KINDS {
                    if maybe_e.kind == kind_to_check {
                        // 2. Instead of removing, add its ID to our list.
                        array_add(*ids_to_remove, maybe_e.id);
                        break; // Found a match, no need to check other kinds for this entity.
                    }
                }
            }
        }
    }
    
    // 3. Now, safely remove all collected entities.
    for id : ids_to_remove {
        entity_world_remove(*world, id);
        entity_world_rebuild(*world);
    }

    // A single rebuild after all removals are done.
    if ids_to_remove.count > 0 {
    } 
  }

 
  update_player :: (player: *Entity, dt: float) {
    player.character_type = game_state.loop[game_state.current_loop_idx];
    player.glyph = CHARACTER_GLYPHS[player.character_type].(int);
    player.color = CHARACTER_COLORS[player.character_type];

    if game_state.state == .PICKING_LOOP {
      // This is a godamn shitshow... UI!!!
      if game_state.modifying_loop_index {
        if rl.IsKeyPressed(.KEY_D) {
          game_state.desired_character_type += 1;
        }
        else if rl.IsKeyPressed(.KEY_A) {
          game_state.desired_character_type -= 1;
        } 
        game_state.desired_character_type = clamp(game_state.desired_character_type, 0, CharacterType.WIZARD);

        if rl.IsKeyPressed(.KEY_SPACE) {
          game_state.loop[game_state.editing_loop_index] = game_state.desired_character_type;
          // Done, reset
          game_state.modifying_loop_index = false;
          game_state.desired_character_type = 0;          
        }
      } 
      else if game_state.on_back_button {
        if rl.IsKeyPressed(.KEY_W) {
          game_state.on_back_button = false;
        }
        else if rl.IsKeyPressed(.KEY_SPACE) {
          // Reset and now we can switch over to PLAYING state
          game_state.on_back_button = false;
          game_state.desired_character_type = 0;
          game_state.modifying_loop_index = false;
          game_state.editing_loop_index = 0;

          game_state.state = .PLAYING;
        }
      } 
      else {
        if rl.IsKeyPressed(.KEY_D) {
          game_state.editing_loop_index += 1;
        }
        else if rl.IsKeyPressed(.KEY_A) {
          game_state.editing_loop_index -= 1;
        } 
        else if rl.IsKeyPressed(.KEY_SPACE) {
          game_state.modifying_loop_index = true;
        }
        else if rl.IsKeyPressed(.KEY_S) {
          game_state.on_back_button = true;  
        }
        game_state.editing_loop_index = clamp(game_state.editing_loop_index, 0, 3);
      }
    }
    else if game_state.state == .PLAYING {
      SWIPE_MOVE_FREQ :: 0.1; // Seconds
      if player.character_type == .SWIPER && !is_zero(player.swiping_dir) {
        player.swipe_counter += dt;
        if player.swipe_counter > SWIPE_MOVE_FREQ {
          player.swipe_counter = 0;
          finished := !move_player(player,player.swiping_dir);
          if finished {
            player.swiping_dir = xy(0, 0);
          }   
        }
      }else {
        input := sxy(0, 0);
        if rl.IsKeyPressed(.KEY_D) input = xy(1, 0);
        if rl.IsKeyPressed(.KEY_A) input = xy(-1, 0);
        if rl.IsKeyPressed(.KEY_S) input = xy(0, 1);
        if rl.IsKeyPressed(.KEY_W) input = xy(0, -1);
        if !is_zero(input) {
          if player.character_type == .TINKERER && player.action_prepped {
            // @Mechanic TINKERER can pull lever
            maybe_lever := find_entity_of_kind_at(Entity_Kind.LEVER, player.pos + input);
            if maybe_lever {
              open_closest_door(maybe_lever.pos);
              cmd: Command;
              set(*cmd, PlayerPerformedAction.{0});
              entity_world_push_command(*world, cmd);
            }else {
              tinkerer_place_wall(player.pos + input);
              cmd: Command;
              set(*cmd, PlayerPerformedAction.{0});
              entity_world_push_command(*world, cmd);
            }
            player.action_prepped = false;
          }
          else if player.character_type == .WIZARD && player.action_prepped {
            create_fireball(player.pos + input, input);
            player.action_prepped = false;
            cmd: Command;
            set(*cmd, PlayerPerformedAction.{1});
            entity_world_push_command(*world, cmd);
          } else if player.character_type == .DIGGER && player.action_prepped {
            maybe_wall := find_entity_of_kind_at(Entity_Kind.DIGGABLE, player.pos + input);
            if maybe_wall {
              entity_world_remove(*world, maybe_wall.id);
              cmd: Command;
              set(*cmd, PlayerPerformedAction.{1});
              entity_world_push_command(*world, cmd);
            }
            player.action_prepped = false;
          } else {
            move_player(player, input);
          }
        }

        for vision : world.entity_groups[Entity_Kind.VISION] {
          if vision.pos == player.pos {
            game_state.standing_on_vision = true;
            break;
          }
          game_state.standing_on_vision = false;
        }

        if rl.IsKeyPressed(.KEY_SPACE) && (player.character_type == .TINKERER || player.character_type == .WIZARD || player.character_type == .DIGGER) {
          player.action_prepped = !player.action_prepped;
        }
        if rl.IsKeyPressed(.KEY_SPACE) && player.character_type == .MARTYR {
          martyr_explode(player.pos);
          cmd: Command;
          set(*cmd, PlayerDied.{});
          entity_world_push_command(*world, cmd);
          game_state.loop_locked[game_state.current_loop_idx] = true;
        }

        if rl.IsKeyPressed(.KEY_Y) {
          game_state.state = .GIVEN_UP;
        }

        // Check if we're standing in the path of a laser
        for laser : world.entity_groups[Entity_Kind.LASER] {
          if laser.laser_state == .ON || laser.laser_state == .ON2 {
            for pos : get_laser_path(laser) {
              if pos == player.pos {
                cmd: Command;
                set(*cmd, PlayerDied.{});
                entity_world_push_command(*world, cmd);
                break;
              }
            }
          }
        }

        // Shake baby
        cell := *buffer[player.pos.x][player.pos.y];
        cell.shake = player.action_prepped;

      }

      if rl.IsKeyPressed(.KEY_R) {
        cmd: Command;
        set(*cmd, PlayerDied.{});
        entity_world_push_command(*world, cmd);
      }

      // Are we currently standing on a mod station tile? 
      // game_state.prev_light_strength = game_state.player_light_strength.(s16);
      // desired_light_strength: float = ifx on_mod_station then ENHANCED_PLAYER_LIGHT_STR else NORMAL_PLAYER_LIGHT_STR;
      // game_state.player_light_strength = lerp(game_state.player_light_strength, desired_light_strength, 1.0 * dt);
      // game_state.curr_light_strength = game_state.player_light_strength.(s16);

      // Process death
      for world.commands {
        if isa(it, PlayerDied) {
          game_state.current_loop_idx = (game_state.current_loop_idx+1) % game_state.loop.count;
          while game_state.loop_locked[game_state.current_loop_idx] game_state.current_loop_idx = (game_state.current_loop_idx+1) % game_state.loop.count;
          player.action_prepped = false;
          game_state.loops += 1;
          trigger_screen_shake(2, 0.5);
          set_player_pos(player, 1, 1);
        }
      }

  #if !RELEASE_BUILD {
      if rl.IsKeyPressed(.KEY_C) {
        create_wall(xy(player.pos.x, player.pos.y)); // Give birth, right here, right now
      }
      if rl.IsKeyPressed(.KEY_TAB) then game_state.edit_mode = !game_state.edit_mode;
      // if rl.IsKeyPressed(.KEY_X) then trigger_screen_shake(5, 1);
      if rl.IsKeyPressed(.KEY_X) then level_completed(player.pos);
  }
    }
  }

  render_player :: (player: *Entity) {
    player_cell := *buffer[player.pos.x][player.pos.y];
    player_cell.fg = player.color;
    if game_state.state == .MENU || game_state.state == .TRANSITION {
      player_cell.fg.a = 0;
    }
    player_cell.glyph = player.glyph;
  }

  player: Entity;
  player.kind = .PLAYER;
  player.update_proc = update_player;
  player.render_proc = render_player;

  player.pos = xy(1, 1);
  player.character_type = .SWIPER;

  entity_world_add(*world, player);
}

trigger_screen_shake :: (intensity: float, duration: float) {
  game_state.shake_intensity = intensity;
  game_state.shake_duration = duration;
}

get_segment_start :: (point: SVector) -> SVector {
  start: SVector = xy(0, 0);
  if point.x < SEGMENT_SIZE && point.y < SEGMENT_SIZE then start = xy(0, 0);
  else if point.x >= SEGMENT_SIZE && point.y < SEGMENT_SIZE then start = xy(SEGMENT_SIZE, 0);
  else if point.x < SEGMENT_SIZE && point.y >= SEGMENT_SIZE then start = xy(0, SEGMENT_SIZE);
  else start = xy(SEGMENT_SIZE, SEGMENT_SIZE);
  return start;
}

print_currently_selected_segment :: () {
  segment_offset := get_segment_start(game_state.selected_point);
  
  print("BEGIN LEVEL\n");

  for y: segment_offset.y..segment_offset.y+SEGMENT_SIZE-1 {
    for x: segment_offset.x..segment_offset.x+SEGMENT_SIZE-1 {
      e := find_entity_at(xy(x, y));
      if e == null {
        print("_");
        continue;
      }
      if e.kind == {
        case .ENEMY;
          print("E");
        case .WALL; 
          print("#");
        case .DOOR; 
          print("D");
        case .LEVER; 
          print("L");
        case .KILL_TILE;
          print("K"); 
        case .FIRE; 
          print("F");
        case .DIGGABLE;
          print("d"); 
        case .GOAL; 
          print("G");
        case .LASER;
          print("%", to_string(*laser_direction_to_glyph(e.laser_direction), 1));
        case .COIN;
          print("$");
        case .VISION;
          print("V");
        case;
          print("_");
      }
    }
      print("\n");
  }

  print("END LEVEL");
}

  // file_name := tprint("./level.in");
  // file, success := file_open(file_name, true);
  // assert(success, "Failed to open level file for writing!");
  // defer file_close(*file);
  // file_write(*file, *builder);

  // print("Saved level!\n");


kill_tile_system :: (dt: float) {
  for world.entity_groups[Entity_Kind.KILL_TILE] {
    if random_get() % 100 < 10 {
      it.glyph = cast(int)(32 + random_get() % (126-32));
    }
  }
}

find_entity_at :: (pos: SVector) -> *Entity {
  for *world.entities {
    if it.pos == pos {
      return it;
    }
  }

  return null;
}

flood_fill_walls :: (pos: SVector) {
    // First, check if the starting point is valid and empty.
    // We can't start a fill on a tile that's already occupied.
    if !is_valid(pos) || find_entity_at(pos) != null {
        return;
    }

    // A queue to hold the coordinates of tiles we need to visit.
    queue: [..]SVector;
    compare_s_vector :: (a: SVector, b: SVector) -> bool {
      return a == b;
    }
    hash :: (v: SVector) -> u32 {
      // Start with a non-zero seed, often a prime number.
      h: u32 = 17;

      // Mix in each component of the vector.
      // Multiplying by another prime number (like 31) helps distribute the bits.
      h = h * 31 + v.x.(u32);
      h = h * 31 + v.y.(u32);
      
      return h;
    }
    // A hash table to keep track of tiles we've already visited to avoid infinite loops.
    visited: Table.Table(SVector, bool, given_compare_function = compare_s_vector, given_hash_function = hash);
    Table.init(*visited);
    defer Table.deinit(*visited); // Ensure the table memory is freed when the function exits.

    // Start the process with the given position.
    array_add(*queue, pos);
    Table.table_add(*visited, pos, true);

    while queue.count > 0 {
        // Get the next tile from the front of the queue.
        current_pos := queue[0];
        array_ordered_remove_by_index(*queue, 0);

        // Place a wall at the current position.
        create_wall(current_pos);

        // Now, check the four neighbors (up, down, left, right).
        neighbors := SVector.[
            current_pos + xy(0, 1),  // Down
            current_pos + xy(0, -1), // Up
            current_pos + xy(1, 0),  // Right
            current_pos + xy(-1, 0)  // Left
        ];

        for neighbor_pos : neighbors {
            // A neighbor is a candidate for the fill if it is:
            // 1. Within the game world's bounds.
            // 2. Not already visited.
            // 3. Not currently occupied by another entity.
            index, success := Table.table_find(*visited, neighbor_pos); 
            is_candidate := is_valid(neighbor_pos) &&
                            !success &&
                            find_entity_at(neighbor_pos) == null;

            if is_candidate {
                Table.table_add(*visited, neighbor_pos, true); // Mark as visited.
                array_add(*queue, neighbor_pos);         // Add to the queue to process later.
            }
        }
    }

    // IMPORTANT: After adding many entities, we must rebuild the world's
    // entity groups and caches to ensure everything works correctly.
    entity_world_rebuild(*world);
}

edit_system :: (dt: float) {
  if !game_state.edit_mode then return;

  if game_state.selected_point.x != -1 {
    // Draw a rect over the selected tile
    point := game_state.selected_point;
    pos := xy((point.x*tile_w).(float), (point.y*tile_h).(float));
    rl.DrawRectangle(pos.x.(s32), pos.y.(s32), tile_w, tile_h, color(20, 255, 30, 100));
  }
  
  if rl.IsMouseButtonPressed(.MOUSE_BUTTON_LEFT) && game_state.selected_point.x == -1 {
    mouse_pos := rl.GetMousePosition();
    mouse_pos.x /= rl.GetScreenWidth();
    mouse_pos.y /= rl.GetScreenHeight();

    grid_pos: SVector;
    grid_pos.x = (mouse_pos.x * COLS).(s16); 
    grid_pos.y = (mouse_pos.y * ROWS).(s16); 

    // We want to be able to modify the loop easily, so initiate that here
    if grid_pos.y == CYCLE_Y {
      idx := 0;
      for x: CYCLE_START_X..CYCLE_START_X+3 {
        if grid_pos.x == x {
          game_state.editing_loop_index = idx;
        }
        idx += 1;
      }
    }

    game_state.selected_point = grid_pos;
  }

  if rl.IsMouseButtonPressed(.MOUSE_BUTTON_RIGHT) {
    game_state.selected_point.x = -1;
    game_state.editing_loop_index = -1;
  }

  if rl.IsKeyPressed(.KEY_DELETE) {
    e := find_entity_at(game_state.selected_point);
    entity_world_remove(*world, e.id);
  }

  if rl.IsKeyPressed(.KEY_P) {
    if game_state.selected_point.x != -1 {
      print_currently_selected_segment();
    } else {
      trigger_screen_shake(4, 1);
    }
  }

  if rl.IsKeyPressed(.KEY_F) && game_state.selected_point.x != -1 {
    flood_fill_walls(game_state.selected_point);
  }

  if rl.IsKeyDown(.KEY_LEFT_ALT) {
    height := rl.GetScreenHeight().(float);
    if game_state.editing_loop_index != -1 {
      btn_pressed := false;
      if rl.GuiButton(rl.Rectangle.{120*0, height-50, 100, 30}, "SWIPER") {
        game_state.loop[game_state.editing_loop_index] = .SWIPER;
        btn_pressed = true;
      }
      if rl.GuiButton(rl.Rectangle.{120*1, height-50, 100, 30}, "TINKERER") {
        game_state.loop[game_state.editing_loop_index] = .TINKERER;
        btn_pressed = true;
      } 
      if rl.GuiButton(rl.Rectangle.{120*2, height-50, 100, 30}, "MARTYR") {
        game_state.loop[game_state.editing_loop_index] = .MARTYR;
        btn_pressed = true;
      } 
      if rl.GuiButton(rl.Rectangle.{120*3, height-50, 100, 30}, "DIGGER") {
        game_state.loop[game_state.editing_loop_index] = .DIGGER;
        btn_pressed = true;
      } 
      if btn_pressed {
        game_state.editing_loop_index = -1;
        game_state.selected_point.x = -1;
      }
      return;
    }

    e := find_entity_at(game_state.selected_point);
    if e != null {
      str_buffer := to_c_string(tprint("ID = %, Kind = %", e.id, e.kind));
      defer free(str_buffer);
      rl.GuiLabel(rl.Rectangle.{10, height-100, 200, 50}, str_buffer);
      if rl.GuiButton(rl.Rectangle.{10, height-50, 100, 50}, "Delete") {
        entity_world_remove(*world, e.id);
        return;
      }
      if e.kind == .LEVER {
        if rl.GuiButton(rl.Rectangle.{220, height-50, 100, 50}, "PULL") {
          // TODO: New behaviour
          return;
        }
      }
      if e.kind == .LASER {
        if rl.GuiButton(rl.Rectangle.{220, height-50, 100, 50}, "ROTATE") {
          if e.laser_direction.x == 1 {
            e.laser_direction = xy(0, -1);
          }
          else if e.laser_direction.y == -1 then e.laser_direction = xy(-1, 0);
          else if e.laser_direction.x == -1 then e.laser_direction = xy(0, 1);
          else if e.laser_direction.y == 1 then e.laser_direction = xy(1, 0);
          return;
        }
      }
    }else if game_state.selected_point.x != -1 {
      if rl.GuiButton(rl.Rectangle.{100*0, height-50, 90, 30}, "WALL") {
        create_wall(game_state.selected_point);
        game_state.selected_point.x = -1;
      }
      if rl.GuiButton(rl.Rectangle.{100*1, height-50, 90, 30}, "DOOR") {
        create_door(game_state.selected_point);
        game_state.selected_point.x = -1;
      }
      if rl.GuiButton(rl.Rectangle.{100*2, height-50, 90, 30}, "LEVER") {
        create_lever(game_state.selected_point);
        game_state.selected_point.x = -1;
      }
      if rl.GuiButton(rl.Rectangle.{100*3, height-50, 90, 30}, "KILL") {
        create_kill_tile(game_state.selected_point);
        game_state.selected_point.x = -1;
      }
      if rl.GuiButton(rl.Rectangle.{100*4, height-50, 90, 30}, "ENEMY") {
        create_enemy(game_state.selected_point);
        game_state.selected_point.x = -1;
      }
      if rl.GuiButton(rl.Rectangle.{100*5, height-50, 90, 30}, "DIGGABLE") {
        create_diggable(game_state.selected_point);
        game_state.selected_point.x = -1;
      }
      if rl.GuiButton(rl.Rectangle.{100*6, height-50, 90, 30}, "FIRE") {
        create_fire(game_state.selected_point);
        game_state.selected_point.x = -1;
      }
      if rl.GuiButton(rl.Rectangle.{100*7, height-50, 90, 30}, "GOAL") {
        create_goal(game_state.selected_point);
        game_state.selected_point.x = -1;
      }
      if rl.GuiButton(rl.Rectangle.{100*0, height-80, 90, 30}, "LASER") {
        create_laser(game_state.selected_point, xy(1, 0));
        game_state.selected_point.x = -1;
      }
      if rl.GuiButton(rl.Rectangle.{100*1, height-80, 90, 30}, "COIN") {
        create_coin(game_state.selected_point);
        game_state.selected_point.x = -1;
      }
      if rl.GuiButton(rl.Rectangle.{100*2, height-80, 90, 30}, "VISION") {
        create_vision(game_state.selected_point);
        game_state.selected_point.x = -1;
      }
    }
  }
}

glyph_basic_render_system :: () {
  for *world.entities {
    if is_basic_rendered(it.kind) {
      cell := *buffer[it.pos.x][it.pos.y];
      
      cell.fg = it.color;
      cell.bg = it.background;

      if game_state.edit_mode {
        cell.fg.a = 255;
      }

      cell.glyph = it.glyph;
    }
  }

  // Color background if player is overlapping with wall
  player := world.entity_groups[Entity_Kind.PLAYER][0];
  for world.entity_groups[Entity_Kind.WALL] {
    if it.pos == player.pos {
      cell := *buffer[it.pos.x][it.pos.y];
      cell.bg = STANDING_ON_WALL_BG;
      break;
    }
  }

  // Color background if player is overlapping with goal
  for world.entity_groups[Entity_Kind.GOAL] {
    if it.pos == player.pos {
      cell := *buffer[it.pos.x][it.pos.y];
      cell.bg = GOAL_COLOR;
      cell.bg.a = 160;
      break;      
    }
  }
}

is_basic_rendered :: (kind: Entity_Kind) -> bool {
  return kind == .WALL || kind == .ENEMY || kind == .KILL_TILE || kind == .DOOR || kind == .LEVER || kind == .DEAD_MARTYR || kind == .DIGGABLE || kind == .GOAL || kind == .COIN || kind == .VISION;
}

glyph_basic_update_system :: (dt: float) {

  calculate_alpha :: (color: *rl.Color, pos: SVector, alpha_modifier: float) {
    player := world.entity_groups[Entity_Kind.PLAYER][0];
    // Basisc player litness
    color.a = get_lit_alpha(player.pos, pos, game_state.player_light_str);

    // Other tiles that can give light
    for kind_strength : LIGHT_SOURCE_KINDS {
      for source : world.entity_groups[kind_strength.kind] {
        new_alpha := color.a.(u64) + get_lit_alpha(source.pos, pos, kind_strength.strength).(u64);
        max_alpha: u64 = 255;
        new_alpha = min(max_alpha, new_alpha);
        color.a = new_alpha.(u8);
      }
    }
    color.a = (color.a * alpha_modifier).(u8);
  }

  for cmd : world.commands {
    player_move := isa(cmd, PlayerMove);
    fireball_move := isa(cmd, FireballMove);
    light_update := isa(cmd, LightUpdate);
    if player_move || fireball_move || light_update {
      for *world.entities {
        if is_basic_rendered(it.kind) {
          calculate_alpha(*it.color, it.pos, it.alpha_modifier);
          if it.kind == .COIN {
            calculate_alpha(*it.background, it.pos, 0.5);
          }
        }
      }
    }
  }
}

draw_string :: (start_x: s16, y: s16, str: string, background: rl.Color = rl.BLANK) {
  x := start_x;
  for i : 0..str.count-1 {
    c := str[i];
    cell := *buffer[x][y];
    cell.glyph = c;
    cell.fg = rl.WHITE;
    cell.bg = background;
    x += 1;
  }
}

render_ui_system :: () {
  y := UI_START_Y;
  glyph := 126;
  for x: 0..COLS-1 {
    cell := *buffer[x][y];
    cell.glyph = glyph;
    cell.fg = ifx game_state.edit_mode then rl.PURPLE else rl.WHITE;
  }

  for x: 0..COLS-1 {
    for y: UI_START_Y..ROWS-1 {
      cell := *buffer[x][y];
      cell.bg = rl.WHITE;
      cell.bg.a = 10;
    }
  }
  if game_state.state == .PLAYING || game_state.state == .PICKING_LOOP {
    cell := *buffer[CYCLE_START_X + game_state.current_loop_idx][CYCLE_Y+1];
    if game_state.state == .PLAYING {
      cell.glyph = 94;
      cell.fg = rl.WHITE;
    }

    for 0..3 {
      cell = *buffer[CYCLE_START_X+it][CYCLE_Y];
      cell.glyph = CHARACTER_GLYPHS[game_state.loop[it]].(int);
      cell.fg = CHARACTER_COLORS[game_state.loop[it]];
      cell.bg = rl.GRAY;

      if game_state.state == .PICKING_LOOP && game_state.editing_loop_index == it && !game_state.on_back_button {
        cell.bg.a = 100;
      }else {
        cell.bg.a = 0;
      }

      if game_state.loop_locked[it] {
        cell.bg = rl.RED;
        cell.bg.a = 120;
      }
    }

    if game_state.state == .PLAYING {
      draw_string(CYCLE_START_X, CYCLE_Y-2, "R=next");
      draw_string(CYCLE_START_X, CYCLE_Y-2, "Y=give up");
      
      loops_str := tprint("loops=%", game_state.loops);
      draw_string(CYCLE_START_X, CYCLE_Y+2, loops_str);

      floors_cleared_str := tprint("floor=%", game_state.floors_cleared+1);
      draw_string(CYCLE_START_X+8, CYCLE_Y+2, floors_cleared_str);

      flavor := get_goal_flavor_text();
      draw_string(CYCLE_START_X, CYCLE_Y+3, flavor);

      if game_state.level_goal == .COLLECT_COINS {
        coins_left := world.entity_groups[Entity_Kind.COIN].count;
        text := tprint("left=%", coins_left);
        x := (COLS-1-text.count).(s16);
        draw_string(x, CYCLE_Y+3, text);
      } 
      if game_state.level_goal == .KILL_ALL_ENEMIES {
        enemies_left := world.entity_groups[Entity_Kind.ENEMY].count;
        text := tprint("left=%", enemies_left);
        x := (COLS-1-text.count).(s16);
        draw_string(x, CYCLE_Y+3, text);
      }

    } else if game_state.state == .PICKING_LOOP {
      mod_your_loop :: "MOD YOUR LOOP";
      draw_string(CYCLE_START_X, CYCLE_Y-2, mod_your_loop);
      // TODO: 
      // for x: CYCLE_START_X..CYCLE_START_X + mod_your_loop.count {
      //   cell := *buffer[x][CYCLE_Y-2];
      //   cell.shake = true;
      // }
      draw_string(CYCLE_START_X, CYCLE_Y+1, "DONE", ifx game_state.on_back_button then rl.ColorAlpha(rl.GRAY, 100) else rl.BLANK);

      if game_state.modifying_loop_index {
        draw_string(5+CYCLE_START_X, CYCLE_Y-1, "SWAP TO");

        // List all available characters to choose from
        for 0..CharacterType.WIZARD {
          cell := *buffer[5+CYCLE_START_X+it][CYCLE_Y];
          cell.glyph = CHARACTER_GLYPHS[it].(int);
          cell.fg = CHARACTER_COLORS[it];
          cell.bg = rl.GRAY;

          if game_state.desired_character_type == it {
            cell.bg.a = 100;
          } else {
            cell.bg.a = 0;
          }
        }
      }
    }
  }
  else if game_state.state == .MENU {
    prompt := "PRESS SPACE";
    x := (COLS/2)-prompt.count/2-1;
    draw_string(x.(s16), 10, "PRESS SPACE");
  }
}

pick_character_to_end_with :: () {
  POSSIBLE_EXIT_CHARACTERS :: CharacterType.[ .SWIPER, .TINKERER, .DIGGER, .WIZARD ];
  while true {
    maybe_character := POSSIBLE_EXIT_CHARACTERS[random_get() % POSSIBLE_EXIT_CHARACTERS.count.(u64)];
    for game_state.loop {
      if it == maybe_character {
        game_state.reach_end_with = maybe_character;
        return;
      }
    }
  }
}

get_goal_flavor_text :: () -> string {
  if game_state.level_goal == {
    case .REACH_END;
      return "Reach end";
    case .REACH_END_WITH;
      return tprint("Reach end with %", CHARACTER_GLYPHS[game_state.reach_end_with]);
    case .KILL_ALL_ENEMIES;
      return "Enemies lurking...";
    case .COLLECT_COINS;
      return "Find treasures...";
    case;
      return "???";
  }
}

level_completed :: (from_pos: SVector) {
  game_state.state = .TRANSITION;
  game_state.transition_t = 0.0;
  game_state.transition_origin = xy(from_pos.x.(float), from_pos.y.(float));
  game_state.transition_out = true;
  game_state.spawn_level_flag = false;
  game_state.floors_cleared += 1;
  for y : 0..ROWS-1 {
    for x : 0..COLS-1 {
      cell := *buffer[x][y];
      cell.override_flag = false;
      cell.prev_override_flag = false;
    }
  }

  cmd: Command;
  set(*cmd, LevelCompleted.{});
  entity_world_push_command(*world, cmd);

  // Because if we just completed a level with these goals, we know there is a goal and we can remove it
  if game_state.level_goal == .REACH_END || game_state.level_goal == .REACH_END_WITH {
    goal := world.entity_groups[Entity_Kind.GOAL][0];
    entity_world_remove(*world, goal.id);
  }

  // Always remove all coins from the map
  for coin : world.entity_groups[Entity_Kind.COIN] {
    entity_world_remove(*world, coin.id);
  }

  game_state.level_goal = (game_state.level_goal + 1) % (Level_Goal.KILL_ALL_ENEMIES + 1);
  if game_state.level_goal == {
    case .REACH_END;
      create_goal(potential_goal_positions[random_get() % potential_goal_positions.count.(u64)]);
    case .REACH_END_WITH;
      create_goal(potential_goal_positions[random_get() % potential_goal_positions.count.(u64)]);
      pick_character_to_end_with();
  }

  // Move player to start
  player := world.entity_groups[Entity_Kind.PLAYER][0];
  player.pos = xy(1, 1);
  command: Command;
  set(*command, PlayerMove.{ player.pos, player.pos, player });
  entity_world_push_command(*world, command);

  // Reset doors and reset alive enemies to their spawn position
  for *world.entities {
    if it.kind == {
      case .DOOR;
        it.door_open = false;
      case .ENEMY;
        it.pos = it.spawn_pos;
    }
  }

  // Loop thruogh and dice roll new enemies
  for potetial_enemy_positions {
    occupied := false;
    for enemy : world.entity_groups[Entity_Kind.ENEMY] {
      if enemy.pos == it {
        occupied = true;
        break;
      }
    }

    if occupied then continue;

    if random_get_zero_to_one() < CHANCE_OF_ENEMY {
      create_enemy(it);
      entity_world_rebuild(*world);
    }
  }

  // Because if we are on KILL_ALL_ENEMIES goal, we need to ensure there is atleast ONE enemy on the map 
  if game_state.level_goal == .KILL_ALL_ENEMIES && world.entity_groups[Entity_Kind.ENEMY].count == 0 {
    pos := potetial_enemy_positions[random_get() % potetial_enemy_positions.count.(u64)];
    create_enemy(pos);
  }

  // Enemies and players should be out the way here, so all we have to worry about is WALL and FIRE
  if game_state.level_goal == .COLLECT_COINS {
    assert(player.pos == xy(1,1));
    COIN_CHANCE :: .4;
    for pos: potential_coin_positions {
      if random_get_zero_to_one() > COIN_CHANCE continue;
      create_coin(pos);
    }

    entity_world_rebuild(*world);

    if world.entity_groups[Entity_Kind.COIN].count == 0 {
      pos := potential_coin_positions[random_get() % potential_coin_positions.count.(u64)];
      create_coin(pos);
    }
  }
}

transition_system :: (dt: float) {
  if game_state.state != .TRANSITION then return;
  if game_state.transition_out then game_state.transition_t += dt;
  else game_state.transition_t -= dt;

  if game_state.transition_out && game_state.transition_t > 1.1 {
    game_state.transition_out = false;
    game_state.transition_origin = xy(1.0, 1.0);
    
    if game_state.spawn_level_flag {
      create_level();
    }
  }
  if !game_state.transition_out && game_state.transition_t < 0.0 {
    if game_state.spawn_level_flag {
      game_state.state = .PICKING_LOOP;
      game_state.editing_loop_index = 0;
      game_state.modifying_loop_index = false;
    } else {
      game_state.state = .PLAYING;
    }         
    for y : 0..ROWS-1 {
      for x : 0..COLS-1 {
        cell := *buffer[x][y];
        cell.override_flag = false;
        cell.prev_override_flag = false;
      }
    }
  }
}

update_player_light_system :: (dt: float) {
  move_number_towards :: (curr: s16, goal: s16) -> s16 {
    if curr < goal {
      return curr + 1;
    }else {
      return curr - 1;
    }
  }
  
  if game_state.state == .PICKING_LOOP && game_state.player_light_str != COLS*4 {
    game_state.light_t += dt;
    if game_state.light_t > 0.02 {
      game_state.light_t = 0;
      game_state.player_light_str = move_number_towards(game_state.player_light_str, COLS*2); 
      cmd: Command;
      set(*cmd, LightUpdate.{});
      entity_world_push_command(*world, cmd);
    }
  }else if game_state.state == .PLAYING && game_state.player_light_str != 12 {
    game_state.light_t += dt;
    if game_state.light_t > 0.02 {
      game_state.light_t = 0;
      game_state.player_light_str = move_number_towards(game_state.player_light_str, 12); 
      cmd: Command;
      set(*cmd, LightUpdate.{});
      entity_world_push_command(*world, cmd);
    }
  }
}

vision_render_system :: () {
  if game_state.standing_on_vision {
    // Light up all goals
    if game_state.level_goal == {
      case .REACH_END; #through;
      case .REACH_END_WITH;
        for goal : world.entity_groups[Entity_Kind.GOAL] {
          cell := *buffer[goal.pos.x][goal.pos.y];
          cell.fg.a = 255;
        }
      case .COLLECT_COINS;
        for coin : world.entity_groups[Entity_Kind.COIN] {
          cell := *buffer[coin.pos.x][coin.pos.y];
          cell.fg.a = 255;
        }
      case .KILL_ALL_ENEMIES;
        for enemy : world.entity_groups[Entity_Kind.ENEMY] {
          cell := *buffer[enemy.pos.x][enemy.pos.y];
          cell.fg.a = 255;
        }        
    }
  }
}

transition_render_system :: () {
  if game_state.state != .TRANSITION then return;

  MAX_DIST_BETWEEN_TWO_CELLS :: #run distance(xy(0.0, 0.0), xy(COLS.(float), UI_START_Y));

  for y : 0..UI_START_Y-1 {
    for x : 0..COLS-1 {
      cell := *buffer[x][y];

      if game_state.transition_out {
        if cell.override_flag {
          if random_get_zero_to_one() < 0.1 {
            cell.override_glyph = cast(int)(32 + random_get() % (126-32));
          }
        }else {
          dist := distance(xy(x.(float),y.(float)), game_state.transition_origin);
          if dist < MAX_DIST_BETWEEN_TWO_CELLS * game_state.transition_t {
            cell.override_flag = true;  
          }
        }
      }else {
        if cell.override_flag {
          // Check if its time to disable the override
          dist := distance(xy(x.(float),y.(float)), game_state.transition_origin);
          if dist > MAX_DIST_BETWEEN_TWO_CELLS * game_state.transition_t {
            cell.override_flag = false;  
          }
          if random_get_zero_to_one() < 0.1 {
            cell.override_glyph = cast(int)(32 + random_get() % (126-32));
          }
        }
      }

      if cell.override_flag != cell.prev_override_flag {
        cell.override_fg = color_random();
        cell.override_bg.a = 0;
        cell.override_glyph = cast(int)(32 + random_get() % (126-32));
      }

      cell.prev_override_flag = cell.override_flag;
    }
  }
}

// System that runs only in the menu
// Should allow the player to press start which begins the game
menu_system :: (dt: float) {
  if game_state.state != .MENU then return;
  
  if rl.IsKeyPressed(.KEY_SPACE) {
    // Initalise a transition
    game_state.state = .TRANSITION;
    game_state.transition_t = 0.0;
    game_state.transition_origin = xy(COLS/2.0, ROWS/2.0);
    game_state.transition_out = true;
    game_state.spawn_level_flag = true;
    for y : 0..ROWS-1 {
      for x : 0..COLS-1 {
        cell := *buffer[x][y];
        cell.override_flag = false;
        cell.prev_override_flag = false;
      }
    }
  }
}

level_complete_system :: (dt: float) {
  for world.commands {
    if isa(it, LevelCompleted) {

    }
    else if isa(it, EnemyKilled) {
      enemies_left := world.entity_groups[Entity_Kind.ENEMY].count;
      if game_state.level_goal == .KILL_ALL_ENEMIES && enemies_left == 0 {
        player := world.entity_groups[Entity_Kind.PLAYER][0];
        level_completed(player.pos);
      }
    }
  }
}

clear_play_area :: () {
  // Loop over every tile in the gameplay area (not the UI).
  for y: 0..GAME_AREA_SIZE-1 {
    for x: 0..COLS-1 {
      cell := *buffer[x][y];
      // Reset the cell to be completely empty.
      cell.glyph = " "[0];
      cell.fg = rl.BLANK; // Transparent
      cell.bg = rl.BLANK;
      cell.shake = false;
    }
  }
}

draw_given_up_ui :: () {
  // --- Calculate the center of the screen ---
  center_x := COLS / 2;
  center_y := ROWS / 2;

  // --- Main Title ---
  title := "YOU GAVE UP";
  title_x := center_x - (title.count / 2);
  // Position the entire text block so it's centered. We'll start the title
  // a few lines above the absolute center.
  start_y := center_y - 4;
  draw_string(title_x.(s16), start_y, title, rl.BLANK);

  // --- Final Stats ---
  floors_str := tprint("Floors Cleared: %", game_state.floors_cleared);
  loops_str  := tprint("Total Loops: %", game_state.loops);
  
  floors_x := center_x - (floors_str.count / 2);
  loops_x  := center_x - (loops_str.count / 2);

  // Draw the stats two lines below the title
  draw_string(floors_x.(s16), start_y + 2, floors_str, rl.BLANK);
  draw_string(loops_x.(s16), start_y + 3, loops_str, rl.BLANK);

  // --- Prompt to restart ---
  prompt := "Restart the game to play again...";
  prompt_x := center_x - (prompt.count / 2);
  // Draw the prompt a few lines below the stats
  draw_string(prompt_x.(s16), start_y + 6, prompt, rl.BLANK);
}

main :: () {
  apollot_time := current_time_consensus();
  random_seed(to_calendar(apollot_time).millisecond.(u64));

  rl.InitWindow(COLS * tile_w, ROWS * tile_h, "JaiJam - Loop Gang");
  rl.SetTargetFPS(60);
  font := rl.LoadFontEx("./CozetteCrossedSevenVector.ttf", tile_w, null, 0);

  entity_world_init(*world);
  array_add(*world.update_systems, kill_tile_system);
  array_add(*world.update_systems, glyph_basic_update_system);
  array_add(*world.render_systems, glyph_basic_render_system);
  array_add(*world.render_systems, render_ui_system);
  array_add(*world.update_systems, menu_system);
  array_add(*world.update_systems, update_player_light_system);
  array_add(*world.update_systems, level_complete_system);

  array_add(*world.update_systems, transition_system);
  array_add(*world.render_systems, transition_render_system);
  array_add(*world.render_systems, vision_render_system);

  create_player();

  entity_world_rebuild(*world);

  // Init the loop variable with a bunch of character states...
  game_state.loop[0] = CharacterType.SWIPER;
  game_state.loop[1] = CharacterType.TINKERER;
  game_state.loop[2] = CharacterType.MARTYR;
  game_state.loop[3] = CharacterType.DIGGER;

  // Push initial move command so every glyph gets correctly lit up
  command: Command;
  player := world.entity_groups[Entity_Kind.PLAYER][0];
  set(*command, PlayerMove.{ player.pos, player.pos, player });
  entity_world_push_command(*world, command);

  rl.GuiSetStyle(0, rl.GuiDefaultProperty.TEXT_SIZE.(s32), 20);
  game_state.selected_point.x = -1;

  while !rl.WindowShouldClose() {
    memory_visualizer_per_frame_update();

    reset_temporary_storage();

    dt := rl.GetFrameTime();
    entity_world_update(*world, dt);

    clear_buffer();
    entity_world_render(*world);

    if game_state.state == .GIVEN_UP {
      clear_play_area();
      draw_given_up_ui();
    }

    shake_offset := Vector2.{ 0, 0 };
    if game_state.shake_duration > 0 {
      game_state.shake_duration -= dt;
      
      // Convert [0, 1] to [-1, 1] and multiple by intensity
      shake_offset.x = ((random_get_zero_to_one() * 2.0) - 1.0) * game_state.shake_intensity;
      shake_offset.y = ((random_get_zero_to_one() * 2.0) - 1.0) * game_state.shake_intensity;

      if game_state.shake_duration <= 0 then game_state.shake_duration = 0;
    }

    rl.BeginDrawing();
      rl.ClearBackground(rl.BLACK);
      // Draw the buffer
      for y : 0..ROWS-1 {
        for x : 0..COLS-1 {
          cell := buffer[x][y];

          // Respect the override
          bg := cell.bg;
          fg := cell.fg;
          glyph := cell.glyph;
          if cell.override_flag {
            bg = cell.override_bg;
            fg = cell.override_fg;
            glyph = cell.override_glyph;
          }

          INDIVIDUAL_SHAKE_INTENSITY :: 2;
          individual_shake_offset := Vector2.{ 0, 0 };
          if cell.shake {
            individual_shake_offset.x = ((random_get_zero_to_one() * 2.0) - 1.0) * INDIVIDUAL_SHAKE_INTENSITY;
            individual_shake_offset.y = ((random_get_zero_to_one() * 2.0) - 1.0) * INDIVIDUAL_SHAKE_INTENSITY;
          } 

          local_offset := shake_offset + individual_shake_offset;
          if y >= UI_START_Y then local_offset = xy(0.0, 0.0);
              
          // We now apply screen shake here
          rect_x := (x * tile_w) + local_offset.x.(s16);
          rect_y := (y * tile_h) + local_offset.y.(s16);
          rl.DrawRectangle(rect_x, rect_y, tile_w, tile_h, bg);

          // Draw the glyph
          glyph_index := rl.GetGlyphIndex(font, glyph.(s32));
          rec := font.recs[glyph_index];
          
          pos_x := (x * tile_w) + (tile_w - rec.width)  / 2;
          pos_y := (y * tile_h) + (tile_h - rec.height) / 2;
          
          // We now apply screen shake here
          final_pos_x := pos_x.(float) + local_offset.x;
          final_pos_y := pos_y.(float) + local_offset.y;
          pos := Vector2.{ final_pos_x, final_pos_y };
          
          rl.DrawTextureRec(font.texture, rec, pos, fg);
        }
      }

      edit_system(dt);

    rl.EndDrawing();
  }
}

#import "Random";
#import "Math";
#import "Basic"()(MEMORY_DEBUGGER=true);
#import "File";
#import "Tagged_Union";
Table :: #import "Hash_Table";
rl :: #import "raylib";

#load "util.jai";
#load "levels.jai";
#load "ascii-math.jai";