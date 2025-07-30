
SCREEN_WIDTH :: 1100;
SCREEN_HEIGHT :: 1100;

/// --- BEGIN ENTITY 

PlayerMove :: struct {
}

Command :: Tagged_Union(PlayerMove);

EntityWorld :: struct {
  entities: [..]Entity;
  entity_groups: [NUM_ENTITY_KIND][..]*Entity;
  cached_id_to_index: Table.Table(u32, s32); 
  
  // For the logic that doesn't fit as an entity but still wants update and such
  update_systems: [..]#type (*EntityWorld, float);
  render_systems: [..]#type ();

  queued_commands: [..]Command; // Gets flushed into commands at the start of every update 
  commands: [..]Command; // Gets flushed at the end of every update

  dirty: bool; // To indicate we need to rebuild our arrays
  next_id: u32 = 0;
}

EntityInitProc :: #type (w: *EntityWorld, e: *Entity);
EntityUpdateProc :: #type (w: *EntityWorld, *Entity, dt: float);
EntityRenderProc :: #type (w: *EntityWorld, e: *Entity);

empty_init :: (_: *EntityWorld, _: *Entity) {}
empty_update :: (_: *EntityWorld, _: *Entity, _: float) {}
empty_render :: (_: *EntityWorld, _: *Entity) {}

// Mega entity struct
Entity :: struct {
  id: u32;
  init_proc: EntityInitProc = empty_init;
  update_proc: EntityUpdateProc = empty_update;
  render_proc: EntityRenderProc = empty_render;
  kind: Entity_Kind;
}

NUM_ENTITY_KIND :: 0;
Entity_Kind :: enum u32 {
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
    it(world, dt);
  }

  for *world.entities {
    it.update_proc(world, it, dt);
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
    it.render_proc(world, it);
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
  new_e.init_proc(world, new_e);
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

color :: (r: u8, g: u8, b: u8) -> rl.Color {
  return rl.Color.{r, g, b, 255};
}

main :: () {
  rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Gnarly Jai");

  while !rl.WindowShouldClose() {

    rl.BeginDrawing();
      rl.ClearBackground(color(39, 38, 64));
      
    rl.EndDrawing();
  }
}

#import "Basic";
rl :: #import "raylib";
Table :: #import "Hash_Table";
#import "Tagged_Union";