
RELEASE_BUILD :: false;

GAME_AREA_SIZE :: (2 * SEGMENT_SIZE); // 43
UI_HEIGHT :: 7;

COLS: s16 : GAME_AREA_SIZE; // 43, for a square playable area
ROWS: s16 : GAME_AREA_SIZE + UI_HEIGHT; // 50, total window height in tiles

UI_START_Y :: GAME_AREA_SIZE; // 43, UI starts right after the game area

tile_w: s16 = 20;
tile_h: s16 = 20;

PLAYER_COLOR :: rl.Color.{ 255, 0, 255, 255 };
GOAL_COLOR :: rl.Color.{ 255, 215, 0, 255 };
NORMAL_PLAYER_LIGHT_STR :: 9.0;
ENHANCED_PLAYER_LIGHT_STR :: COLS.(float);

STANDING_ON_WALL_BG :: rl.Color.{ 100, 100, 100, 100 };

FIRE_COLOR_1 :: rl.Color.{ 255,90,0,50 };
FIRE_COLOR_2 :: rl.Color.{ 255,154,0,50 };

CYCLE_START_X :: 3;
CYCLE_Y :: UI_START_Y + 3;

State :: enum {
  TRANSITION;
  PLAYING;
  PICKING_LOOP;
  MENU;
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
  current_loop_idx: int = 0;
  iterations: int = 0;

  player_light_strength: float = NORMAL_PLAYER_LIGHT_STR;
  prev_light_strength: s16 = NORMAL_PLAYER_LIGHT_STR.(s16);
  curr_light_strength: s16 = NORMAL_PLAYER_LIGHT_STR.(s16);

  shake_duration: float = 0.0;
  shake_intensity: float = 0.0;
  transition_t: float = 0.0;
  transition_origin: Vector2;
  spawn_level_flag: bool = false;

  transition_out: bool;

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
  // WIZARD - ranged based attack & also controls levers
}

/// --- BEGIN ENTITY 

PlayerMove :: struct {
  old_pos: SVector;
  new_pos: SVector;
  player: *Entity;
}

PlayerDied :: struct {}
LightUpdate :: struct {}

Command :: Tagged_Union(PlayerMove, PlayerDied, LightUpdate);

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

  fire_t: float;
}

NUM_ENTITY_KIND :: 10;
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
  goal.glyph = 88;

  goal.update_proc = goal_update;

  entity_world_add(*world, goal);
}

create_wall :: (pos: SVector) {
  wall: Entity;

  wall.kind = .WALL;

  wall.pos = pos;
  wall.color = color(100, 100, 100, 255);
  wall.glyph = 35;

  entity_world_add(*world, wall);
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
  dead_martyr.color = PLAYER_COLOR;
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

    for world.commands {
      player_move := isa(it, PlayerMove);
      if player_move {
        // The enemy doesn't react to the swiper character
        if player_move.player.character_type == .SWIPER {
          return;
        }

        sees_player, t := has_line_of_sight(enemy, player_move.player, 8);
        if sees_player {
          enemy.color = color(255, 20, 50, enemy.color.a);
        } else {
          enemy.color = color(90, 90, 90, enemy.color.a);
        }

        // Move?
        enemy.move_tick += 1;
        if enemy.move_tick % 2 == 0 && has_line_of_sight(enemy, player_move.player, 8) {
          // Check if we're neighbouring to the player, if so lets go ahead and kill them 
          if is_direct_neighbour(player_move.new_pos, enemy.pos) {
            cmd: Command;
            set(*cmd, PlayerDied.{});
            entity_world_push_command(*world, cmd);
          }else {
            move_enemy_towards_player(player_move.player, enemy);
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

create_player :: () {
  set_player_pos :: (player: *Entity, x: s16, y: s16) {
    command: Command;
    set(*command, PlayerMove.{ player.pos, xy(x, y), player });
    entity_world_push_command(*world, command);

    player.pos = xy(x, y);
  }

  // Return true or false depending on if we successfully moved or not
  move_player :: (player: *Entity, dx: s16, dy: s16) -> bool {
    new_pos := xy(player.pos.x + dx, player.pos.y + dy);
    // Check for wall
    walkable, kind := is_walkable(new_pos);
    if kind == .KILL_TILE {
      // Mechanic "Martyrs can cover up KILL TILES"
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
      command: Command;
      set(*command, PlayerDied.{});
      entity_world_push_command(*world, command); 
      return false;
    }
    if player.character_type == .SWIPER && kind == .ENEMY {
      // Yo! The swiper has moved into an enemy, kill it and kill the player
      entity_world_remove(*world, find_entity_at(new_pos).id);
      command: Command;
      set(*command, PlayerDied.{});
      entity_world_push_command(*world, command); 
      return false;
    }
    if player.character_type == .TINKERER && kind == .LEVER {
      open_closest_door(new_pos);
    }
    if player.character_type == .DIGGER && kind == .DIGGABLE {
      entity_world_remove(*world, find_entity_at(new_pos).id);
    }
    
    if (!game_state.edit_mode && !walkable) || !is_valid(new_pos) || kind == .ENEMY then return false;

    set_player_pos(player, new_pos.x, new_pos.y);

    if player.character_type == .SWIPER && is_zero(player.swiping_dir) {
      player.swiping_dir = xy(dx, dy);
      player.swipe_counter = 0;
    }

    return true;
  }

  is_explodeable :: (entity: *Entity) -> bool {
    return entity.kind == .ENEMY; // TODO:
  }

  martyr_explode :: () {
    for x: -1..1 {
      for y: -1..1 {
        // TODO: Remove explodable tiles
      }
    }
  }
 
  update_player :: (player: *Entity, dt: float) {
    player.character_type = game_state.loop[game_state.current_loop_idx];
    player.glyph = CHARACTER_GLYPHS[player.character_type].(int);

    if game_state.state == .PICKING_LOOP {
      // This is a godamn shitshow... UI!!!
      if game_state.modifying_loop_index {
        if rl.IsKeyPressed(.KEY_D) {
          game_state.desired_character_type += 1;
        }
        else if rl.IsKeyPressed(.KEY_A) {
          game_state.desired_character_type -= 1;
        } 
        game_state.desired_character_type = clamp(game_state.desired_character_type, 0, CharacterType.DIGGER);

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
    if game_state.state == .PLAYING {
      SWIPE_MOVE_FREQ :: 0.1; // Seconds
      if player.character_type == .SWIPER && !is_zero(player.swiping_dir) {
        player.swipe_counter += dt;
        if player.swipe_counter > SWIPE_MOVE_FREQ {
          player.swipe_counter = 0;
          finished := !move_player(player, player.swiping_dir.x, player.swiping_dir.y);
          if finished {
            player.swiping_dir = xy(0, 0);
          }   
        }
      }else {
        if rl.IsKeyPressed(.KEY_D) move_player(player, 1, 0);
        if rl.IsKeyPressed(.KEY_A) move_player(player, -1, 0);
        if rl.IsKeyPressed(.KEY_S) move_player(player, 0, 1);
        if rl.IsKeyPressed(.KEY_W) move_player(player, 0, -1);

        if rl.IsKeyPressed(.KEY_SPACE) && player.character_type == .TINKERER {
          create_wall(player.pos);
        }

        if rl.IsKeyPressed(.KEY_SPACE) && player.character_type == .MARTYR {
          martyr_explode();
        }
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

      if game_state.curr_light_strength != game_state.prev_light_strength {
        cmd: Command;
        set(*cmd, LightUpdate);
        entity_world_push_command(*world, cmd);
      }

      // Process death
      for world.commands {
        if isa(it, PlayerDied) {
          game_state.current_loop_idx = (game_state.current_loop_idx+1) % game_state.loop.count;
          game_state.iterations += 1;
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
    player_cell.fg = PLAYER_COLOR;
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
  
  print("BEGIN LEVEL");

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
  return kind == .WALL || kind == .ENEMY || kind == .KILL_TILE || kind == .DOOR || kind == .LEVER || kind == .DEAD_MARTYR || kind == .DIGGABLE || kind == .GOAL;
}

glyph_basic_update_system :: (dt: float) {
  for cmd : world.commands {
    player_move := isa(cmd, PlayerMove);
    // light_update := isa(cmd, LightUpdate);
    if player_move {
      for *world.entities {
        if is_basic_rendered(it.kind) {
          it.color.a = get_lit_alpha(player_move.player.pos, it.pos, game_state.curr_light_strength);

          // Dead martyrs light up the world
          for dead_martyr : world.entity_groups[Entity_Kind.DEAD_MARTYR] {
            new_alpha := it.color.a.(u64) + get_lit_alpha(dead_martyr.pos, it.pos, 6).(u64);
            max_alpha: u64 = 255;
            new_alpha = min(max_alpha, new_alpha);
            it.color.a = new_alpha.(u8);
          }

          for fire : world.entity_groups[Entity_Kind.FIRE] {
            new_alpha := it.color.a.(u64) + get_lit_alpha(fire.pos, it.pos, 6).(u64);
            max_alpha: u64 = 255;
            new_alpha = min(max_alpha, new_alpha);
            it.color.a = new_alpha.(u8);
          }

          it.color.a = (it.color.a * it.alpha_modifier).(u8);
        }
      }
    }
  }
}

render_ui_system :: () {
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
      cell.fg = PLAYER_COLOR;
      cell.bg = rl.GRAY;

      if game_state.state == .PICKING_LOOP && game_state.editing_loop_index == it && !game_state.on_back_button {
        cell.bg.a = 100;
      }else {
        cell.bg.a = 0;
      }
    }

    if game_state.state == .PLAYING {
      draw_string(CYCLE_START_X, CYCLE_Y-2, "R=next");
      iterations_str := tprint("loops=%", game_state.iterations);
      draw_string(CYCLE_START_X, CYCLE_Y+2, iterations_str);
    } else if game_state.state == .PICKING_LOOP {
      draw_string(CYCLE_START_X, CYCLE_Y-2, "MOD YOUR LOOP");
      draw_string(CYCLE_START_X, CYCLE_Y+1, "DONE", ifx game_state.on_back_button then rl.ColorAlpha(rl.GRAY, 100) else rl.BLANK);

      if game_state.modifying_loop_index {
        // List all available characters to choose from
        for 0..CharacterType.DIGGER {
          cell := *buffer[5+CYCLE_START_X+it][CYCLE_Y];
          cell.glyph = CHARACTER_GLYPHS[it].(int);
          cell.fg = PLAYER_COLOR;
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

level_completed :: (from_pos: SVector) {
  game_state.state = .TRANSITION;
  game_state.transition_t = 0.0;
  game_state.transition_origin = xy(from_pos.x.(float), from_pos.y.(float));
  game_state.transition_out = true;
  game_state.spawn_level_flag = false;
  for y : 0..ROWS-1 {
    for x : 0..COLS-1 {
      cell := *buffer[x][y];
      cell.override_flag = false;
      cell.prev_override_flag = false;
    }
  }
}

transition_system :: (dt: float) {
  if game_state.state != .TRANSITION then return;
  if game_state.transition_out then game_state.transition_t += dt;
  else game_state.transition_t -= dt;

  if game_state.transition_out && game_state.transition_t > 1.1 {
    game_state.transition_out = false;
    // Reset player here
    player := world.entity_groups[Entity_Kind.PLAYER][0];
    player.pos = xy(1, 1);
    game_state.transition_origin = xy(player.pos.x.(float), player.pos.y.(float));

    command: Command;
    set(*command, PlayerMove.{ player.pos, player.pos, player });
    entity_world_push_command(*world, command);
    
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

  array_add(*world.update_systems, transition_system);
  array_add(*world.render_systems, transition_render_system);

  // Fill up the world
  create_player();
  // create_level();

  entity_world_rebuild(*world);

  // Init the loop variable with a bunch of character states...
  game_state.loop[0] = CharacterType.DIGGER;
  game_state.loop[1] = CharacterType.MARTYR;
  game_state.loop[2] = CharacterType.MARTYR;
  game_state.loop[3] = CharacterType.SWIPER;

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

          local_offset := shake_offset;
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

#load "levels.jai";
#load "ascii-math.jai";