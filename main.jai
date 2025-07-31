
RELEASE_BUILD :: false;

UI_START_Y :: 41 - 6;

COLS: s16 : 41;
ROWS: s16 : 41;

tile_w: s16 = 24;
tile_h: s16 = 24;

PLAYER_COLOR :: rl.Color.{ 255, 0, 255, 255 };
NORMAL_PLAYER_LIGHT_STR :: 9.0;
ENHANCED_PLAYER_LIGHT_STR :: COLS.(float);

STANDING_ON_WALL_BG :: rl.Color.{ 100, 100, 100, 100 };

GameState :: struct {
  glitcher_counter: float = 0.0;

  // Used for editing
  edit_mode: bool = false;
  selected_point: SVector;
  connecting_to_door: bool = false;

  loop: [4]CharacterType;
  current_loop_idx: int = 0;
  iterations: int = 0;

  player_light_strength: float = NORMAL_PLAYER_LIGHT_STR;
  prev_light_strength: s16;
  curr_light_strength: s16;
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

buffer: [COLS][ROWS]Cell;

CharacterType :: enum {
  SWIPER :: 0;
  TINKERER :: 1;
  MARTYR :: 2;
  DIGGER :: 3;
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
  
  door_connections: [..]SVector;

  door_open: bool;

  character_type: CharacterType;
  swiping_dir: SVector;
  swipe_counter: float;
}

NUM_ENTITY_KIND :: 9;
Entity_Kind :: enum u32 {
  PLAYER;
  ENEMY;
  WALL;
  DOOR;
  LEVER;
  KILL_TILE;
  DEAD_MARTYR;
  MOD_STATION;
  DIGGABLE;
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

create_mod_station :: (pos: SVector) {
  e: Entity;
  e.kind = .MOD_STATION;
  e.pos = pos;
  e.glyph = 43;
  e.color = color(0, 255, 100, 255);

  entity_world_add(*world, e);
}

create_wall :: (pos: SVector, is_diggable := false) {
  wall: Entity;

  wall.kind = .WALL;

  wall.pos = pos;
  wall.color = color(100, 100, 100, 255);
  wall.glyph = 35;

  if is_diggable {
    wall.color = color(79, 58, 43, 255);
    wall.kind = .DIGGABLE;      
  }

  entity_world_add(*world, wall);
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

create_dead_martyr :: (pos_x: s16, pos_y: s16) {
  dead_martyr: Entity;
  dead_martyr.kind = .DEAD_MARTYR;

  dead_martyr.pos = xy(pos_x, pos_y);
  dead_martyr.color = PLAYER_COLOR;
  dead_martyr.alpha_modifier = 0.25;
  dead_martyr.glyph = GLYPH.MARTYR.(int);

  entity_world_add(*world, dead_martyr);
}

create_kill_tile :: (pos_x: s16, pos_y: s16) {
  kill_tile: Entity;
  kill_tile.kind = .KILL_TILE;

  kill_tile.pos = xy(pos_x, pos_y);
  kill_tile.color = color_random();
  kill_tile.glyph = cast(int)(32 + random_get() % (126-32));

  entity_world_add(*world, kill_tile);
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
    // Did we die? TODO: This will depend on the current state, certain characters won't die etc
    if kind == .KILL_TILE {
      // If we're a MARTYR character, we should remove the KILL_TILE and replace it with a dead martyr that we can walk over
      if player.character_type == .MARTYR {
        entity_world_remove(*world, find_entity_at(new_pos).id);
        create_dead_martyr(new_pos.x, new_pos.y);
      }

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
      lever := find_entity_at(new_pos);
      for lever.door_connections {
        door := find_entity_at(it);
        door.door_open = true;
      }
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
 
  update_player :: (player: *Entity, dt: float) {
    player.character_type = game_state.loop[game_state.current_loop_idx];
    player.glyph = CHARACTER_GLYPHS[player.character_type].(int);

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
    }

    if rl.IsKeyPressed(.KEY_R) {
      cmd: Command;
      set(*cmd, PlayerDied.{});
      entity_world_push_command(*world, cmd);
    }

    // Are we currently standing on a mod station tile? 
    on_mod_station := false;
    for mod_station : world.entity_groups[Entity_Kind.MOD_STATION] {
      if mod_station.pos == player.pos {
        on_mod_station = true;
        break;
      }
    }
    game_state.prev_light_strength = game_state.player_light_strength.(s16);
    desired_light_strength: float = ifx on_mod_station then ENHANCED_PLAYER_LIGHT_STR else NORMAL_PLAYER_LIGHT_STR;
    game_state.player_light_strength = lerp(game_state.player_light_strength, desired_light_strength, 1.0 * dt);
    game_state.curr_light_strength = game_state.player_light_strength.(s16);

    if game_state.curr_light_strength != game_state.prev_light_strength {
      print("light update!\n");
      cmd: Command;
      set(*cmd, LightUpdate);
      entity_world_push_command(*world, cmd);
    }

    // Process death
    for world.commands {
      if isa(it, PlayerDied) {
        game_state.current_loop_idx = (game_state.current_loop_idx+1) % game_state.loop.count;
        game_state.iterations += 1;
        set_player_pos(player, 1, 1);
      }
    }

#if !RELEASE_BUILD {
    if rl.IsKeyPressed(.KEY_C) {
      create_wall(xy(player.pos.x, player.pos.y)); // Give birth, right here, right now
    }
    if rl.IsKeyPressed(.KEY_TAB) then game_state.edit_mode = !game_state.edit_mode;
    if rl.IsKeyPressed(.KEY_P) then print_level();
}
  }

  render_player :: (player: *Entity) {
    player_cell := *buffer[player.pos.x][player.pos.y];
    player_cell.fg = PLAYER_COLOR;
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

connect_lever_to_door :: (lever_pos: SVector, door_pos: SVector) {
  lever := find_entity_at(lever_pos);
  assert(lever != null && lever.kind == .LEVER);

  door := find_entity_at(door_pos);
  assert(door != null && door.kind == .DOOR);

  array_add(*lever.door_connections, door_pos);
}

print_level :: () {
  builder: String_Builder;
  init_string_builder(*builder);
  for world.entity_groups[Entity_Kind.ENEMY] {
    append(*builder, tprint("create_enemy(xy(%, %));\n", it.pos.x, it.pos.y));
  }
  for world.entity_groups[Entity_Kind.WALL] {
    append(*builder, tprint("create_wall(xy(%, %));\n", it.pos.x, it.pos.y));
  }
  for world.entity_groups[Entity_Kind.KILL_TILE] {
    append(*builder, tprint("create_kill_tile(%, %);\n", it.pos.x, it.pos.y));
  }
  for world.entity_groups[Entity_Kind.DOOR] {
    append(*builder, tprint("create_door(xy(%, %));\n", it.pos.x, it.pos.y));
  }
  for world.entity_groups[Entity_Kind.LEVER] {
    append(*builder, tprint("create_lever(xy(%, %));\n", it.pos.x, it.pos.y));
    for door_pos : it.door_connections {
      append(*builder, tprint("connect_lever_to_door(xy(%, %), xy(%, %));\n", it.pos.x, it.pos.y, door_pos.x, door_pos.y));
    }
  }
  for world.entity_groups[Entity_Kind.MOD_STATION] {
    append(*builder, tprint("create_mod_station(xy(%, %));\n", it.pos.x, it.pos.y));
  }

  // Create connection between the levers and doors!

  file_name := tprint("./level.in");
  file, success := file_open(file_name, true);
  assert(success, "Failed to open level file for writing!");
  defer file_close(*file);
  file_write(*file, *builder);

  print("Saved level!\n");
}

kill_tile_system :: (dt: float) {
  KILL_TILE_UPDATE :: 0.8;   
  game_state.glitcher_counter += dt;
  if game_state.glitcher_counter >= KILL_TILE_UPDATE {
    for world.entity_groups[Entity_Kind.KILL_TILE] {
      if random_get() % 100 < 10 {
        it.glyph = cast(int)(32 + random_get() % (126-32));
      }
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
  
  if rl.IsMouseButtonPressed(.MOUSE_BUTTON_LEFT) && (game_state.selected_point.x == -1 || game_state.connecting_to_door) {
    mouse_pos := rl.GetMousePosition();
    mouse_pos.x /= rl.GetScreenWidth();
    mouse_pos.y /= rl.GetScreenHeight();

    grid_pos: SVector;
    grid_pos.x = (mouse_pos.x * COLS).(s16); 
    grid_pos.y = (mouse_pos.y * ROWS).(s16); 

    // Check if we're assigning door to a lever
    if game_state.connecting_to_door {
      maybe_door := find_entity_at(grid_pos);
      if maybe_door != null && maybe_door.kind == .DOOR {
        lever := find_entity_at(game_state.selected_point);
        array_add(*lever.door_connections, grid_pos);
        return;
      }

      game_state.connecting_to_door = false;
    }

    game_state.selected_point = grid_pos;
  }

  if rl.IsMouseButtonPressed(.MOUSE_BUTTON_RIGHT) {
    game_state.selected_point.x = -1;
  }

  if game_state.connecting_to_door {
    rl.GuiLabel(rl.Rectangle.{0, 50, 100, 50} , "CONNECTING DOOR!");
  }

  if rl.IsKeyDown(.KEY_LEFT_ALT) {
    e := find_entity_at(game_state.selected_point);
    height := rl.GetScreenHeight().(float);
    if e != null {
      str_buffer := to_c_string(tprint("ID = %, Kind = %", e.id, e.kind));
      defer free(str_buffer);
      rl.GuiLabel(rl.Rectangle.{10, height-100, 200, 50}, str_buffer);
      if rl.GuiButton(rl.Rectangle.{10, height-50, 100, 50}, "Delete") {
        entity_world_remove(*world, e.id);
        return;
      }
      if e.kind == .DOOR {
        if rl.GuiButton(rl.Rectangle.{110, height-50, 100, 50}, "CLOPEN") {
          e.door_open = !e.door_open;
          return;
        }
      }
      if e.kind == .LEVER {
        if rl.GuiButton(rl.Rectangle.{110, height-50, 100, 50}, "CONNECT") {
          game_state.connecting_to_door = true;
          return;
        }
        if rl.GuiButton(rl.Rectangle.{220, height-50, 100, 50}, "PULL") {
          for e.door_connections {
            door := find_entity_at(it);
            assert(door != null && door.kind == .DOOR);
            door.door_open = true;
          }
          return;
        }
        rl.GuiLabel(rl.Rectangle.{ 330, height-50, 100, 50 }, to_c_string(tprint("doors = %", e.door_connections.count)));
      }
    }else if game_state.selected_point.x != -1 {
      if rl.GuiButton(rl.Rectangle.{10+80*0, height-50, 80, 30}, "WALL") {
        create_wall(game_state.selected_point);
        game_state.selected_point.x = -1;
      }
      if rl.GuiButton(rl.Rectangle.{10+80*1, height-50, 80, 30}, "DOOR") {
        create_door(game_state.selected_point);
        game_state.selected_point.x = -1;
      }
      if rl.GuiButton(rl.Rectangle.{10+80*2, height-50, 80, 30}, "LEVER") {
        create_lever(game_state.selected_point);
        game_state.selected_point.x = -1;
      }
      if rl.GuiButton(rl.Rectangle.{10+80*3, height-50, 80, 30}, "KILL") {
        create_kill_tile(game_state.selected_point.x, game_state.selected_point.y);
        game_state.selected_point.x = -1;
      }
      if rl.GuiButton(rl.Rectangle.{10+80*4, height-50, 80, 30}, "ENEMY") {
        create_enemy(game_state.selected_point);
        game_state.selected_point.x = -1;
      }
      if rl.GuiButton(rl.Rectangle.{10+80*5, height-50, 80, 30}, "MOD") {
        create_mod_station(game_state.selected_point);
        game_state.selected_point.x = -1;
      }
      if rl.GuiButton(rl.Rectangle.{10+80*6, height-50, 80, 30}, "DIGGABLE") {
        create_wall(game_state.selected_point, true);
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

  player := world.entity_groups[Entity_Kind.PLAYER][0];
  for world.entity_groups[Entity_Kind.WALL] {
    if it.pos == player.pos {
      cell := *buffer[it.pos.x][it.pos.y];
      cell.bg = STANDING_ON_WALL_BG;
      break;
    }
  }
}

is_basic_rendered :: (kind: Entity_Kind) -> bool {
  return kind == .WALL || kind == .ENEMY || kind == .KILL_TILE || kind == .DOOR || kind == .LEVER || kind == .DEAD_MARTYR || kind == .MOD_STATION || kind == .DIGGABLE;
}

glyph_basic_update_system :: (dt: float) {
  for cmd : world.commands {
    player_move := isa(cmd, PlayerMove);
    light_update := isa(cmd, LightUpdate);
    if player_move || light_update {
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

          it.color.a = (it.color.a * it.alpha_modifier).(u8);
        }
      }
    }
  }
}

render_ui_system :: () {
  draw_string :: (start_x: s16, y: s16, str: string) {
    x := start_x;
    for i : 0..str.count-1 {
      c := str[i];
      cell := *buffer[x][y];
      cell.glyph = c;
      cell.fg = rl.WHITE;
      x += 1;
    }
  }

  y := UI_START_Y;
  glyph := 126;
  for x: 0..COLS-1 {
    cell := *buffer[x][y];
    cell.glyph = glyph;
    cell.fg = rl.WHITE;
  }

  for x: 0..COLS-1 {
    for y: UI_START_Y..ROWS-1 {
      cell := *buffer[x][y];
      cell.bg = rl.WHITE;
      cell.bg.a = 10;
    }
  }

  CYCLE_START_X :: 3;
  CYCLE_Y :: UI_START_Y + 3;
  
  // Draw the indicator on the current loop character
  cell := *buffer[CYCLE_START_X + game_state.current_loop_idx][CYCLE_Y+1];
  cell.glyph = 94;
  cell.fg = rl.WHITE;

  // Draw the current character
  for 0..3 {
    cell = *buffer[CYCLE_START_X+it][CYCLE_Y];
    cell.glyph = CHARACTER_GLYPHS[game_state.loop[it]].(int);
    cell.fg = PLAYER_COLOR;
  }

  draw_string(CYCLE_START_X, CYCLE_Y-2, "R=next");
  iterations_str := tprint("loops=%", game_state.iterations);
  draw_string(CYCLE_START_X, CYCLE_Y+2, iterations_str);
}

main :: () {
  rl.InitWindow(COLS * tile_w, ROWS * tile_h, "JaiJam - Loop Gang");
  rl.SetTargetFPS(60);
  font := rl.LoadFontEx("./font.ttf", tile_w, null, 0);

  entity_world_init(*world);
  array_add(*world.update_systems, kill_tile_system);
  array_add(*world.update_systems, glyph_basic_update_system);
  array_add(*world.render_systems, glyph_basic_render_system);
  array_add(*world.render_systems, render_ui_system);

  // Fill up the world
  create_player();
  create_level();

  entity_world_rebuild(*world);

  // Init the loop variable with a bunch of character states...
  game_state.loop[0] = CharacterType.DIGGER;
  game_state.loop[1] = CharacterType.MARTYR;
  game_state.loop[2] = CharacterType.MARTYR;
  game_state.loop[3] = CharacterType.TINKERER;

  // Push initial move command so every glyph gets correctly lit up
  command: Command;
  player := world.entity_groups[Entity_Kind.PLAYER][0];
  set(*command, PlayerMove.{ player.pos, player.pos, player });
  entity_world_push_command(*world, command);

  rl.GuiSetStyle(0, rl.GuiDefaultProperty.TEXT_SIZE.(s32), 20);

  while !rl.WindowShouldClose() {
    memory_visualizer_per_frame_update();

    reset_temporary_storage();
    entity_world_update(*world, rl.GetFrameTime());

    clear_buffer();
    entity_world_render(*world);

    rl.BeginDrawing();
      rl.ClearBackground(rl.BLACK);
      // Draw the buffer
      for y : 0..ROWS-1 {
        for x : 0..COLS-1 {
          cell := buffer[x][y];
          rl.DrawRectangle(x*tile_w, y*tile_h, tile_w, tile_h, cell.bg);

          // Draw the glyph
          glyph_index := rl.GetGlyphIndex(font, cell.glyph.(s32));
          rec := font.recs[glyph_index];
          pos := xy((x*tile_w).(float), (y*tile_h).(float));
          rl.DrawTextureRec(font.texture, rec, pos, cell.fg);
        }
      }

      edit_system(rl.GetFrameTime());

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