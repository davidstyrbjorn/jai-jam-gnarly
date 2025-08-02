
potential_goal_positions: [..]SVector;
potetial_enemy_positions: [..]SVector;
potential_coin_positions: [..]SVector;

CHANCE_OF_ENEMY :: .5;

// @AI! Generated function for simply creating empty segments with gaps
generate_walled_segment :: (up_gap: bool, right_gap: bool, down_gap: bool, left_gap: bool, gap_size: int = 2) {
    // We calculate the starting position of the gap to keep it centered.
    start_of_gap := (SEGMENT_SIZE / 2) - (gap_size / 2);

    // The outer loop iterates over the rows (y-axis).
    for y: 0..SEGMENT_SIZE-1 {
        // The inner loop iterates over the columns (x-axis) for the current row.
        for x: 0..SEGMENT_SIZE-1 {
            is_top_wall    := y == 0;
            is_bottom_wall := y == SEGMENT_SIZE - 1;
            is_left_wall   := x == 0;
            is_right_wall  := x == SEGMENT_SIZE - 1;

            char: string = "_"; // Default to an empty space

            if is_top_wall {
                // Check if the current 'x' position falls within the gap's range.
                is_in_gap := x >= start_of_gap && x < start_of_gap + gap_size;
                char = ifx up_gap && is_in_gap then "_" else "#";
            } else if is_bottom_wall {
                is_in_gap := x >= start_of_gap && x < start_of_gap + gap_size;
                char = ifx down_gap && is_in_gap then "_" else "#";
            } else if is_left_wall {
                // For vertical walls, we check against the 'y' position.
                is_in_gap := y >= start_of_gap && y < start_of_gap + gap_size;
                char = ifx left_gap && is_in_gap then "_" else "#";
            } else if is_right_wall {
                is_in_gap := y >= start_of_gap && y < start_of_gap + gap_size;
                char = ifx right_gap && is_in_gap then "_" else "#";
            }
            
            print("%", char);
        }
        // A newline is printed after each row is complete.
        print("\n");
    }
}

// #run {
//   GAP_SIZE :: 4;
//   print("BOTTOM_LEFT\n");
//   generate_walled_segment(true, true, false, false, GAP_SIZE);
//   print("DONE\n");

//   print("BOTTOM_RIGHT\n");
//   generate_walled_segment(true, false, false, true, GAP_SIZE);
//   print("DONE\n");

//   print("TOP_RIGHT\n");
//   generate_walled_segment(false, false, true, true, GAP_SIZE);
//   print("DONE\n");

//   print("TOP LEFT\n");
//   generate_walled_segment(false, true, true, false, GAP_SIZE);
//   print("DONE\n");
// }

create_level :: () {
  pick_random_segment :: (prefabs: []string) -> string {
    some_rand := random_get();
    rand_idx := some_rand % prefabs.count.(u64);
    return prefabs[rand_idx];
  }

  spawn_segment(pick_random_segment(segments[0].prefabs), xy(0, 0));
  spawn_segment(pick_random_segment(segments[1].prefabs), xy(SEGMENT_SIZE, 0));
  spawn_segment(pick_random_segment(segments[2].prefabs), xy(0, SEGMENT_SIZE));
  spawn_segment(pick_random_segment(segments[3].prefabs), xy(SEGMENT_SIZE, SEGMENT_SIZE));

  assert(potential_goal_positions.count > 0);

  // Always initalise with placing a goal since we always start with .REACH_END
  rand_idx := random_get() % potential_goal_positions.count.(u64);
  create_goal(potential_goal_positions[rand_idx]);

  for potetial_enemy_positions {
    if random_get_zero_to_one() < CHANCE_OF_ENEMY {
      create_enemy(it);
    }
  }
}

create_up_laser :: (pos: SVector) {
  create_laser(pos, xy(0, -1));
}

create_down_laser :: (pos: SVector) {
  create_laser(pos, xy(0, 1));
}

create_right_laser :: (pos: SVector) {
  create_laser(pos, xy(1, 0));
}

create_left_laser :: (pos: SVector) {
  create_laser(pos, xy(-1, 0));
}

character_and_spawner :: struct{
  char: u8;
  spawner: #type (pos: SVector);
}.[
  .{ "#"[0].(u8), create_wall },
  .{ "D"[0].(u8), create_door },
  .{ "L"[0].(u8), create_lever },
  .{ "K"[0].(u8), create_kill_tile },
  .{ "F"[0].(u8), create_fire },
  .{ "d"[0].(u8), create_diggable },
  .{ ">"[0].(u8), create_right_laser },
  .{ "<"[0].(u8), create_left_laser },
  .{ "^"[0].(u8), create_up_laser },
  .{ "v"[0].(u8), create_down_laser },
  .{ "V"[0].(u8), create_vision },
];

exists_as_spawner :: (c: u8) -> bool {
  for character_and_spawner {
    if it.char == c then return true;
  }
  return false;
}

spawn_segment :: (prefab: string, start: SVector) {
  pos := start;
  counter := 0;
  for 0..prefab.count-1 {
    c := prefab[it];
    if c == "G"[0] {
      array_add(*potential_goal_positions, pos);
    }
    else if c == "E"[0] {
      array_add(*potetial_enemy_positions, pos);
    }
    else if c == "$"[0] {
      array_add(*potential_coin_positions, pos);
    }
    else if c != "_"[0] && !exists_as_spawner(c) {
      continue;
    }

    for character_and_spawner {
      if it.char == c then it.spawner(pos);
    }

    counter += 1;
    pos.x += 1;
    if counter == SEGMENT_SIZE {
      counter = 0;
      pos.y += 1;
      pos.x = start.x;
    }
  }
}

OPEN_DIRECTIONS :: enum {
  UP :: 0;
  RIGHT :: 1;
  DOWN :: 2;
  LEFT :: 3;
}

SegmentSelection :: struct {
  openness: [4]bool;
  prefabs: []string;
}

segments: []SegmentSelection = .[
  .{.[false, true, true, false], TOP_LEFT },
  .{.[false, false, true, true], TOP_RIGHT },
  .{.[true, true, false, false], BOTTOM_LEFT },
  .{.[true, false, false, true], BOTTOM_RIGHT },
];

#load "segments.jai";