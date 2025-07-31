
/*
D - door
L - lever
E - enemy
P - pit
K - kill tile
# - Wall
  ###
  #@#
  # #
  #K#
 #   #
 #L  #
 #DDD#
 # E #
#K   K# 
#K   K#
#K P K#
 #   # 
 #   #
*/

COLS: s16 : 41;
ROWS: s16 : 41;

tile_w: s16 = 24;
tile_h: s16 = 24;

GameState :: struct {
  edit_mode: bool = false;
  current_level: int = 0;
  glitcher_counter: float = 0.0;
  selected_point: SVector;
}
game_state: GameState;
world: EntityWorld;

SVector :: struct {
  x, y: s16;
}

operator == :: (left: SVector, right: SVector) -> bool {
  return left.x == right.x && left.y == right.y;
}

buffer: [COLS][ROWS]Cell;

/// --- BEGIN ENTITY 

PlayerMove :: struct {
  old_pos: SVector;
  new_pos: SVector;
  player: *Entity;
}

Command :: Tagged_Union(PlayerMove);

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

  pos: SVector;
  offset: Vector2;
  color: rl.Color;
  glyph: int;
  move_tick: s16;
  
  door_connections: [..]SVector;

  door_open: bool;
}

NUM_ENTITY_KIND :: 7;
Entity_Kind :: enum u32 {
  PLAYER;
  ENEMY;
  WALL;
  DOOR;
  LEVER;
  PIT;
  KILL_TILE;
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

is_walkable :: (pos: SVector) -> bool {
  entity := find_entity_at(pos);
  if entity == null {
    return true;
  }

  print("entity.kind = %\n", entity.kind);

  if entity.kind == .DOOR {
    return entity.door_open;
  }

  if entity.kind == {
    case .PLAYER; #through;
    case .ENEMY; #through;
    case .WALL; #through;
    case .LEVER; #through;
    case .PIT; #through;
    case .KILL_TILE; return false;
  }

  return true;
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

create_wall :: (pos: SVector) {
  wall: Entity;

  wall.kind = .WALL;

  wall.pos = pos;
  wall.color = color(100, 100, 100, 255);
  wall.glyph = 35;

  entity_world_add(*world, wall);
}

create_pit :: (pos: SVector) {
  pit: Entity;

  pit.kind = .PIT;

  pit.pos = pos;
  pit.color = color(255, 127, 80, 255);
  pit.glyph = 80;

  entity_world_add(*world, pit);
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
  door: Entity;

  door.kind = .DOOR;

  door.pos = pos;
  door.color = color(0, 139, 139, 255);
  door.glyph = 68;

  entity_world_add(*world, door);
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
    for world.commands {
      player_move := isa(it, PlayerMove);
      if player_move {
        sees_player, t := has_line_of_sight(enemy, player_move.player, 8);
        if sees_player {
          enemy.color = color(255, 20, 50, 255);
        } else {
          enemy.color = color(90, 90, 90, 255);
        }

        // Move?
        enemy.move_tick += 1;
        if enemy.move_tick % 2 == 0 && has_line_of_sight(enemy, player_move.player, 8) {
          move_enemy_towards_player(player_move.player, enemy);
        }
      }
    }
  }

  enemy.update_proc = enemy_update;

  enemy.pos = pos;
  enemy.move_tick = 0;
  enemy.color = color(90, 90, 90, 255);
  enemy.glyph = 69;

  entity_world_add(*world, enemy);
}

create_player :: () {
  move_player :: (player: *Entity, dx: s16, dy: s16) {
    new_pos := xy(player.pos.x + dx, player.pos.y + dy);
    // Check for wall
    if (!game_state.edit_mode && !is_walkable(new_pos)) || !is_valid(new_pos) then return;

    command: Command;
    set(*command, PlayerMove.{ player.pos, new_pos, player });
    entity_world_push_command(*world, command);

    player.pos = new_pos;
  }
 
  update_player :: (player: *Entity, dt: float) {
    if rl.IsKeyPressed(.KEY_D) move_player(player, 1, 0);
    if rl.IsKeyPressed(.KEY_A) move_player(player, -1, 0);
    if rl.IsKeyPressed(.KEY_S) move_player(player, 0, 1);
    if rl.IsKeyPressed(.KEY_W) move_player(player, 0, -1);

    if rl.IsKeyPressed(.KEY_C) {
      create_wall(xy(player.pos.x, player.pos.y)); // Give birth, right here, right now
      // create_enemy(world, xy(player.pos.x, player.pos.y)); // Give birth, right here, right now
      // create_glitcher(player.pos.x, player.pos.y); // Give birth, right here, right now
    }

    if rl.IsKeyPressed(.KEY_TAB) then game_state.edit_mode = !game_state.edit_mode;

    if rl.IsKeyPressed(.KEY_P) then print_level();
  }

  render_player :: (player: *Entity) {
    player_cell := *buffer[player.pos.x][player.pos.y];
    player_cell.fg = color(255, 0, 255, 255);
    player_cell.glyph = player.glyph;
  }

  player: Entity;
  player.kind = .PLAYER;
  player.update_proc = update_player;
  player.render_proc = render_player;

  player.pos = xy(1, 1);
  player.glyph = 64;

  entity_world_add(*world, player);
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

  file_name := tprint("./level_%.jai.in", game_state.current_level);
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
  
  if rl.IsMouseButtonPressed(.MOUSE_BUTTON_LEFT) && game_state.selected_point.x == -1 {
    mouse_pos := rl.GetMousePosition();
    mouse_pos.x /= rl.GetScreenWidth();
    mouse_pos.y /= rl.GetScreenHeight();

    grid_pos: SVector;
    grid_pos.x = (mouse_pos.x * COLS).(s16); 
    grid_pos.y = (mouse_pos.y * ROWS).(s16); 

    game_state.selected_point = grid_pos;
  }

  if rl.IsMouseButtonPressed(.MOUSE_BUTTON_RIGHT) {
    game_state.selected_point.x = -1;
  }

  if rl.IsKeyDown(.KEY_LEFT_ALT) {
    // Display some basic level info
    rl.GuiLabel(rl.Rectangle.{0, 0, 100, 100}, to_c_string(tprint("level = %", game_state.current_level)));
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
      if rl.GuiButton(rl.Rectangle.{10+80*3, height-50, 80, 30}, "PIT") {
        create_pit(game_state.selected_point);
        game_state.selected_point.x = -1;
      }
      if rl.GuiButton(rl.Rectangle.{10+80*4, height-50, 80, 30}, "KILL") {
        create_kill_tile(game_state.selected_point.x, game_state.selected_point.y);
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

      if game_state.edit_mode {
        cell.fg.a = 255;
      }
      
      cell.glyph = it.glyph;
    }
  }
}

is_basic_rendered :: (kind: Entity_Kind) -> bool {
  return kind == .WALL || kind == .ENEMY || kind == .KILL_TILE || kind == .DOOR || kind == .LEVER || kind == .PIT;
}

glyph_basic_update_system :: (dt: float) {
  for cmd : world.commands {
    player_move := isa(cmd, PlayerMove);
    if player_move {
      for *world.entities {
        if is_basic_rendered(it.kind) {
          it.color.a = get_lit_alpha(player_move.player.pos, it.pos, 9);
        }
      }
    }
  }
}

main :: () {
  rl.InitWindow(COLS * tile_w, ROWS * tile_h, "Glyph Test");
  rl.SetTargetFPS(60);
  font := rl.LoadFontEx("./font.ttf", tile_w, null, 0);

  entity_world_init(*world);
  array_add(*world.update_systems, kill_tile_system);
  array_add(*world.update_systems, glyph_basic_update_system);
  array_add(*world.render_systems, glyph_basic_render_system);

  // Fill up the world
  create_player();
  levels[game_state.current_level]();

  entity_world_rebuild(*world);

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