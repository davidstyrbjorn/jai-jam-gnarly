
CHARACTER_GLYPHS :: GLYPH.[.SWIPER, .TINKERER, .MARTYR, .DIGGER]; // Order matters

GLYPH :: enum int {
  SWIPER :: 115;
  TINKERER :: 116;
  MARTYR :: 109;
  DIGGER :: 100;
}

Node :: struct {
  pos: SVector;
  g_cost: s16;
  h_cost: s16;
  f_cost: s16;
}

FIRE_GLYPHS :: int.[126, 42, 46];

Cell :: struct {
  glyph: int;
  fg, bg: rl.Color; 

  value: float = 0.0;
  override_flag: bool;
  prev_override_flag: bool;
  override_glyph: int;
  override_fg, override_bg: rl.Color;
}

directions := SVector.[
  SVector.{1, 0},
  SVector.{-1, 0},
  SVector.{0, 1},
  SVector.{0, -1},
];

has_line_of_sight :: (from: *Entity, to: *Entity, max_distance: s16) -> bool, float {
  dx := abs(to.pos.x - from.pos.x);
  dy := abs(to.pos.y - from.pos.y);
  steps := max(dx, dy);
  
  // Simple out of bounds for visibility check
  if dx > max_distance || dy > max_distance then return false, 0.0;

  x := from.pos.x;
  y := from.pos.y;
  n := 1 + dx + dy;
  x_inc := ifx to.pos.x > from.pos.x then cast(s16)1 else cast(s16)-1;
  y_inc := ifx to.pos.y > from.pos.y then cast(s16)1 else cast(s16)-1;
  error := dx - dy;

  dx *= 2;
  dy *= 2;

  distance_walked: s16 = 0;

  while n > 0 {

    walkable, _ := is_walkable(xy(x, y));
    if !walkable return false, 0.0; // Lose state, hard ray

    if x == to.pos.x && y == to.pos.y {
      t := 1.0 - (distance_walked.(float) / max_distance);
      return true, t; // Win state
    }

    if error > 0 {
      x += x_inc;
      error -= dy;
    } else {
      y += y_inc;
      error += dx;
    }

    distance_walked += 1;
    if distance_walked > max_distance then return false, 0.0;

    n -= 1;
  }

  return false, 0.0;
}

move_enemy_towards_player :: (player: *Entity, enemy: *Entity) -> bool {
  // Are we already ONE cell away from the player? let's not move into them
  if abs(enemy.pos.x - player.pos.x) + abs(enemy.pos.y - player.pos.y) <= 1 then return true;

  open_list: [..]Node;
  defer array_free(open_list);
  closed: [COLS][ROWS]bool;

  came_from_pos: [COLS][ROWS]SVector;
  for y : 0..ROWS-1 {
    for x : 0..COLS-1 {
      came_from_pos[x][y] = xy(-1, -1);
    }
  }

  start := Node.{
    xy(enemy.pos.x, enemy.pos.y), 
    0,
    heuristic(enemy.pos, player.pos),
    0
  };
  start.f_cost = start.g_cost + start.h_cost;

  array_add(*open_list, start);

  found := false;
  while open_list.count > 0 {
    // Find node with lowest f cost
    current_index := 0;
    for 1..open_list.count-1 {
      if open_list[it].f_cost < open_list[current_index].f_cost then current_index = it;
    }

    current := open_list[current_index];
    array_ordered_remove_by_index(*open_list, current_index);

    // Win condition
    if current.pos.x == player.pos.x && current.pos.y == player.pos.y {
      found = true;
      break;
    }

    closed[current.pos.x][current.pos.y] = true;

    for directions {
      new_pos := xy(current.pos.x + it.x, current.pos.y + it.y);

      // Not a valid position, or already visited?
      if !is_valid(new_pos) then continue;
      walkable, _ := is_walkable(new_pos);
      if closed[new_pos.x][new_pos.y] || !walkable then continue;
      by_id, occupied := is_occupied_by_enemy(new_pos);
      if occupied && by_id != enemy.id then continue; // Avoid walking into another enemy 

      tentative_g := current.g_cost + 1;
      
      // Check if already in open list with a better g cost
      in_open := false;
      for node : open_list {
        if node.pos.x == new_pos.x && node.pos.y == new_pos.y && tentative_g >= node.g_cost {
          in_open = true;
          break;
        }
      }

      if in_open then continue;

      came_from_pos[new_pos.x][new_pos.y] = current.pos;
      
      h := heuristic(new_pos, player.pos);
      array_add(*open_list, Node.{
        new_pos,
        tentative_g,
        h,
        tentative_g + h,
      });
    }
  }

  if !found then return false; // Lose condition

  // Reconstruct the path
  pos := player.pos;
  path: [..]SVector;
  defer array_free(path);

  while pos.x != enemy.pos.x || pos.y != enemy.pos.y {
    array_add(*path, pos);
    tmp := came_from_pos[pos.x][pos.y];
    if tmp.x == -1 || tmp.y == -1 then return true; // TODO: Why do we need this?
    pos = tmp;
  }

  last := path[path.count-1];
  enemy.pos.x = last.x;
  enemy.pos.y = last.y;

  return true;
}

get_lit_alpha :: (light_pos: SVector, from: SVector, dist_to_dark: s16) -> u8 {
  euclidian_distance := abs(light_pos.x - from.x) + abs(light_pos.y - from.y);
  if euclidian_distance > dist_to_dark {
    return 0;
  }
  t := 1.0 - euclidian_distance.(float)/dist_to_dark;
  return (255 * t).(u8);
}

is_direct_neighbour :: (pos1: SVector, pos2: SVector) -> bool {
    return (abs(pos1.x - pos2.x) == 1 && pos1.y == pos2.y) ||
           (pos1.x == pos2.x && abs(pos1.y - pos2.y) == 1);
}