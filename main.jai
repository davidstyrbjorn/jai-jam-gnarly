
SCREEN_WIDTH :: 1100;
SCREEN_HEIGHT :: 1100;

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