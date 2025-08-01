create_level :: () {
  pick_random_segment :: (prefabs: []string) -> string {
    some_rand := random_get();
    rand_index := some_rand % prefabs.count.(u64);
    return prefabs[rand_index];
  }

  spawn_segment(pick_random_segment(segments[0].prefabs), xy(0, 0));
  spawn_segment(pick_random_segment(segments[1].prefabs), xy(SEGMENT_SIZE, 0));
  spawn_segment(pick_random_segment(segments[2].prefabs), xy(0, SEGMENT_SIZE));
  spawn_segment(pick_random_segment(segments[3].prefabs), xy(SEGMENT_SIZE, SEGMENT_SIZE));
}

character_and_spawner :: struct{
  char: u8;
  spawner: #type (pos: SVector);
}.[
  .{ "E"[0].(u8), create_enemy },
  .{ "#"[0].(u8), create_wall },
  .{ "D"[0].(u8), create_door },
  .{ "L"[0].(u8), create_lever },
  .{ "K"[0].(u8), create_kill_tile },
  .{ "F"[0].(u8), create_fire },
  .{ "d"[0].(u8), create_diggable },
  .{ "G"[0].(u8), create_goal },
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
    if prefab[it] != "_"[0] && !exists_as_spawner(prefab[it]) {
      continue;
    }

    c := prefab[it];
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

test :: () {
}

#load "segments.jai";